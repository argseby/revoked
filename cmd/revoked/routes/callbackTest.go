package routes

import (
	"errors"
	"net/http"
	"revoked/cmd/revoked/services"
	"revoked/util"
	"strconv"
	"strings"

	"github.com/pocketbase/pocketbase/core"
)

// CallbackTestRoute exposes POST /api/requests/callback-test: send one sample
// delivery to a callback URL and report what came back.
//
// The URL travels in the body rather than being read off a saved request, so
// the owner can check a hook while still typing it. It is still the server that
// fetches it, through the same client a real delivery uses — a test fired from
// the client would prove nothing about whether this host can reach the target,
// and would skip the SSRF policy that decides whether it may.
func CallbackTestRoute(app core.App) {
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		e.Router.POST("/api/requests/callback-test", func(re *core.RequestEvent) error {
			if re.Auth == nil || re.Auth.Collection().Name != util.Coll.Users {
				return re.UnauthorizedError("Authentication required", nil)
			}
			// An on-demand fetch is a livelier probe than waiting for a
			// submission, so it gets a budget of its own, per caller.
			if !allowRequest(re, callbackTestLimiter, re.Auth.Id) {
				return rateLimitedResponse(re)
			}

			body := struct {
				URL       string `json:"url"`
				RequestID string `json:"requestId"`
			}{}
			if err := re.BindBody(&body); err != nil {
				return re.BadRequestError("Invalid request body", nil)
			}
			url := strings.TrimSpace(body.URL)
			if url == "" {
				return re.BadRequestError("A callback URL is required", nil)
			}

			// An unsaved request has no id yet; a saved one lends its own, so
			// the X-Revoked-Request header the hook checks is the real value.
			requestID := "example-request-id"
			slug := "example-request"
			if id := strings.TrimSpace(body.RequestID); id != "" {
				req, err := app.FindRecordById(util.Coll.Requests, id)
				if err != nil || req == nil {
					return re.NotFoundError(util.Errors.RequestNotFound.ErrorText, nil)
				}
				if req.GetString(util.Fields.Request.User) != re.Auth.Id {
					return re.ForbiddenError("Not your request", nil)
				}
				requestID = req.Id
				slug = req.GetString(util.Fields.Request.Slug)
			}

			status, err := services.PostCallback(url, requestID,
				services.SampleCallbackPayload(requestID, slug))

			// A refusal is the answer to the question, not an error in asking
			// it: the result rides in the body so the caller can show what
			// happened rather than a bare status. `code` separates the three
			// failures a caller acts on differently — this server may not go
			// there, it could not get there, it got there and was rebuffed —
			// because the prose around them all reads like "not found".
			if err != nil {
				code := "unreachable"
				if errors.Is(err, util.ErrCallbackURLBlocked) {
					code = "blocked"
				}
				return re.JSON(http.StatusOK, map[string]any{
					"ok":     false,
					"status": 0,
					"code":   code,
					"detail": err.Error(),
				})
			}
			code := "ok"
			if status >= 400 {
				code = "status"
			}
			return re.JSON(http.StatusOK, map[string]any{
				"ok":     status < 400,
				"status": status,
				"code":   code,
				"detail": "Endpoint answered " + strconv.Itoa(status),
			})
		})

		return e.Next()
	})
}
