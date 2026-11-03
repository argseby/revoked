package routes

import (
	"crypto/subtle"
	"encoding/json"
	"errors"
	"net/http"
	"revoked/cmd/revoked/server"
	"revoked/cmd/revoked/services"
	"revoked/util"
	"strings"
	"time"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/security"
	"github.com/pocketbase/pocketbase/tools/types"
)

// connectLimiter bounds code exchanges per IP: a code is short-lived and
// single-use, but guessing at the endpoint should still get nowhere fast. It
// leaves room for a page or two waiting for the owner's answer, asking every
// few seconds.
var connectLimiter = util.NewRateLimiter(util.LimitFromEnv("RATELIMIT_CONNECT_REQUESTS", 60), time.Minute)

// ConnectionsRoute exposes connected tools.
//
// A tool is connected from the app, never from the tool's own page:
//
//	POST /api/connections/authorize   (the owner, signed in — from the app)
//	    finds or creates the connection for the tool's origin and returns a
//	    one-time code, bound to the tool's PKCE challenge and return address.
//	    With "reuse" it only lets another browser into a connection the owner
//	    already agreed to: nothing about the connection changes, its expiry
//	    least of all.
//	POST /api/connect/token           (the tool)
//	    exchanges code + verifier for a bearer token for this browser.
//
// The code reaches the tool in its return address, which the app opens in a
// browser — not necessarily the one that asked. A tool that knows the owner's
// server can ask for the answer itself instead: the app authorizes with
// "poll", opens nothing, and the page that asked exchanges its verifier alone,
// again and again until the owner has answered (202 until then). Such an
// answer is not bound to the owner's browser by a redirect, so the app never
// gives one unasked: the owner compares a code both sides derive from the
// challenge. The server holds the request to the tool's origin.
//
// With that token (header X-Revoked-Connection) a tool can:
//
//	GET    /api/connection            the links its proposals became: status,
//	                                  views, expiry — and the URL only of
//	                                  links the owner handed over, while
//	                                  the owner lets it receive links
//	                                  (allowHandOver).
//	POST   /api/connection/links/{id}/revoke
//	                                  revoke one of those links, when the
//	                                  owner allowed it (allowRevoke).
//	GET    /api/connection/vault[/{id}]
//	                                  read the owner's vault, when the owner
//	                                  allowed it (allowVaultRead) and the token
//	                                  was not collected by polling.
//	DELETE /api/connection            disconnect itself.
//
// The owner decides these permissions when connecting and changes them later
// with
//
//	POST /api/connections/{id}/permissions   {"allowRevoke"?, "allowHandOver"?, "allowVaultRead"?}
//
// allowVaultRead can only be withdrawn there: granting it takes a fresh
// connect, so the owner sees the tool's own request for it.
//
// and can stop the tool altogether:
//
//	POST /api/connections/{id}/pause         refuses its tokens, holds its links
//	POST /api/connections/{id}/resume        undoes that
//	POST /api/connections/{id}/disconnect    {"revokeLinks"?}
//
// A token is not a PocketBase auth record, so no collection rule ever admits
// it: the vault routes in connectionVault.go are the only way it reads one. Nor does a tool keep anything here — what it
// has to remember about a proposal travels in the link's ref and label.
//
// A connection lasts util.ConnectionTTL from the last time the owner connected
// the tool; after that its tokens are refused, and deleted when the owner
// connects it again. What a tool does is written to the audit log.
func ConnectionsRoute(app core.App, root *server.RootKey) {
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		e.Router.POST("/api/connections/authorize", func(re *core.RequestEvent) error {
			if re.Auth == nil || re.Auth.Collection().Name != util.Coll.Users {
				return re.UnauthorizedError(util.Errors.NotAuthenticated.ErrorCode, nil)
			}
			workspace := re.Auth.GetString(util.Fields.User.ActiveWorkspace)
			if workspace == "" {
				return re.BadRequestError(util.Errors.InvalidActiveWorkspace.ErrorCode, nil)
			}

			var body struct {
				ClientId    string `json:"clientId"`
				ClientName  string `json:"clientName"`
				RedirectUri string `json:"redirectUri"`
				Challenge   string `json:"challenge"`
				connectionGrant
				// Set when the owner was not asked again: the tool is already
				// connected and another of their browsers wants in. That takes
				// a live connection and leaves it exactly as it was.
				Reuse bool `json:"reuse"`
				// Set when the page that asked collects the answer itself, with
				// its verifier, instead of being handed a code.
				Poll bool `json:"poll"`
			}
			if err := re.BindBody(&body); err != nil {
				return re.BadRequestError("Invalid request body", nil)
			}
			origin, ok := util.NormalizeOrigin(body.ClientId)
			if !ok {
				return appErrorResponse(re, http.StatusBadRequest, &util.Errors.ConnectionClientInvalid)
			}
			if !util.RedirectWithinOrigin(body.RedirectUri, origin) {
				return appErrorResponse(re, http.StatusBadRequest, &util.Errors.ConnectionRedirectInvalid)
			}
			if !util.ValidPKCE(body.Challenge) {
				return appErrorResponse(re, http.StatusBadRequest, &util.Errors.ConnectionChallengeInvalid)
			}
			// A polled answer is tied to the owner only by a code anyone can
			// read out to them, so it must never carry the vault.
			if body.Poll && body.AllowVaultRead != nil && *body.AllowVaultRead {
				return appErrorResponse(re, http.StatusBadRequest, &util.Errors.ConnectionVaultPolled)
			}
			name := strings.Join(strings.Fields(body.ClientName), " ")
			if len([]rune(name)) > 40 {
				name = string([]rune(name)[:40])
			}

			granter := services.GranterScopes(app, re.Auth, workspace, false)
			var code, connectionID string
			var saved *core.Record
			var refused *util.AppError
			err := app.RunInTransaction(func(tx core.App) error {
				conn, err := tx.FindFirstRecordByFilter(util.Coll.Connections,
					"user = {:user} && workspace = {:ws} && clientId = {:client}",
					dbx.Params{"user": re.Auth.Id, "ws": workspace, "client": origin})
				if err != nil || conn == nil {
					if body.Reuse {
						return errNotConnected
					}
					coll, err := tx.FindCollectionByNameOrId(util.Coll.Connections)
					if err != nil {
						return err
					}
					conn = core.NewRecord(coll)
					conn.Set(util.Fields.Connection.User, re.Auth.Id)
					conn.Set(util.Fields.Connection.Workspace, workspace)
					conn.Set(util.Fields.Connection.ClientId, origin)
				}
				// A pause holds until the owner lifts it. Connecting again is not
				// that, because a tool can ask for it at any time.
				if conn.GetBool(util.Fields.Connection.Paused) {
					return errConnectionPaused
				}
				expired := !conn.IsNew() && util.ConnectionExpired(conn.GetDateTime(util.Fields.Connection.ExpiresAt).Time())
				if body.Reuse {
					// Without the owner's say nothing is renewed: a tool that
					// could open the app on its own would otherwise never lapse.
					if expired {
						return errNotConnected
					}
				} else {
					if name != "" {
						conn.Set(util.Fields.Connection.ClientName, name)
					}
					// Tokens that lapsed stay dead: renewing the connection must
					// not bring a browser back that the owner did not reconnect.
					if expired {
						stale, err := tx.FindAllRecords(util.Coll.ConnectionTokens,
							dbx.HashExp{util.Fields.ConnectionToken.Connection: conn.Id})
						if err != nil {
							return err
						}
						for _, row := range stale {
							if err := tx.Delete(row); err != nil {
								return err
							}
						}
					}
					if refused = applyConnectionGrant(tx, conn, body.connectionGrant, granter); refused != nil {
						return errConnectionGrant
					}
					conn.Set(util.Fields.Connection.ExpiresAt, time.Now().Add(util.ConnectionTTL))
					if err := tx.Save(conn); err != nil {
						return err
					}
					if err := ensureOwnSection(tx, conn, body.connectionGrant); err != nil {
						return err
					}
				}
				saved = conn

				tokens, err := tx.FindCollectionByNameOrId(util.Coll.ConnectionTokens)
				if err != nil {
					return err
				}
				code = security.RandomString(48)
				row := core.NewRecord(tokens)
				row.Set(util.Fields.ConnectionToken.Connection, conn.Id)
				row.Set(util.Fields.ConnectionToken.CodeHash, util.HashToken(code))
				row.Set(util.Fields.ConnectionToken.CodeChallenge, body.Challenge)
				row.Set(util.Fields.ConnectionToken.CodeExpiresAt, time.Now().Add(util.ConnectionCodeTTL))
				row.Set(util.Fields.ConnectionToken.RedirectUri, strings.TrimSpace(body.RedirectUri))
				row.Set(util.Fields.ConnectionToken.Poll, body.Poll)
				connectionID = conn.Id
				return tx.Save(row)
			})
			if errors.Is(err, errConnectionGrant) {
				return appErrorResponse(re, http.StatusBadRequest, refused)
			}
			if errors.Is(err, errNotConnected) {
				return appErrorResponse(re, http.StatusConflict, &util.Errors.ConnectionNotConnected)
			}
			if errors.Is(err, errConnectionPaused) {
				return appErrorResponse(re, http.StatusConflict, &util.Errors.ConnectionPaused)
			}
			if err != nil {
				return re.InternalServerError("Failed to connect", err)
			}
			action := auditToolAuthorized
			if body.Reuse {
				action = auditToolBrowserAdded
			}
			var extra map[string]any
			if body.Poll {
				extra = map[string]any{"poll": true}
			}
			auditConnection(app, re, saved, action, extra)
			return re.JSON(http.StatusOK, map[string]any{"code": code, "connectionId": connectionID})
		})

		e.Router.POST("/api/connect/token", func(re *core.RequestEvent) error {
			if !allowRequest(re, connectLimiter, "") {
				return rateLimitedResponse(re)
			}
			var body struct {
				Code        string `json:"code"`
				Verifier    string `json:"verifier"`
				RedirectUri string `json:"redirectUri"`
			}
			if err := re.BindBody(&body); err != nil {
				return re.BadRequestError("Invalid request body", nil)
			}
			invalid := func() error {
				return appErrorResponse(re, http.StatusBadRequest, &util.Errors.ConnectionGrantInvalid)
			}
			if !util.ValidPKCE(body.Verifier) {
				return invalid()
			}
			// Without a code the page is asking for an answer the app left for
			// it. Only a browser on the tool's own origin may collect one.
			polled := body.Code == ""
			origin, _ := util.NormalizeOrigin(re.Request.Header.Get("Origin"))

			var token string
			var conn *core.Record
			spent, pending := false, false
			err := app.RunInTransaction(func(tx core.App) error {
				var row *core.Record
				var err error
				if polled {
					row, err = tx.FindFirstRecordByFilter(util.Coll.ConnectionTokens,
						"codeChallenge = {:challenge} && codeChallenge != '' && poll = true",
						dbx.Params{"challenge": util.PKCEChallenge(body.Verifier)})
					if err != nil || row == nil {
						// The owner has not answered yet, or never will.
						pending = true
						return nil
					}
				} else {
					row, err = tx.FindFirstRecordByFilter(util.Coll.ConnectionTokens,
						"codeHash = {:hash} && codeHash != ''",
						dbx.Params{"hash": util.HashToken(body.Code)})
					if err != nil || row == nil {
						return errGrant
					}
				}
				// A code is spent the moment anyone presents it, right or wrong:
				// a stolen code cannot be retried against the verifier.
				challenge := row.GetString(util.Fields.ConnectionToken.CodeChallenge)
				expires := row.GetDateTime(util.Fields.ConnectionToken.CodeExpiresAt)
				redirect := row.GetString(util.Fields.ConnectionToken.RedirectUri)
				row.Set(util.Fields.ConnectionToken.CodeHash, "")
				row.Set(util.Fields.ConnectionToken.CodeChallenge, "")

				ok := !expires.IsZero() && expires.Time().After(time.Now()) &&
					strings.TrimSpace(body.RedirectUri) == redirect &&
					subtle.ConstantTimeCompare([]byte(util.PKCEChallenge(body.Verifier)), []byte(challenge)) == 1
				if ok {
					owner, err := tx.FindRecordById(util.Coll.Connections,
						row.GetString(util.Fields.ConnectionToken.Connection))
					ok = err == nil && !owner.GetBool(util.Fields.Connection.Paused) &&
						(!polled || owner.GetString(util.Fields.Connection.ClientId) == origin)
				}
				if !ok {
					// Committed, not rolled back: the spent code stays spent.
					spent = true
					return tx.Delete(row)
				}

				token = security.RandomString(48)
				row.Set(util.Fields.ConnectionToken.TokenHash, util.HashToken(token))
				row.Set(util.Fields.ConnectionToken.LastUsedAt, types.NowDateTime())
				if err := tx.Save(row); err != nil {
					return err
				}
				conn, err = tx.FindRecordById(util.Coll.Connections,
					row.GetString(util.Fields.ConnectionToken.Connection))
				return err
			})
			if errors.Is(err, errGrant) || (err == nil && spent) {
				return invalid()
			}
			if err == nil && pending {
				return re.JSON(http.StatusAccepted, map[string]any{"pending": true})
			}
			if err != nil || conn == nil {
				return re.InternalServerError("Failed to exchange code", err)
			}
			auditConnection(app, re, conn, auditToolConnected, nil)
			view := connectionGrantView(conn, nil)
			view["id"] = conn.Id
			view["clientName"] = conn.GetString(util.Fields.Connection.ClientName)
			view["expiresAt"] = conn.GetString(util.Fields.Connection.ExpiresAt)
			return re.JSON(http.StatusOK, map[string]any{"token": token, "connection": view})
		})

		e.Router.GET("/api/connection", func(re *core.RequestEvent) error {
			token, conn, first, ok := connectionTokenFromRequest(app, re)
			if !ok {
				return nil
			}
			// One entry per stretch of use, not per poll.
			if first {
				auditConnection(app, re, conn, auditToolRead, nil)
			}
			links, err := app.FindRecordsByFilter(util.Coll.Links,
				"connection = {:conn}", "-created", 500, 0, dbx.Params{"conn": conn.Id})
			if err != nil {
				return re.InternalServerError("Failed to list links", err)
			}
			out := make([]map[string]any, 0, len(links))
			for _, l := range links {
				out = append(out, connectionLinkView(conn, l, root.Domain()))
			}
			requests, err := connectionRows(app, util.Coll.Requests, conn.Id, connectionRequestView)
			if err != nil {
				return re.InternalServerError("Failed to list requests", err)
			}
			attestations, err := connectionRows(app, util.Coll.Attestations, conn.Id, connectionAttestationView)
			if err != nil {
				return re.InternalServerError("Failed to list attestations", err)
			}
			checks, err := connectionRows(app, util.Coll.AttestationChecks, conn.Id, connectionCheckView)
			if err != nil {
				return re.InternalServerError("Failed to list checks", err)
			}
			view := connectionGrantView(conn, token)
			view["id"] = conn.Id
			view["clientId"] = conn.GetString(util.Fields.Connection.ClientId)
			view["clientName"] = conn.GetString(util.Fields.Connection.ClientName)
			view["expiresAt"] = conn.GetString(util.Fields.Connection.ExpiresAt)
			view["links"] = out
			view["requests"] = requests
			view["attestations"] = attestations
			view["checks"] = checks
			return re.JSON(http.StatusOK, view)
		})

		// Ending a share is the one thing a tool may change, and only for a
		// link its own proposal became. The owner is notified like for any
		// other revocation.
		e.Router.POST("/api/connection/links/{id}/revoke", func(re *core.RequestEvent) error {
			conn, _, ok := connectionFromRequest(app, re)
			if !ok {
				return nil
			}
			if !connectionHas(conn, util.ScopeLinkUpdate) {
				return appErrorResponse(re, http.StatusForbidden, &util.Errors.ConnectionRevokeNotAllowed)
			}
			link, err := app.FindRecordById(util.Coll.Links, re.Request.PathValue("id"))
			if err != nil || link == nil || link.GetString(util.Fields.Link.Connection) != conn.Id {
				return re.NotFoundError("Link not found", nil)
			}
			if link.GetString(util.Fields.Link.Status) != util.StatusRevoked {
				link.Set(util.Fields.Link.Status, util.StatusRevoked)
				if err := app.Save(link); err != nil {
					return re.InternalServerError("Failed to revoke the link", err)
				}
				auditConnection(app, re, conn, auditToolRevokedLink, map[string]any{"link": link.Id})
			}
			return re.JSON(http.StatusOK, connectionLinkView(conn, link, root.Domain()))
		})

		// Closing a request stops new answers; the answers already given stay
		// their responders' grants.
		e.Router.POST("/api/connection/requests/{id}/close", func(re *core.RequestEvent) error {
			conn, _, ok := connectionFromRequest(app, re)
			if !ok {
				return nil
			}
			if !connectionHas(conn, util.ScopeRequestUpdate) {
				return appErrorResponse(re, http.StatusForbidden, &util.Errors.ConnectionRevokeNotAllowed)
			}
			f := util.Fields.Request
			request, err := app.FindRecordById(util.Coll.Requests, re.Request.PathValue("id"))
			if err != nil || request == nil || request.GetString(f.Connection) != conn.Id {
				return re.NotFoundError("Request not found", nil)
			}
			if request.GetString(f.Status) != util.StatusRevoked {
				request.Set(f.Status, util.StatusRevoked)
				request.Set(f.HeldPaused, false)
				if err := app.Save(request); err != nil {
					return re.InternalServerError("Failed to close the request", err)
				}
				auditConnection(app, re, conn, auditToolClosedRequest, map[string]any{"request": request.Id})
			}
			return re.JSON(http.StatusOK, connectionRequestView(request))
		})

		// Revoking an attestation is final and reaches every verifier through
		// the status list, exactly as when the owner revokes it.
		e.Router.POST("/api/connection/attestations/{id}/revoke", func(re *core.RequestEvent) error {
			conn, _, ok := connectionFromRequest(app, re)
			if !ok {
				return nil
			}
			if !connectionHas(conn, util.ScopeAttestationUpdate) {
				return appErrorResponse(re, http.StatusForbidden, &util.Errors.ConnectionRevokeNotAllowed)
			}
			f := util.Fields.Attestation
			attestation, err := app.FindRecordById(util.Coll.Attestations, re.Request.PathValue("id"))
			if err != nil || attestation == nil || attestation.GetString(f.Connection) != conn.Id {
				return re.NotFoundError("Attestation not found", nil)
			}
			if attestation.GetString(f.Status) != util.StatusRevoked {
				attestation.Set(f.Status, util.StatusRevoked)
				attestation.Set(f.RevokedAt, types.NowDateTime())
				attestation.Set(f.RevokedReason, util.RevocationManual)
				if err := app.Save(attestation); err != nil {
					return re.InternalServerError("Failed to revoke the attestation", err)
				}
				auditConnection(app, re, conn, auditToolRevokedAttestation, map[string]any{"attestation": attestation.Id})
			}
			return re.JSON(http.StatusOK, connectionAttestationView(attestation))
		})

		e.Router.POST("/api/connections/{id}/permissions", func(re *core.RequestEvent) error {
			conn, err := ownedConnection(app, re)
			if err != nil {
				return err
			}
			var body connectionGrant
			if err := re.BindBody(&body); err != nil {
				return re.BadRequestError("Invalid request body", nil)
			}
			// The whole vault is granted only by connecting again, so the
			// owner sees the tool's own request for it.
			if body.AllowVaultRead != nil && *body.AllowVaultRead {
				return appErrorResponse(re, http.StatusBadRequest, &util.Errors.ConnectionVaultReconnect)
			}
			granter := services.GranterScopes(app, re.Auth, conn.GetString(util.Fields.Connection.Workspace), false)
			var refused *util.AppError
			err = app.RunInTransaction(func(tx core.App) error {
				if refused = applyConnectionGrant(tx, conn, body, granter); refused != nil {
					return errConnectionGrant
				}
				if err := tx.Save(conn); err != nil {
					return err
				}
				return ensureOwnSection(tx, conn, body)
			})
			if errors.Is(err, errConnectionGrant) {
				return appErrorResponse(re, http.StatusBadRequest, refused)
			}
			if err != nil {
				return re.InternalServerError("Failed to change the permissions", err)
			}
			auditConnection(app, re, conn, auditToolPermissionChanged, nil)
			return re.JSON(http.StatusOK, connectionGrantView(conn, nil))
		})

		e.Router.POST("/api/connections/{id}/pause", func(re *core.RequestEvent) error {
			conn, err := ownedConnection(app, re)
			if err != nil {
				return err
			}
			if err := services.PauseConnection(app, conn); err != nil {
				return re.InternalServerError("Failed to pause the tool", err)
			}
			auditConnection(app, re, conn, auditToolPaused, nil)
			return re.JSON(http.StatusOK, map[string]any{"paused": true})
		})

		e.Router.POST("/api/connections/{id}/resume", func(re *core.RequestEvent) error {
			conn, err := ownedConnection(app, re)
			if err != nil {
				return err
			}
			if err := services.ResumeConnection(app, conn); err != nil {
				return re.InternalServerError("Failed to activate the tool", err)
			}
			auditConnection(app, re, conn, auditToolResumed, nil)
			return re.JSON(http.StatusOK, map[string]any{"paused": false})
		})

		e.Router.POST("/api/connections/{id}/disconnect", func(re *core.RequestEvent) error {
			conn, err := ownedConnection(app, re)
			if err != nil {
				return err
			}
			var body struct {
				RevokeLinks bool `json:"revokeLinks"`
			}
			if err := re.BindBody(&body); err != nil {
				return re.BadRequestError("Invalid request body", nil)
			}
			if err := services.DisconnectConnection(app, conn, body.RevokeLinks); err != nil {
				return re.InternalServerError("Failed to disconnect", err)
			}
			auditConnection(app, re, conn, auditToolOwnerDisconnected, map[string]any{"revokeLinks": body.RevokeLinks})
			return re.NoContent(http.StatusNoContent)
		})

		e.Router.DELETE("/api/connection", func(re *core.RequestEvent) error {
			conn, _, ok := connectionFromRequest(app, re)
			if !ok {
				return nil
			}
			if err := app.Delete(conn); err != nil {
				return re.InternalServerError("Failed to disconnect", err)
			}
			auditConnection(app, re, conn, auditToolDisconnected, nil)
			return re.NoContent(http.StatusNoContent)
		})

		return e.Next()
	})
}

