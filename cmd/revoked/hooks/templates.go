package hooks

import (
	"revoked/cmd/revoked/services"
	"revoked/util"

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

// BindTemplateHooks refuses a schema the request page could not read back.
// Without it the template saves, and every request built on it reaches the
// responder with nothing to fill in.
func BindTemplateHooks(app core.App) {
	check := func(e *core.RecordRequestEvent) error {
		if err := services.ValidateTemplateSchemaShape(e.Record.GetString(util.Fields.Template.Schema)); err != nil {
			return util.AsFieldValidationError(util.Fields.Template.Schema, util.Errors.TemplateSchemaInvalid)
		}
		return e.Next()
	}
	app.OnRecordCreateRequest(util.Coll.Templates).BindFunc(check)
	app.OnRecordUpdateRequest(util.Coll.Templates).BindFunc(check)
}
