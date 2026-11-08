package services

import (
	"errors"
	"time"

	"revoked/util"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
)

// ErrTwoFactorAccountMissing is returned by ResetTwoFactor for an address no
// account has.
var ErrTwoFactorAccountMissing = errors.New("no account has this address")

// TwoFactorEnabled reports whether account signs in with a code from an
// authenticator app after its passkey.
func TwoFactorEnabled(account *core.Record) bool {
	return account != nil && account.GetString(util.Fields.User.TotpSecret) != ""
}

// UseTotpCode reports whether code is a current code for secret that this
// account has not used yet, and marks its time step used. The mark is one
// conditional UPDATE, so two requests racing with the same code cannot both
// pass. It does not save account; the column is written directly.
func UseTotpCode(app core.App, account *core.Record, secret, code string, now time.Time) bool {
	step, ok := util.MatchTotp(secret, code, now)
	if !ok {
		return false
	}
	f := util.Fields.User
	res, err := app.DB().NewQuery(
		"UPDATE {{" + util.Coll.Users + "}} SET [[" + f.TotpLastStep + "]] = {:step}" +
			" WHERE [[id]] = {:id} AND COALESCE([[" + f.TotpLastStep + "]], 0) < {:step}",
	).Bind(dbx.Params{"step": step, "id": account.Id}).Execute()
	if err != nil {
		return false
	}
	if n, err := res.RowsAffected(); err != nil || n != 1 {
		return false
	}
	account.Set(f.TotpLastStep, step)
	return true
}

// TwoFactorReset is what ResetTwoFactor did.
type TwoFactorReset struct {
	UserID string
	// Enabled and Pending say what the account had before the reset: a
	// confirmed authenticator, and one being set up.
	Enabled, Pending bool
}

// ResetTwoFactor is the operator's way back in for someone who lost their
// authenticator app: it clears the account's secrets, ends every session it
// has (the token key changes), and writes an audit row. The passkey stays the
// way in; with REQUIRE_2FA on, the app then asks for a new authenticator.
func ResetTwoFactor(app core.App, email, actor string) (*TwoFactorReset, error) {
	users, err := app.FindCollectionByNameOrId(util.Coll.Users)
	if err != nil {
		return nil, err
	}
	account, err := app.FindAuthRecordByEmail(users, email)
	if err != nil || account == nil {
		return nil, ErrTwoFactorAccountMissing
	}
	f := util.Fields.User
	out := &TwoFactorReset{
		UserID:  account.Id,
		Enabled: account.GetString(f.TotpSecret) != "",
		Pending: account.GetString(f.TotpPending) != "",
	}
	account.Set(f.TotpSecret, "")
	account.Set(f.TotpPending, "")
	account.Set(f.TotpEnabledAt, "")
	account.Set(f.TotpLastStep, 0)
	account.RefreshTokenKey()
	if err := app.Save(account); err != nil {
		return nil, err
	}
	RecordAudit(app, AuditEntry{
		Action:     util.AuditActionUpdate,
		Collection: util.Coll.Users,
		RecordId:   account.Id,
		User:       account.Id,
		UserAgent:  actor,
		OldData:    map[string]any{"twoFactor": twoFactorState(out.Enabled)},
		NewData:    map[string]any{"twoFactor": "reset", "sessions": "ended"},
	})
	return out, nil
}

func twoFactorState(enabled bool) string {
	if enabled {
		return "enabled"
	}
	return "disabled"
}

// AuditTwoFactor records the account itself turning its authenticator on or
// off.
func AuditTwoFactor(app core.App, account *core.Record, enabled bool, ip, userAgent string) {
	RecordAudit(app, AuditEntry{
		Action:     util.AuditActionUpdate,
		Collection: util.Coll.Users,
		RecordId:   account.Id,
		User:       account.Id,
		Ip:         ip,
		UserAgent:  userAgent,
		OldData:    map[string]any{"twoFactor": twoFactorState(!enabled)},
		NewData:    map[string]any{"twoFactor": twoFactorState(enabled)},
	})
}