type grantError struct{}

func (grantError) Error() string { return "invalid grant" }

var errGrant error = grantError{}

// errNotConnected ends a reuse that found no live connection to reuse.
var errNotConnected = errors.New("not connected")

// errConnectionPaused ends an authorize for a tool the owner has paused.
var errConnectionPaused = errors.New("connection paused")

// errConnectionGrant ends a transaction whose grant was refused; the refusal
// itself travels beside it.
var errConnectionGrant = errors.New("connection grant refused")

// ownedConnection finds the connection named in the path for the person asking.
func ownedConnection(app core.App, re *core.RequestEvent) (*core.Record, error) {
	if re.Auth == nil || re.Auth.Collection().Name != util.Coll.Users {
		return nil, re.UnauthorizedError(util.Errors.NotAuthenticated.ErrorCode, nil)
	}
	conn, err := app.FindRecordById(util.Coll.Connections, re.Request.PathValue("id"))
	if err != nil || conn == nil || conn.GetString(util.Fields.Connection.User) != re.Auth.Id {
		return nil, re.NotFoundError("Connection not found", nil)
	}
	return conn, nil
}

// connectionLastUsedResolution keeps "last used" honest without a write per request.
const connectionLastUsedResolution = 10 * time.Minute

// connectionFromRequest resolves the X-Revoked-Connection token to its
// connection, and reports whether this is the first request of a new stretch
// of use. When it cannot, it has already answered 401 and reports !ok.
func connectionFromRequest(app core.App, re *core.RequestEvent) (conn *core.Record, first, ok bool) {
	_, conn, first, ok = connectionTokenFromRequest(app, re)
	return conn, first, ok
}

