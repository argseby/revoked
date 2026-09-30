package services

import (
	"encoding/base64"
	"errors"
	"net/url"
	"strings"
	"time"

	"revoked/util"

	"github.com/go-webauthn/webauthn/webauthn"
	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/security"
	"github.com/pocketbase/pocketbase/tools/types"
)

// ErrPasskeyTicketInvalid reports a ticket that is unknown, used or expired.
var ErrPasskeyTicketInvalid = errors.New("passkey ticket invalid")

// PasskeyUser is an account as a WebAuthn ceremony sees it: its record id as
// the user handle, its email as the name an authenticator shows, and the
// passkeys it already has.
type PasskeyUser struct {
	ID          string
	Email       string
	Credentials []webauthn.Credential
}

func (u *PasskeyUser) WebAuthnID() []byte                         { return []byte(u.ID) }
func (u *PasskeyUser) WebAuthnName() string                       { return u.Email }
func (u *PasskeyUser) WebAuthnDisplayName() string                { return u.Email }
func (u *PasskeyUser) WebAuthnCredentials() []webauthn.Credential { return u.Credentials }

// PasskeyCredentialID is how a credential id is stored and looked up.
func PasskeyCredentialID(raw []byte) string {
	return base64.RawURLEncoding.EncodeToString(raw)
}

// LoadPasskeyUser reads an account and its passkeys for a ceremony.
func LoadPasskeyUser(app core.App, user *core.Record) (*PasskeyUser, error) {
	rows, err := app.FindAllRecords(util.Coll.Passkeys,
		dbx.HashExp{util.Fields.Passkey.User: user.Id})
	if err != nil {
		return nil, err
	}
	out := &PasskeyUser{ID: user.Id, Email: user.Email()}
	for _, row := range rows {
		var cred webauthn.Credential
		if err := row.UnmarshalJSONField(util.Fields.Passkey.Credential, &cred); err != nil {
			// One unreadable row must not lock the account out of the rest.
			app.Logger().Error("Unreadable passkey", "passkey", row.Id, "error", err)
			continue
		}
		out.Credentials = append(out.Credentials, cred)
	}
	return out, nil
}

// SavePasskey stores a credential an account just registered.
func SavePasskey(app core.App, userID, name string, cred *webauthn.Credential) (*core.Record, error) {
	coll, err := app.FindCollectionByNameOrId(util.Coll.Passkeys)
	if err != nil {
		return nil, err
	}
	row := core.NewRecord(coll)
	row.Set(util.Fields.Passkey.User, userID)
	row.Set(util.Fields.Passkey.CredentialId, PasskeyCredentialID(cred.ID))
	row.Set(util.Fields.Passkey.Credential, cred)
	row.Set(util.Fields.Passkey.Name, name)
	if err := app.Save(row); err != nil {
		return nil, err
	}
	return row, nil
}

// TouchPasskey records a sign-in: the authenticator's new counter and flags,
// and when it was last used.
func TouchPasskey(app core.App, cred *webauthn.Credential) error {
	row, err := app.FindFirstRecordByData(util.Coll.Passkeys,
		util.Fields.Passkey.CredentialId, PasskeyCredentialID(cred.ID))
	if err != nil {
		return err
	}
	row.Set(util.Fields.Passkey.Credential, cred)
	row.Set(util.Fields.Passkey.LastUsedAt, types.NowDateTime())
	return app.Save(row)
}

// IssuePasskeyTicket makes a one-time ticket that lets userID register a
// passkey, and returns it. Only its hash is kept. Tickets that have lapsed are
// swept on the way.
func IssuePasskeyTicket(app core.App, userID string, ttl time.Duration) (string, time.Time, error) {
	coll, err := app.FindCollectionByNameOrId(util.Coll.PasskeyTickets)
	if err != nil {
		return "", time.Time{}, err
	}
	if stale, err := app.FindRecordsByFilter(util.Coll.PasskeyTickets,
		"expiresAt < {:now}", "", 200, 0, dbx.Params{"now": types.NowDateTime().String()}); err == nil {
		for _, row := range stale {
			_ = app.Delete(row)
		}
	}
	ticket := security.RandomString(48)
	expires := time.Now().Add(ttl)
	row := core.NewRecord(coll)
	row.Set(util.Fields.PasskeyTicket.User, userID)
	row.Set(util.Fields.PasskeyTicket.TokenHash, util.HashToken(ticket))
	row.Set(util.Fields.PasskeyTicket.ExpiresAt, expires)
	if err := app.Save(row); err != nil {
		return "", time.Time{}, err
	}
	return ticket, expires, nil
}

// FindPasskeyTicket resolves a ticket to its row and the account it is for,
// without spending it: a ceremony that fails can be tried again.
func FindPasskeyTicket(app core.App, ticket string) (row, user *core.Record, err error) {
	if strings.TrimSpace(ticket) == "" {
		return nil, nil, ErrPasskeyTicketInvalid
	}
	row, err = app.FindFirstRecordByData(util.Coll.PasskeyTickets,
		util.Fields.PasskeyTicket.TokenHash, util.HashToken(ticket))
	if err != nil || row == nil {
		return nil, nil, ErrPasskeyTicketInvalid
	}
	expires := row.GetDateTime(util.Fields.PasskeyTicket.ExpiresAt)
	if expires.IsZero() || !expires.Time().After(time.Now()) {
		return nil, nil, ErrPasskeyTicketInvalid
	}
	user, err = app.FindRecordById(util.Coll.Users, row.GetString(util.Fields.PasskeyTicket.User))
	if err != nil || user == nil {
		return nil, nil, ErrPasskeyTicketInvalid
	}
	return row, user, nil
}

// PasskeyTicketURL is the page a ticket is redeemed on, on the server reached
// at authority (host[:port]); a local development address is plain http.
func PasskeyTicketURL(authority, ticket string) string {
	scheme := "https://"
	host := strings.Split(authority, ":")[0]
	if host == "localhost" || host == "127.0.0.1" {
		scheme = "http://"
	}
	return scheme + authority + util.PasskeyPagePath + "?mode=enroll&ticket=" + url.QueryEscape(ticket)
}

// EnsurePasskeyAccount finds the account for email, or creates it. A new
// account has no way in until a ticket is redeemed: its password is random,
// thrown away, and password sign-in is off.
func EnsurePasskeyAccount(app core.App, email string) (user *core.Record, created bool, err error) {
	users, err := app.FindCollectionByNameOrId(util.Coll.Users)
	if err != nil {
		return nil, false, err
	}
	if user, err = app.FindAuthRecordByEmail(users, email); err == nil && user != nil {
		return user, false, nil
	}
	user = core.NewRecord(users)
	user.SetEmail(email)
	user.SetVerified(true)
	user.SetRandomPassword()
	if err := app.Save(user); err != nil {
		return nil, false, err
	}
	return user, true, nil
}
