package routes

import (
	"net/http"

	"github.com/pocketbase/pocketbase/core"
)

// HealthzRoute registers the GET /healthz liveness probe on app.
func HealthzRoute(app core.App) {
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {

		e.Router.GET("/healthz", func(e *core.RequestEvent) error {
			return e.String(http.StatusOK, "ok")
		})

		return e.Next()
	})
}