// connectionTokenFromRequest is connectionFromRequest with the token's own
// row, which says how the token was collected.
func connectionTokenFromRequest(app core.App, re *core.RequestEvent) (row, conn *core.Record, first, ok bool) {
	refuse := func(appErr *util.AppError) (*core.Record, *core.Record, bool, bool) {
		_ = appErrorResponse(re, http.StatusUnauthorized, appErr)
		return nil, nil, false, false
	}
	token := strings.TrimSpace(re.Request.Header.Get(util.ConnectionHeader))
	if token == "" {
		return refuse(&util.Errors.ConnectionUnauthorized)
	}
	row, err := app.FindFirstRecordByFilter(util.Coll.ConnectionTokens,
		"tokenHash = {:hash} && tokenHash != ''", dbx.Params{"hash": util.HashToken(token)})
	if err != nil || row == nil {
		return refuse(&util.Errors.ConnectionUnauthorized)
	}
	conn, err = app.FindRecordById(util.Coll.Connections,
		row.GetString(util.Fields.ConnectionToken.Connection))
	if err != nil || conn == nil {
		return refuse(&util.Errors.ConnectionUnauthorized)
	}
	if util.ConnectionExpired(conn.GetDateTime(util.Fields.Connection.ExpiresAt).Time()) {
		return refuse(&util.Errors.ConnectionExpired)
	}
	// 403, not 401: a tool drops its token on a 401, and this one comes back.
	if conn.GetBool(util.Fields.Connection.Paused) {
		_ = appErrorResponse(re, http.StatusForbidden, &util.Errors.ConnectionPaused)
		return nil, nil, false, false
	}
	now := time.Now()
	touch := func(r *core.Record, field string) bool {
		last := r.GetDateTime(field)
		if !last.IsZero() && now.Sub(last.Time()) <= connectionLastUsedResolution {
			return false
		}
		r.Set(field, types.NowDateTime())
		if err := app.Save(r); err != nil {
			app.Logger().Error("Failed to touch connection lastUsedAt", "error", err)
		}
		return true
	}
	touch(row, util.Fields.ConnectionToken.LastUsedAt)
	first = touch(conn, util.Fields.Connection.LastUsedAt)
	return row, conn, first, true
}

