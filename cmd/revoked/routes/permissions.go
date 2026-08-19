package routes

import (
	"net/http"
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
)

// PermissionsRoute serves the permission catalogue, so clients render the list
// the server enforces instead of a copy that drifts. Unauthenticated: the
// catalogue is API contract, not workspace state.
func PermissionsRoute(app core.App) {
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		e.Router.GET("/api/permissions", func(re *core.RequestEvent) error {
			out := make([]map[string]any, 0, len(util.Permissions))
			for _, p := range util.Permissions {
				out = append(out, map[string]any{
					"key":         p.Key,
					"label":       p.Label,
					"description": p.Description,
					"destructive": p.Destructive,
					// Grants are stored expanded; clients need the mapping to name them back.
					"scopes": p.Scopes,
				})
			}
			return re.JSON(http.StatusOK, map[string]any{"permissions": out})
		})
		return e.Next()
	})
}
