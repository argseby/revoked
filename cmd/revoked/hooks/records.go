package hooks

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
)

// BindRecordHooks enforces the alias invariants on record create and update.
func BindRecordHooks(app core.App) {
	app.OnRecordCreate(util.Coll.Records).BindFunc(func(e *core.RecordEvent) error {
		if err := validateAliasRecord(app, e.Record); err != nil {
			return err
		}
		return e.Next()
	})

	app.OnRecordUpdate(util.Coll.Records).BindFunc(func(e *core.RecordEvent) error {
		if err := validateAliasRecord(app, e.Record); err != nil {
			return err
		}
		return e.Next()
	})
}

// validateAliasRecord rejects self, missing, cross-workspace and chained alias
// targets, and clears an alias's own value.
func validateAliasRecord(app core.App, rec *core.Record) error {
	parentId := rec.GetString(util.Fields.Record.AliasOf)
	if parentId == "" {
		return nil
	}
	if parentId == rec.Id {
		return util.AsValidationError(util.Errors.AliasCycle)
	}
	parent, err := app.FindRecordById(util.Coll.Records, parentId)
	if err != nil || parent == nil {
		return util.AsValidationError(util.Errors.AliasParentMissing)
	}
	if parent.GetString(util.Fields.Record.Workspace) != rec.GetString(util.Fields.Record.Workspace) {
		return util.AsValidationError(util.Errors.AliasParentMissing)
	}
	if parent.GetString(util.Fields.Record.AliasOf) != "" {
		return util.AsValidationError(util.Errors.AliasCycle)
	}
	// An alias never stores its own value; reads resolve through the parent.
	rec.Set(util.Fields.Record.Value, "")
	return nil
}