// What a connected tool does, and what its owner does to it, as the audit log
// names it. An app older than the disconnect route still deletes through the
// collection API, which records it as a delete.
const (
	auditToolAuthorized         = "tool_authorized"          // the owner connected or renewed it
	auditToolBrowserAdded       = "tool_browser_added"       // the app let another browser in, the connection as it was
	auditToolConnected          = "tool_connected"           // a browser exchanged its code
	auditToolRead               = "tool_read"                // it read where its links stand
	auditToolRevokedLink        = "tool_revoked_link"        // it revoked one of its links
	auditToolClosedRequest      = "tool_closed_request"      // it closed one of its requests
	auditToolRevokedAttestation = "tool_revoked_attestation" // it revoked one of its attestations
	auditToolListedVault        = "tool_listed_vault"        // it listed the records in the vault
	auditToolReadRecord         = "tool_read_record"         // it read one record's value
	auditToolDisconnected       = "tool_disconnected"        // it disconnected itself
	auditToolCreatedLink        = "tool_created_link"        // it created a share itself
	auditToolCreatedRequest     = "tool_created_request"     // it created a request itself

	auditToolPermissionChanged = "tool_permission_changed" // the owner changed what it may do
	auditToolPaused            = "tool_paused"             // the owner paused it
	auditToolResumed           = "tool_resumed"            // the owner activated it again
	auditToolOwnerDisconnected = "tool_owner_disconnected" // the owner disconnected it
)

