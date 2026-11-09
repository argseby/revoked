package hooks

import (
	"strings"

	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
)

// serverSetContactFields are the fields that say whether a contact has been
// proven, and which account it reaches. A client that could set the first
// group would be able to present an address it typed in as a verified peer,
// which is the whole phishing primitive: a co-member then sends the vault to a
// key the attacker holds. `user` is held for the same reason in a plainer
// form — this server publishes no user directory, so a client naming an
// account id is naming one it had no way to discover, and a delivery would go
// to a stranger it picked. The address is what a person writes down; resolving
// it to an account is the server's job.
var serverSetContactFields = []string{
	util.Fields.Contact.TrustState,
	util.Fields.Contact.VerifiedAt,
	util.Fields.Contact.PeerFingerprint,
	util.Fields.Contact.LastUsedAt,
	util.Fields.Contact.User,
	util.Fields.Contact.CreatedBy,
}

// BindContactHooks holds the fields that say a contact is proven, and refuses
// a contact with no way to reach anyone.
func BindContactHooks(app core.App) {
	app.OnRecordCreateRequest(util.Coll.Contacts).BindFunc(func(e *core.RecordRequestEvent) error {
		if err := util.RestrictFields(e, serverSetContactFields...); err != nil {
			return err
		}
		// Who added it owns it (VISIBILITY.md): a person, or the person a
		// key belongs to.
		if e.Auth != nil {
			switch e.Auth.Collection().Name {
			case util.Coll.Users:
				e.Record.Set(util.Fields.Contact.CreatedBy, e.Auth.Id)
			case util.Coll.ApiKeys:
				e.Record.Set(util.Fields.Contact.CreatedBy, e.Auth.GetString(util.Fields.ApiKey.User))
			}
		}
		return e.Next()
	})
	app.OnRecordUpdateRequest(util.Coll.Contacts).BindFunc(func(e *core.RecordRequestEvent) error {
		if err := util.RestrictFields(e, serverSetContactFields...); err != nil {
			return err
		}
		return e.Next()
	})

	app.OnRecordCreate(util.Coll.Contacts).BindFunc(func(e *core.RecordEvent) error {
		// Unverified is the only state a new contact can honestly be in:
		// nothing has been checked yet.
		e.Record.Set(util.Fields.Contact.TrustState, util.ContactUnverified)
		if err := validateContactRoute(e.Record); err != nil {
			return err
		}
		return e.Next()
	})
	app.OnRecordUpdate(util.Coll.Contacts).BindFunc(func(e *core.RecordEvent) error {
		if err := validateContactRoute(e.Record); err != nil {
			return err
		}
		return e.Next()
	})
}

// BindContactBlockHooks keeps a block to its owner and to something it can
// actually refuse.
//
// The address and domain are lowercased here rather than at the check: a block
// written as "Spam@Example.com" that silently never matches is worse than none
// at all, because the person believes they are rid of the sender.
func BindContactBlockHooks(app core.App) {
	settle := func(e *core.RecordEvent) error {
		f := util.Fields.ContactBlock
		e.Record.Set(f.Email, strings.ToLower(strings.TrimSpace(e.Record.GetString(f.Email))))
		e.Record.Set(f.Domain, strings.ToLower(strings.TrimSpace(e.Record.GetString(f.Domain))))
		if e.Record.GetString(f.BlockedUser) == "" &&
			e.Record.GetString(f.Email) == "" &&
			e.Record.GetString(f.Domain) == "" {
			return util.AsFieldValidationError(f.Email, util.Errors.ContactBlockTargetMissing)
		}
		return e.Next()
	}
	app.OnRecordCreate(util.Coll.ContactBlocks).BindFunc(settle)
	app.OnRecordUpdate(util.Coll.ContactBlocks).BindFunc(settle)
}

// validateContactRoute refuses a contact that names nobody reachable.
func validateContactRoute(contact *core.Record) error {
	if contact.GetString(util.Fields.Contact.User) != "" ||
		contact.GetString(util.Fields.Contact.Email) != "" ||
		contact.GetString(util.Fields.Contact.PeerDomain) != "" {
		return nil
	}
	return util.AsFieldValidationError(util.Fields.Contact.Email, util.Errors.ContactRouteMissing)
}
