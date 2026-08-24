package hooks

import (
	"revoked/cmd/revoked/services"

	"github.com/pocketbase/pocketbase/core"
)

// BindBuiltinTemplateSync reconciles the built-in template catalogue on serve.
// A sync failure is logged, never fatal: a bad drop-in file must not take the
// server down with it.
func BindBuiltinTemplateSync(app core.App) {
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		if err := services.SyncBuiltinTemplates(app, services.BuiltinTemplatesDir(app)); err != nil {
			app.Logger().Error("Built-in template sync failed", "error", err)
		}
		return e.Next()
	})
}