// auditConnection records something done to or by a connection. The row names
// the tool by origin, so it still reads after the connection is gone; extra
// adds what the action was about. A failure is logged and never blocks the action it describes.
func auditConnection(app core.App, re *core.RequestEvent, conn *core.Record, action string, extra map[string]any) {
	fields := map[string]any{
		util.Fields.Connection.ClientId:       conn.GetString(util.Fields.Connection.ClientId),
		util.Fields.Connection.ClientName:     conn.GetString(util.Fields.Connection.ClientName),
		util.Fields.Connection.Scopes:         conn.GetStringSlice(util.Fields.Connection.Scopes),
		util.Fields.Connection.VaultAccess:    conn.GetString(util.Fields.Connection.VaultAccess),
		util.Fields.Connection.Section:        conn.GetString(util.Fields.Connection.Section),
		util.Fields.Connection.Sections:       conn.GetStringSlice(util.Fields.Connection.Sections),
		util.Fields.Connection.AllowVaultRead: conn.GetBool(util.Fields.Connection.AllowVaultRead),
		util.Fields.Connection.ExpiresAt:      conn.GetString(util.Fields.Connection.ExpiresAt),
	}
	for k, v := range extra {
		fields[k] = v
	}
	saveAuditRow(app, re, auditRow{
		user:       conn.GetString(util.Fields.Connection.User),
		workspace:  conn.GetString(util.Fields.Connection.Workspace),
		action:     action,
		collection: util.Coll.Connections,
		recordID:   conn.Id,
		fields:     fields,
	})
}

