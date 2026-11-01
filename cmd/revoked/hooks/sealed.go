package hooks

import (
	"slices"

	"revoked/cmd/revoked/services"
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
)

// sealedOnlyFields may only change through /api/sealed/*. A plain value is
// refused separately below, because an app from before sealing would otherwise
// write plaintext straight back into a record its owner encrypted.
var sealedOnlyFields = []string{
	util.Fields.Record.Sealed,
	util.Fields.Record.SealedValue,
	util.Fields.Record.SealedVersion,
	util.Fields.Record.KeyEpoch,
	util.Fields.Record.KeyWrap,
}

// BindSealedHooks keeps the collection API away from what makes a record
// sealed: the sealed routes write those fields with an app.Save that does not
// pass through these request hooks.
func BindSealedHooks(app core.App) {
	app.OnRecordCreateRequest(util.Coll.Records).BindFunc(func(e *core.RecordRequestEvent) error {
		for _, field := range sealedOnlyFields {
			switch e.Record.GetString(field) {
			case "", "0", "false":
			default:
				return refuseSealedWrite(e, field)
			}
		}
		return e.Next()
	})

	app.OnRecordUpdateRequest(util.Coll.Records).BindFunc(func(e *core.RecordRequestEvent) error {
		original := e.Record.Original()
		for _, field := range sealedOnlyFields {
			if e.Record.GetString(field) != original.GetString(field) {
				return refuseSealedWrite(e, field)
			}
		}
		if services.IsSealed(original) {
			f := util.Fields.Record
			if e.Record.GetString(f.Value) != "" {
				return refuseSealedWrite(e, f.Value)
			}
			// The ciphertext is bound to the key, so a rename would make it
			// unreadable.
			if e.Record.GetString(f.Key) != original.GetString(f.Key) {
				return refuseSealedWrite(e, f.Key)
			}
		}
		return e.Next()
	})
}

func refuseSealedWrite(e *core.RecordRequestEvent, field string) error {
	return e.BadRequestError("Failed to save.",
		util.AsFieldValidationError(field, util.Errors.SealedFieldsRestricted))
}

// validateSealedRecord holds what a sealed record is, however it was written.
// An empty value is what makes every path nobody taught about sealing fail
// closed, so nothing may ever put one there.
func validateSealedRecord(rec *core.Record) error {
	if !services.IsSealed(rec) {
		return nil
	}
	f := util.Fields.Record
	if rec.GetString(f.Value) != "" {
		return util.AsFieldValidationError(f.Value, util.Errors.SealedFieldsRestricted)
	}
	if rec.GetString(f.SealedValue) == "" || rec.GetString(f.KeyWrap) == "" {
		return util.AsFieldValidationError(f.SealedValue, util.Errors.SealedInvalid)
	}
	if rec.GetString(f.Type) == util.TypeFile {
		return util.AsFieldValidationError(f.Type, util.Errors.SealedRecordUnsupported)
	}
	if rec.GetString(f.AliasOf) != "" {
		return util.AsFieldValidationError(f.AliasOf, util.Errors.SealedRecordUnsupported)
	}
	return nil
}

// refuseStaleRecordWrite stops a write that loaded a record before it was sealed
// from saving it after. PocketBase writes back every column, so a label edit
// racing a seal would otherwise restore the plain value. The sealed routes
// re-read inside their transaction, so they always pass.
func refuseStaleRecordWrite(app core.App, rec *core.Record) error {
	if rec.IsNew() {
		return nil
	}
	f := util.Fields.Record
	fresh, err := app.FindRecordById(util.Coll.Records, rec.Id)
	if err != nil {
		return nil
	}
	if fresh.GetInt(f.SealedVersion) != rec.Original().GetInt(f.SealedVersion) {
		return util.AsFieldValidationError(f.SealedVersion, util.Errors.SealedVersionConflict)
	}
	return nil
}

// refuseNewSealedRecords stops a plain link from naming a sealed record. Only
// additions are checked: sealing a record already on a link must not make every
// later save of that link fail, and reads drop it from the link anyway.
func refuseNewSealedRecords(app core.App, link *core.Record) error {
	f := util.Fields.Link
	before := link.Original().GetStringSlice(f.Records)
	for _, id := range link.GetStringSlice(f.Records) {
		if slices.Contains(before, id) {
			continue
		}
		rec, err := app.FindRecordById(util.Coll.Records, id)
		if err == nil && services.IsSealedThroughAlias(app, rec) {
			return util.AsFieldValidationError(f.Records, util.Errors.SealedRecordUnsupported)
		}
	}
	return nil
}
