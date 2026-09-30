package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
	"github.com/pocketbase/pocketbase/tools/types"
)

// Replaces passwords with passkeys.
//
// passkeys holds one row per authenticator a person registered: the WebAuthn
// credential (public key, counter, flags — nothing secret, but nothing a
// client needs either, so it is hidden), and a name and last use so the owner
// can tell their passkeys apart. Rows are written only by the passkey routes;
// the owner lists them, and removes one through a route that refuses to take
// the last.
//
// passkeyTickets holds the hash of a one-time link that lets its account
// register a passkey without being signed in with another: issued by the
// operator for a new or locked-out account, or by a signed-in person for
// another device. Server code only.
//
// Password sign-in is switched off for users. Accounts that existed before
// keep their rows and need a ticket from the operator to get their first
// passkey.
func init() {
	migrations.Register(func(app core.App) error {
		users, err := app.FindCollectionByNameOrId(util.Coll.Users)
		if err != nil {
			return err
		}

		passkeys := core.NewBaseCollection(util.Coll.Passkeys)
		passkeys.Fields.Add(
			&core.RelationField{
				Name:          util.Fields.Passkey.User,
				CollectionId:  users.Id,
				Required:      true,
				MaxSelect:     1,
				CascadeDelete: true,
			},
			// The credential id, base64url: what a sign-in is looked up by.
			&core.TextField{Name: util.Fields.Passkey.CredentialId, Required: true, Max: 1400},
			&core.JSONField{Name: util.Fields.Passkey.Credential, Required: true, Hidden: true, MaxSize: 64 << 10},
			&core.TextField{Name: util.Fields.Passkey.Name, Max: 60},
			&core.DateField{Name: util.Fields.Passkey.LastUsedAt},
			&core.AutodateField{Name: util.Fields.Passkey.Created, OnCreate: true},
		)
		passkeys.AddIndex("idxPasskeysCredential", true, util.Fields.Passkey.CredentialId, "")
		passkeys.AddIndex("idxPasskeysUser", false, util.Fields.Passkey.User, "")
		passkeys.ListRule = types.Pointer(util.UserSelfOnly())
		passkeys.ViewRule = types.Pointer(util.UserSelfOnly())
		if err := app.Save(passkeys); err != nil {
			return err
		}

		tickets := core.NewBaseCollection(util.Coll.PasskeyTickets)
		tickets.Fields.Add(
			&core.RelationField{
				Name:          util.Fields.PasskeyTicket.User,
				CollectionId:  users.Id,
				Required:      true,
				MaxSelect:     1,
				CascadeDelete: true,
			},
			&core.TextField{Name: util.Fields.PasskeyTicket.TokenHash, Required: true, Max: 64, Hidden: true},
			&core.DateField{Name: util.Fields.PasskeyTicket.ExpiresAt, Required: true},
			&core.AutodateField{Name: util.Fields.PasskeyTicket.Created, OnCreate: true},
		)
		tickets.AddIndex("idxPasskeyTicketsToken", true, util.Fields.PasskeyTicket.TokenHash, "")
		if err := app.Save(tickets); err != nil {
			return err
		}

		users.PasswordAuth.Enabled = false
		return app.Save(users)
	}, func(app core.App) error {
		if users, err := app.FindCollectionByNameOrId(util.Coll.Users); err == nil {
			users.PasswordAuth.Enabled = true
			if err := app.Save(users); err != nil {
				return err
			}
		}
		for _, name := range []string{util.Coll.PasskeyTickets, util.Coll.Passkeys} {
			if c, err := app.FindCollectionByNameOrId(name); err == nil {
				if err := app.Delete(c); err != nil {
					return err
				}
			}
		}
		return nil
	})
}