// auditRow is an audit entry for something a route did directly, which the
// audit hook does not see.
type auditRow struct {
	user, workspace, action, collection, recordID string
	fields                                        map[string]any
}

func saveAuditRow(app core.App, re *core.RequestEvent, entry auditRow) {
	coll, err := app.FindCollectionByNameOrId(util.Coll.AuditLogs)
	if err != nil {
		app.Logger().Error("Audit log collection missing", "error", err)
		return
	}
	data, _ := json.Marshal(entry.fields)
	row := core.NewRecord(coll)
	row.Set(util.Fields.AuditLog.User, entry.user)
	row.Set(util.Fields.AuditLog.Workspace, entry.workspace)
	row.Set(util.Fields.AuditLog.Action, entry.action)
	row.Set(util.Fields.AuditLog.Collection, entry.collection)
	row.Set(util.Fields.AuditLog.RecordId, entry.recordID)
	row.Set(util.Fields.AuditLog.NewData, string(data))
	row.Set(util.Fields.AuditLog.Ip, re.Request.RemoteAddr)
	row.Set(util.Fields.AuditLog.UserAgent, re.Request.UserAgent())
	if err := app.Save(row); err != nil {
		app.Logger().Error("Failed to save audit log", "error", err)
	}
}

// connectionLinkView is what a tool may know about a link its proposal became:
// where it stands, never what it holds. The URL only when the owner handed it
// over, still lets the tool receive links, and only while it can be opened.
func connectionLinkView(conn, l *core.Record, domain string) map[string]any {
	status := l.GetString(util.Fields.Link.Status)
	expires := l.GetDateTime(util.Fields.Link.ExpiresAt)
	if status == util.StatusActive && !expires.IsZero() && expires.Time().Before(time.Now()) {
		status = util.StatusExpired
	}
	view := map[string]any{
		"id":         l.Id,
		"ref":        l.GetString(util.Fields.Link.Ref),
		"label":      l.GetString(util.Fields.Link.Label),
		"status":     status,
		"viewCount":  l.GetInt(util.Fields.Link.ViewCount),
		"maxViews":   l.GetInt(util.Fields.Link.MaxViews),
		"expiresAt":  l.GetString(util.Fields.Link.ExpiresAt),
		"created":    l.GetString(util.Fields.Link.Created),
		"handedOver": l.GetBool(util.Fields.Link.HandedOver),
	}
	if l.GetBool(util.Fields.Link.HandedOver) && status == util.StatusActive &&
		connectionHas(conn, util.ConnectionHandOverScope) {
		view["url"] = publicLinkURL(domain, l.GetString(util.Fields.Link.Slug))
	}
	return view
}

