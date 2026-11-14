package routes

import (
	"net/http"
	"strings"

	"revoked/cmd/revoked/services"
	"revoked/util"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
)

// MeRoute exposes GET /api/me: who the credential acts as. A key or a tool
// names its workspace when it creates records, and has no other way to learn
// it. It answers only with what the credential itself carries or the caller
// can already read, never the token.
func MeRoute(app core.App) {
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		e.Router.GET("/api/me", func(re *core.RequestEvent) error {
			if strings.TrimSpace(re.Request.Header.Get(util.ConnectionHeader)) != "" {
				_, conn, _, ok := connectionTokenFromRequest(app, re)
				if !ok {
					return nil
				}
				f := util.Fields.Connection
				return re.JSON(http.StatusOK, map[string]any{
					"kind":      services.CredentialConnection,
					"id":        conn.Id,
					"workspace": conn.GetString(f.Workspace),
					"clientId":  conn.GetString(f.ClientId),
					"expiresAt": dateOrEmpty(conn.GetDateTime(f.ExpiresAt)),
				})
			}
			if re.Auth == nil {
				return appErrorResponse(re, http.StatusUnauthorized, &util.Errors.NotAuthenticated)
			}
			switch re.Auth.Collection().Name {
			case util.Coll.ApiKeys:
				key := services.ApiKeyCredential(re.Auth)
				return re.JSON(http.StatusOK, map[string]any{
					"kind":        services.CredentialApiKey,
					"id":          key.Id,
					"user":        key.User,
					"workspace":   key.Workspace,
					"scopes":      nonNil(key.Scopes),
					"vaultAccess": key.VaultAccess,
					"sections":    nonNil(key.Sections),
					"expiresAt":   dateOrEmpty(re.Auth.GetDateTime(util.Fields.ApiKey.ExpiresAt)),
				})
			case util.Coll.Users:
				workspace := re.Auth.GetString(util.Fields.User.ActiveWorkspace)
				return re.JSON(http.StatusOK, map[string]any{
					"kind":      "user",
					"user":      re.Auth.Id,
					"workspace": workspace,
					"role":      memberRole(app, workspace, re.Auth.Id),
				})
			}
			return appErrorResponse(re, http.StatusForbidden, &util.Errors.NotAuthorized)
		})
		return e.Next()
	})
}

// memberRole is the user's role in the workspace, or "" when they are not a
// member of it.
func memberRole(app core.App, workspace, user string) string {
	if workspace == "" {
		return ""
	}
	f := util.Fields.WorkspaceMember
	member, err := app.FindFirstRecordByFilter(util.Coll.WorkspaceMembers,
		f.Workspace+" = {:w} && "+f.User+" = {:u}", dbx.Params{"w": workspace, "u": user})
	if err != nil {
		return ""
	}
	return member.GetString(f.Role)
}

func nonNil(s []string) []string {
	if s == nil {
		return []string{}
	}
	return s
}
