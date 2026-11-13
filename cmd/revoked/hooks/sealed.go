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
			// An encrypted file's blob and its name inside the sealed value
			// change together, through /api/sealed/records only. An upload
			// here would put plaintext where the ciphertext was.
			if len(e.Record.GetUnsavedFiles(f.File)) > 0 ||
				e.Record.GetString(f.File) != original.GetString(f.File) {
				return refuseSealedWrite(e, f.File)
			}
			if e.Record.GetString(f.Filename) != original.GetString(f.Filename) {
				return refuseSealedWrite(e, f.Filename)
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
	if rec.GetString(f.AliasOf) != "" {
		return util.AsFieldValidationError(f.AliasOf, util.Errors.SealedRecordUnsupported)
	}
	return nil
}

// validateSealedFileTransition keeps a file's blob in step with its state: a
// file that becomes encrypted, or stops being encrypted, always gets a new
// blob in the same save. Otherwise a sealed record would keep serving the
// plaintext it had, or an unsealed one the ciphertext.
func validateSealedFileTransition(rec *core.Record) error {
	f := util.Fields.Record
	if rec.GetString(f.Type) != util.TypeFile || rec.IsNew() {
		return nil
	}
	if services.IsSealed(rec) != services.IsSealed(rec.Original()) &&
		len(rec.GetUnsavedFiles(f.File)) == 0 {
		return util.AsFieldValidationError(f.File, util.Errors.SealedInvalid)
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

// refuseNewSealedRecords stops a link from naming a sealed record it holds no
// key for. A link carries one only together with a seal for the record's
// current version, which /api/sealed/links writes in the same transaction
// before it saves the link (design/e2ee-sharing.md §3.3); a save that names
// one without it, as the collection API would, is refused. An alias of a
// sealed record is refused either way. Only additions are checked: sealing a
// record already on a link must not make every later save of that link fail,
// and reads drop it from the link anyway.
func refuseNewSealedRecords(app core.App, link *core.Record) error {
	f := util.Fields.Link
	before := link.Original().GetStringSlice(f.Records)
	for _, id := range link.GetStringSlice(f.Records) {
		if slices.Contains(before, id) {
			continue
		}
		rec, err := app.FindRecordById(util.Coll.Records, id)
		if err != nil || !services.IsSealedThroughAlias(app, rec) {
			continue
		}
		if link.IsNew() || services.CurrentLinkSeal(app, link.Id, rec) == nil {
			return util.AsFieldValidationError(f.Records, util.Errors.SealedRecordUnsupported)
		}
	}
	return nil
}

// refuseStampedSealedFiles keeps encrypted files off links that stamp their
// files: the server cannot read one to stamp it, and a stamped share must
// never hand out an unstamped copy. Checked on every save, so turning the
// stamp on for a link that already carries one is refused too.
func refuseStampedSealedFiles(app core.App, link *core.Record) error {
	f := util.Fields.Link
	if !link.GetBool(f.Watermark) {
		return nil
	}
	for _, id := range link.GetStringSlice(f.Records) {
		if services.IsSealedFile(app, id) {
			return util.AsFieldValidationError(f.Watermark, util.Errors.SealedFileWatermark)
		}
	}
	return nil
}