// publicLinkURL is the landlord-facing page of a link on this server's
// advertised domain; a local development domain is served over plain http.
func publicLinkURL(domain, slug string) string {
	scheme := "https://"
	host := strings.Split(domain, ":")[0]
	if host == "localhost" || host == "127.0.0.1" {
		scheme = "http://"
	}
	return scheme + domain + "/s/" + slug
}

// connectionRows lists what a connection's proposals became in one
// collection, newest first.
func connectionRows(app core.App, coll, connID string, view func(*core.Record) map[string]any) ([]map[string]any, error) {
	rows, err := app.FindRecordsByFilter(coll, "connection = {:conn}", "-created", 500, 0, dbx.Params{"conn": connID})
	if err != nil {
		return nil, err
	}
	out := make([]map[string]any, 0, len(rows))
	for _, r := range rows {
		out = append(out, view(r))
	}
	return out, nil
}

// connectionRequestView is where a request stands — never its slug, which
// would let the tool answer it, nor the answers.
func connectionRequestView(r *core.Record) map[string]any {
	f := util.Fields.Request
	status := r.GetString(f.Status)
	expires := r.GetDateTime(f.ExpiresAt)
	if status == util.StatusActive && !expires.IsZero() && expires.Time().Before(time.Now()) {
		status = util.StatusExpired
	}
	return map[string]any{
		"id":            r.Id,
		"ref":           r.GetString(f.Ref),
		"label":         r.GetString(f.Label),
		"status":        status,
		"responseCount": r.GetInt(f.ResponseCount),
		"maxResponses":  r.GetInt(f.MaxResponses),
		"expiresAt":     r.GetString(f.ExpiresAt),
		"created":       r.GetString(f.Created),
	}
}

