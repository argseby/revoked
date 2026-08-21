package hooks

import (
	"revoked/util"

	validation "github.com/go-ozzo/ozzo-validation/v4"
	"github.com/pocketbase/pocketbase/core"
	"golang.org/x/crypto/bcrypt"
)

// BindRequestHooks bcrypt-hashes a request's plaintext password before save,
// validates its callback URL, and strips the hash from API responses.
func BindRequestHooks(app core.App) {
	app.OnRecordCreate(util.Coll.Requests).BindFunc(func(e *core.RecordEvent) error {
		resolvePasswordWrite(e.Record, util.Fields.Request.Password)
		if err := validateCallbackURLInPlace(e.Record); err != nil {
			return err
		}
		if e.Record.GetString(util.Fields.Request.Status) == "" {
			e.Record.Set(util.Fields.Request.Status, util.StatusActive)
		}
		return e.Next()
	})

	app.OnRecordUpdate(util.Coll.Requests).BindFunc(func(e *core.RecordEvent) error {
		resolvePasswordWrite(e.Record, util.Fields.Request.Password)
		if err := validateCallbackURLInPlace(e.Record); err != nil {
			return err
		}
		return e.Next()
	})

	app.OnRecordEnrich(util.Coll.Requests).BindFunc(func(e *core.RecordEnrichEvent) error {
		if e.Record != nil {
			// Masked rather than blanked: a blank field is indistinguishable
			// from "remove this gate", so echoing a read back used to strip the
			// password off a protected request.
			maskStoredPassword(e.Record, util.Fields.Request.Password)
		}
		return e.Next()
	})
}

// validateCallbackURLInPlace rejects a callback target the server would refuse
// to fetch anyway (see util.NewSafeCallbackClient), so the owner learns at save
// time rather than from a delivery failure.
func validateCallbackURLInPlace(rec *core.Record) error {
	cb := rec.GetString(util.Fields.Request.CallbackUrl)
	if cb == "" {
		return nil
	}
	if err := util.ValidateCallbackURL(cb); err != nil {
		return validation.Errors{
			util.Fields.Request.CallbackUrl: validation.NewError(
				"validation_callback_url_blocked", err.Error(),
			),
		}
	}
	return nil
}

// isBcryptHash reports whether s is already a valid bcrypt hash.
func isBcryptHash(s string) bool {
	_, err := bcrypt.Cost([]byte(s))
	return err == nil
}
