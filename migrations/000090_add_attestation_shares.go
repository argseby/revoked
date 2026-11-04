package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
	"github.com/pocketbase/pocketbase/tools/types"
)

// Adds attestationShares: a link a holder made to show one attestation to
// whoever opens it.
//
// A row starts pending with a nonce the holder's presentation must commit to,
// and turns active once that presentation arrives and verifies. The link
// itself is a token only its hash is kept of. The presentation is kept, since
// it is what the link shows; it never leaves through the collection API.
//
// Written by the share routes alone. Its owner may list and read their rows
// (without the presentation, the nonce or the hash) and ends one through the
// revoke route. Removing the attestation removes its links with it.
func init() {
	migrations.Register(func(app core.App) error {
		users, err := app.FindCollectionByNameOrId(util.Coll.Users)
		if err != nil {
			return err
		}
		credentials, err := app.FindCollectionByNameOrId(util.Coll.Credentials)
		if err != nil {
			return err
		}

		f := util.Fields.AttestationShare
		shares := core.NewBaseCollection(util.Coll.AttestationShares)
		shares.Fields.Add(
			&core.RelationField{Name: f.User, CollectionId: users.Id, Required: true, MaxSelect: 1, CascadeDelete: true},
			&core.RelationField{Name: f.Credential, CollectionId: credentials.Id, Required: true, MaxSelect: 1, CascadeDelete: true},
			&core.SelectField{
				Name:      f.Status,
				Required:  true,
				Values:    util.AttestationShareStatuses,
				MaxSelect: 1,
			},
			&core.TextField{Name: f.Nonce, Required: true, Max: 128, Hidden: true},
			&core.TextField{Name: f.Audience, Required: true, Max: 255},
			&core.TextField{Name: f.TokenHash, Max: 128, Hidden: true},
			&core.TextField{Name: f.Presentation, Max: util.MaxCredentialLength, Hidden: true},
			// The names of the details the link shows, for the holder's list.
			&core.JSONField{Name: f.Disclosed, MaxSize: 8 << 10},
			&core.DateField{Name: f.ExpiresAt, Required: true},
			&core.NumberField{Name: f.ViewCount, OnlyInt: true},
			&core.DateField{Name: f.LastViewedAt},
			&core.AutodateField{Name: f.Created, OnCreate: true},
			&core.AutodateField{Name: f.Updated, OnCreate: true, OnUpdate: true},
		)
		shares.AddIndex("idxAttestationSharesUser", false, f.User+", "+f.Created, "")
		shares.AddIndex("idxAttestationSharesCredential", false, f.Credential, "")
		shares.AddIndex("idxAttestationSharesNonce", true, f.Nonce, "")
		shares.AddIndex("idxAttestationSharesToken", true, f.TokenHash, f.TokenHash+" != ''")
		owner := util.AccessSpec{Kind: util.AccessUserSelf}
		shares.ListRule = types.Pointer(owner.Rule())
		shares.ViewRule = types.Pointer(owner.Rule())
		return app.Save(shares)
	}, func(app core.App) error {
		shares, err := app.FindCollectionByNameOrId(util.Coll.AttestationShares)
		if err != nil {
			return nil
		}
		return app.Delete(shares)
	})
}