// connectionAttestationView leaves out the claims and the offer token: the
// values are the owner's statement, and the token would let the tool accept
// the offer itself.
func connectionAttestationView(r *core.Record) map[string]any {
	f := util.Fields.Attestation
	return map[string]any{
		"id":                 r.Id,
		"ref":                r.GetString(f.Ref),
		"type":               r.GetString(f.Type),
		"label":              r.GetString(f.Label),
		"status":             r.GetString(f.Status),
		"subjectName":        r.GetString(f.SubjectName),
		"subjectFingerprint": r.GetString(f.SubjectFingerprint),
		"subjectDomain":      r.GetString(f.SubjectDomain),
		"expiresAt":          r.GetString(f.ExpiresAt),
		"issuedAt":           r.GetString(f.IssuedAt),
		"created":            r.GetString(f.Created),
	}
}

// connectionCheckView is a check and, once answered, its verdict with the
// claims the other person chose to show — never the nonce or the
// presentation.
func connectionCheckView(r *core.Record) map[string]any {
	f := util.Fields.AttestationCheck
	status := r.GetString(f.Status)
	if status == util.CheckStatusOpen && !r.GetDateTime(f.ExpiresAt).Time().After(time.Now()) {
		status = util.StatusExpired
	}
	view := map[string]any{
		"id":         r.Id,
		"ref":        r.GetString(f.Ref),
		"type":       r.GetString(f.Type),
		"status":     status,
		"expiresAt":  r.GetString(f.ExpiresAt),
		"answeredAt": r.GetString(f.AnsweredAt),
		"created":    r.GetString(f.Created),
	}
	var verdict services.AttestationVerdict
	if raw := r.GetString(f.Result); raw != "" && json.Unmarshal([]byte(raw), &verdict) == nil {
		view["verdict"] = map[string]any{
			"state":    verdict.State,
			"issuer":   verdict.Issuer,
			"type":     verdict.Type,
			"claims":   verdict.Claims,
			"withheld": verdict.Withheld,
			"status":   verdict.Status,
			"holder":   verdict.Holder,
		}
	}
	return view
}

// vaultReadable reports whether this token reaches the whole vault. A token
// collected by polling never does: anyone can send the owner a connect link and
// read them its check code, but only the owner's own machine receives an
// answer sent back to the tool's address.
func vaultReadable(conn, token *core.Record) bool {
	return services.ConnectionCredential(conn, token).WholeVault
}
