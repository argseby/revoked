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
		hashRequestPasswordInPlace(e.Record)
		if err := validateCallbackURLInPlace(e.Record); err != nil {
			return err
		}
		if e.Record.GetString(util.Fields.Request.Status) == "" {
			e.Record.Set(util.Fields.Request.Status, util.StatusActive)
		}
		return e.Next()
	})

	app.OnRecordUpdate(util.Coll.Requests).BindFunc(func(e *core.RecordEvent) error {
		hashRequestPasswordInPlace(e.Record)
		if err := validateCallbackURLInPlace(e.Record); err != nil {
			return err
		}
		return e.Next()
	})

	app.OnRecordEnrich(util.Coll.Requests).BindFunc(func(e *core.RecordEnrichEvent) error {
		if e.Record != nil {
			e.Record.Set(util.Fields.Request.Password, "")
		}
		return e.Next()
	})
}

// hashRequestPasswordInPlace bcrypt-hashes a request's plaintext password,
// skipping empty or already-hashed values.
func hashRequestPasswordInPlace(rec *core.Record) {
	pw := rec.GetString(util.Fields.Request.Password)
	if pw == "" || isBcryptHash(pw) {
		return
	}
	hash, err := util.HashPassword(pw)
	if err != nil {
		return
	}
	rec.Set(util.Fields.Request.Password, hash)
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
