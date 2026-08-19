package routes

import (
	"encoding/json"
	"net/http"
	"revoked/util"
	"time"

	"github.com/pocketbase/pocketbase/core"
)

// RequestGrantsRoute exposes GET /api/requests/{id}/links, the request owner's view
// of the links minted under it. Resolution to the responder's current values happens
// server-side because the requester cannot read those vault records directly.
func RequestGrantsRoute(app core.App) {
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		e.Router.GET("/api/requests/{id}/links", func(re *core.RequestEvent) error {
			if re.Auth == nil || re.Auth.Collection().Name != util.Coll.Users {
				return re.UnauthorizedError("Authentication required", nil)
			}
			req, err := app.FindRecordById(util.Coll.Requests, re.Request.PathValue("id"))
			if err != nil || req == nil {
				return re.NotFoundError(util.Errors.RequestNotFound.ErrorText, nil)
			}
			if req.GetString(util.Fields.Request.User) != re.Auth.Id {
				return re.ForbiddenError("Not your request", nil)
			}

			links, err := app.FindRecordsByFilter(
				util.Coll.Links,
				"request = {:r}", "-created", 200, 0,
				map[string]any{"r": req.Id},
			)
			if err != nil {
				return re.InternalServerError("Failed to load links", nil)
			}
			items := make([]map[string]any, 0, len(links))
			for _, link := range links {
				items = append(items, resolveLinkPayload(app, link))
			}
			return re.JSON(http.StatusOK, map[string]any{"items": items})
		})

		return e.Next()
	})
}

// resolveLinkPayload projects a link into the requester-facing shape, substituting
// each grant's live vault value for the snapshot. Only an active link resolves;
// otherwise every granted key drops, as does a grant whose record was deleted —
// never a stale copy. Non-granted keys (guest answers) fall through from the snapshot.
func resolveLinkPayload(app core.App, link *core.Record) map[string]any {
	status := link.GetString(util.Fields.Link.Status)

	data := map[string]any{}
	if s := link.GetString(util.Fields.Link.Data); s != "" {
		_ = json.Unmarshal([]byte(s), &data)
	}
	grants := map[string]string{}
	if s := link.GetString(util.Fields.Link.Grants); s != "" {
		_ = json.Unmarshal([]byte(s), &grants)
	}

	live := map[string]bool{}
	if status != util.StatusActive {
		for key := range grants {
			delete(data, key)
		}
	} else {
		for key, recId := range grants {
			rec, err := app.FindRecordById(util.Coll.Records, recId)
			if err != nil || rec == nil {
				delete(data, key)
				live[key] = false
				continue
			}
			data[key] = rec.GetString(util.Fields.Record.Value)
			live[key] = true
		}
	}

	// Resolved so the requester can show "Signed by <name> (<domain>)" rather than
	// a bare flag.
	identityName := ""
	identityDomain := ""
	if idStr := link.GetString(util.Fields.Link.Identity); idStr != "" {
		if idRec, err := app.FindRecordById(util.Coll.Identities, idStr); err == nil && idRec != nil {
			identityName = idRec.GetString(util.Fields.Identity.Name)
			identityDomain = idRec.GetString(util.Fields.Identity.DomainAtIssue)
		}
	}

	return map[string]any{
		"id":             link.Id,
		"slug":           link.GetString(util.Fields.Link.Slug),
		"request":        link.GetString(util.Fields.Link.Request),
		"identity":       link.GetString(util.Fields.Link.Identity),
		"identityName":   identityName,
		"identityDomain": identityDomain,
		"identifier":     link.GetString(util.Fields.Link.Identifier),
		"senderName":     link.GetString(util.Fields.Link.SenderName),
		"status":         status,
		"data":           data,
		"live":           live,
		"created":        link.GetDateTime(util.Fields.Link.Created).Time().UTC().Format(time.RFC3339),
	}
}
