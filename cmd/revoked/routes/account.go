package routes

import (
	"errors"
	"net/http"

	"revoked/cmd/revoked/services"
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
)

// DeleteAccountRoute closes the caller's own account. A custom route because
// deleting the users row through the collection API would strip the owner from
// their workspaces, records and links without removing any of them.
func DeleteAccountRoute(app core.App) {
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		e.Router.DELETE("/api/account", func(re *core.RequestEvent) error {
			// Users only: an API key must not be able to delete the person behind it.
			if re.Auth == nil || re.Auth.Collection().Name != util.Coll.Users {
				return appErrorResponse(re, http.StatusUnauthorized, &util.Errors.NotAuthenticated)
			}

			if err := services.PurgeAccount(app, re.Auth.Id); err != nil {
				if errors.Is(err, services.ErrAccountLastAdmin) {
					return appErrorResponse(re, http.StatusConflict, &util.Errors.LastAdminProtected)
				}
				return re.InternalServerError("Failed to delete the account", nil)
			}

			return re.NoContent(http.StatusNoContent)
		})
		return e.Next()
	})
}
