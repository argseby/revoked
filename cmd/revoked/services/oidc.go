package services

import (
	"errors"
	"slices"

	"revoked/util"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
)

// SignInGrant is the grant a service receives when its user agrees to share
// vault entries at sign-in: the link's id, the token to read it with, and the
// keys it answers.
type SignInGrant struct {
	ID    string   `json:"id"`
	Token string   `json:"token"`
	Keys  []string `json:"keys"`
}

// PrimaryIdentity returns a person's active primary identity, if they have one.
func PrimaryIdentity(app core.App, userID string) *core.Record {
	f := util.Fields.Identity
	rec, err := app.FindFirstRecordByFilter(util.Coll.Identities,
		f.User+" = {:u} && "+f.IsPrimary+" = true && "+f.Status+" = {:active}",
		dbx.Params{"u": userID, "active": util.StatusActive})
	if err != nil {
		return nil
	}
	return rec
}

// OIDCClaims are the claims a person agreed to give a service, by scope. The
// subject is derived per service; everything else appears only under the
// scope that carries it.
func OIDCClaims(app core.App, user *core.Record, clientID string, secret []byte, scopes []string) map[string]any {
	claims := map[string]any{"sub": util.PairwiseSubject(secret, user.Id, clientID)}
	var identity *core.Record
	identityLoaded := false
	primary := func() *core.Record {
		if !identityLoaded {
			identity, identityLoaded = PrimaryIdentity(app, user.Id), true
		}
		return identity
	}
	if slices.Contains(scopes, util.OIDCScopeProfile) {
		name := user.GetString("name")
		if name == "" {
			if id := primary(); id != nil {
				name = id.GetString(util.Fields.Identity.Name)
			}
		}
		if name != "" {
			claims["name"] = name
		}
	}
	if slices.Contains(scopes, util.OIDCScopeEmail) {
		claims["email"] = user.Email()
		claims["email_verified"] = user.Verified()
	}
	if slices.Contains(scopes, util.OIDCScopeIdentity) {
		if id := primary(); id != nil {
			claims[util.OIDCScopeIdentity] = id.GetString(util.Fields.Identity.Fingerprint)
		}
	}
	return claims
}

// SaveSignInGrant gives a service a grant over the entries its user chose at
// sign-in: one link per person and service, updated on every sign-in that
// shares something, with a fresh token each time. choices maps the key the
// service asked for to the person's entry; every entry must be theirs.
func SaveSignInGrant(app core.App, user *core.Record, clientID string, choices map[string]string, token string) (*core.Record, error) {
	grants := map[string]string{}
	var records []string
	for key, recordID := range choices {
		rec, err := app.FindRecordById(util.Coll.Records, recordID)
		if err != nil || rec == nil || rec.GetString(util.Fields.Record.User) != user.Id {
			return nil, ErrSignInRecord
		}
		// Grants point at the entry holding the value, as request answers do.
		if parentID := rec.GetString(util.Fields.Record.AliasOf); parentID != "" {
			if parent, err := app.FindRecordById(util.Coll.Records, parentID); err == nil && parent != nil {
				rec = parent
			}
		}
		grants[key] = rec.Id
		if !slices.Contains(records, rec.Id) {
			records = append(records, rec.Id)
		}
	}

	f := util.Fields.Link
	link, _ := app.FindFirstRecordByFilter(util.Coll.Links,
		f.User+" = {:u} && "+f.SignInClient+" = {:c}", dbx.Params{"u": user.Id, "c": clientID})
	if link == nil {
		col, err := app.FindCollectionByNameOrId(util.Coll.Links)
		if err != nil {
			return nil, err
		}
		slug, err := util.GenerateToken(16)
		if err != nil {
			return nil, err
		}
		link = core.NewRecord(col)
		link.Set(f.Slug, "s_"+slug)
		link.Set(f.User, user.Id)
		link.Set(f.Workspace, user.GetString(util.Fields.User.ActiveWorkspace))
		link.Set(f.SignInClient, clientID)
	}
	link.Set(f.Label, "Sign-in at "+clientID)
	link.Set(f.Status, util.StatusActive)
	link.Set(f.Records, records)
	link.Set(f.Grants, grants)
	link.Set(f.GrantTokenHash, util.HashToken(token))
	if err := app.Save(link); err != nil {
		return nil, err
	}
	return link, nil
}

// ErrSignInRecord is returned by SaveSignInGrant for an entry that is not
// the signed-in person's own.
var ErrSignInRecord = errors.New("entry is not the signed-in person's")
