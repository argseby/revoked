package hooks

import (
	"net/http"

	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/hook"
)

// BindTrustedProxy applies TRUSTED_PROXY_HEADER over PocketBase's stored
// setting, at boot and whenever the settings reload, so rate limits key on the
// client's address rather than the proxy's without a trip to the dashboard. In
// memory only, as with the mail settings: the next boot wins.
func BindTrustedProxy(app core.App) {
	apply := func(app core.App) {
		s := app.Settings()
		s.TrustedProxy.Headers = util.TrustedProxyHeaders()
		// The rightmost entry is the one the proxy appended; the leftmost is
		// whatever the client sent.
		s.TrustedProxy.UseLeftmostIP = false
	}
	app.OnBootstrap().BindFunc(func(e *core.BootstrapEvent) error {
		if err := e.Next(); err != nil {
			return err
		}
		apply(e.App)
		return nil
	})
	app.OnSettingsReload().BindFunc(func(e *core.SettingsReloadEvent) error {
		if err := e.Next(); err != nil {
			return err
		}
		apply(e.App)
		return nil
	})
	// Again as the server starts, for an app bootstrapped before this hook
	// was bound.
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		apply(e.App)
		return e.Next()
	})
}

// BindDashboardAccess keeps the superuser dashboard and the superuser sign-in
// off the public internet: unless DASHBOARD_ACCESS=public, they answer only
// requests that reach the server directly — from the machine itself or over
// an SSH tunnel — and look absent to anything that came through the proxy.
func BindDashboardAccess(app core.App) {
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		e.Router.Bind(&hook.Handler[*core.RequestEvent]{
			Id: "revokedDashboardAccess",
			Func: func(re *core.RequestEvent) error {
				if util.IsSuperuserPath(re.Request.URL.Path) &&
					!util.DashboardIsPublic() &&
					!util.IsDirectRequest(re.Request) {
					return re.Error(http.StatusNotFound, "The requested resource wasn't found.", nil)
				}
				return re.Next()
			},
			// Ahead of PocketBase's own middlewares, so a refused request
			// never reaches the sign-in or its rate limiter.
			Priority: -10000,
		})
		return e.Next()
	})
}
