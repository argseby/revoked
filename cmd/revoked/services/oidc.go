package services

import (
	"errors"
	"net/url"
	"regexp"
	"slices"
	"strings"
	"unicode/utf8"

	"revoked/util"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/types"
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

// OIDCClaims are the claims a person agreed to give a service from one of
// their workspaces, by scope. The subject is derived per service and
// workspace; everything else appears only under the scope that carries it.
func OIDCClaims(app core.App, user *core.Record, workspace, clientID string, secret []byte, scopes []string) map[string]any {
	version := 0
	if row := findSignIn(app, user.Id, workspace, clientID); row != nil {
		version = row.GetInt(util.Fields.SignIn.SubjectVersion)
	}
	claims := map[string]any{"sub": util.PairwiseSubject(secret, user.Id, workspace, clientID, version)}
	var identity *core.Record
	identityLoaded := false
	primary := func() *core.Record {
		if !identityLoaded {
			identity, identityLoaded = PrimaryIdentity(app, user.Id), true
		}
		return identity
	}
	if slices.Contains(scopes, util.OIDCScopeProfile) {
		if name := SignInName(app, user.Id, workspace, clientID); name != "" {
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
	workspace := user.GetString(util.Fields.User.ActiveWorkspace)
	grants := map[string]string{}
	var records []string
	for key, recordID := range choices {
		rec, err := app.FindRecordById(util.Coll.Records, recordID)
		if err != nil || rec == nil || rec.GetString(util.Fields.Record.User) != user.Id ||
			rec.GetString(util.Fields.Record.Workspace) != workspace {
			return nil, ErrSignInRecord
		}
		// Grants point at the entry holding the value, as request answers do.
		if parentID := rec.GetString(util.Fields.Record.AliasOf); parentID != "" {
			if parent, err := app.FindRecordById(util.Coll.Records, parentID); err == nil && parent != nil {
				rec = parent
			}
		}
		if IsSealed(rec) {
			return nil, ErrSignInRecord
		}
		grants[key] = rec.Id
		if !slices.Contains(records, rec.Id) {
			records = append(records, rec.Id)
		}
	}

	f := util.Fields.Link
	link, _ := app.FindFirstRecordByFilter(util.Coll.Links,
		f.User+" = {:u} && "+f.Workspace+" = {:w} && "+f.SignInClient+" = {:c}",
		dbx.Params{"u": user.Id, "w": workspace, "c": clientID})
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
		link.Set(f.SignInClient, clientID)
	}
	link.Set(f.Workspace, workspace)
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

// SaveSignInAlias files the entry chosen for key under that key in the person's
// vault, so the next sign-in finds it there. A key already in use stays as it
// is: keys are unique per workspace, and a file can't be an alias. It returns
// the new alias's id, or "" when none was needed.
func SaveSignInAlias(app core.App, user *core.Record, key, recordID string) (string, error) {
	f := util.Fields.Record
	parent, err := app.FindRecordById(util.Coll.Records, recordID)
	if err != nil {
		return "", err
	}
	if parentID := parent.GetString(f.AliasOf); parentID != "" {
		if parent, err = app.FindRecordById(util.Coll.Records, parentID); err != nil {
			return "", err
		}
	}
	if parent.GetString(f.Type) == util.TypeFile {
		return "", nil
	}
	workspace := user.GetString(util.Fields.User.ActiveWorkspace)
	existing, _ := app.FindFirstRecordByFilter(util.Coll.Records,
		f.Key+" = {:k} && "+f.User+" = {:u} && "+f.Workspace+" = {:w}",
		dbx.Params{"k": key, "u": user.Id, "w": workspace})
	if existing != nil {
		return "", nil
	}
	col, err := app.FindCollectionByNameOrId(util.Coll.Records)
	if err != nil {
		return "", err
	}
	alias := core.NewRecord(col)
	alias.Set(f.Key, key)
	alias.Set(f.Label, key)
	alias.Set(f.Type, parent.GetString(f.Type))
	alias.Set(f.Format, parent.GetString(f.Format))
	alias.Set(f.User, user.Id)
	alias.Set(f.Workspace, workspace)
	alias.Set(f.AliasOf, parent.Id)
	if err := app.Save(alias); err != nil {
		return "", err
	}
	return alias.Id, nil
}

var signInSectionKeyInvalid = regexp.MustCompile(`[^a-z0-9_]`)

// SaveSignInSection groups entries made for a service under a section named
// after it, and marks them as made for that service, so the vault can say where
// they came from. Only entries made during a sign-in come here: one the person
// already had stays where they filed it.
func SaveSignInSection(app core.App, user *core.Record, clientID string, entryIDs []string) error {
	host := clientID
	if u, err := url.Parse(clientID); err == nil && u.Hostname() != "" {
		host = u.Hostname()
	}
	if utf8.RuneCountInString(host) > maxSignInSectionName {
		host = string([]rune(host)[:maxSignInSectionName])
	}
	workspace := user.GetString(util.Fields.User.ActiveWorkspace)
	r := util.Fields.Record
	for _, id := range entryIDs {
		rec, err := app.FindRecordById(util.Coll.Records, id)
		if err != nil || rec.GetString(r.User) != user.Id || rec.GetString(r.Workspace) != workspace || IsSealed(rec) {
			return ErrSignInRecord
		}
		rec.Set(r.RequestedBy, host)
		if err := app.Save(rec); err != nil {
			return err
		}
	}

	f := util.Fields.Section
	key := SignInSectionPrefix + signInSectionKeyInvalid.ReplaceAllString(strings.ToLower(host), "_")
	section, _ := app.FindFirstRecordByFilter(util.Coll.Sections,
		f.Key+" = {:k} && "+f.User+" = {:u} && "+f.Workspace+" = {:w}",
		dbx.Params{"k": key, "u": user.Id, "w": workspace})
	if section == nil {
		col, err := app.FindCollectionByNameOrId(util.Coll.Sections)
		if err != nil {
			return err
		}
		section = core.NewRecord(col)
		section.Set(f.Key, key)
		section.Set(f.Name, host)
		section.Set(f.RequestedBy, host)
		section.Set(f.User, user.Id)
		section.Set(f.Workspace, workspace)
	}
	records := section.GetStringSlice(f.Records)
	for _, id := range entryIDs {
		if !slices.Contains(records, id) {
			records = append(records, id)
		}
	}
	section.Set(f.Records, records)
	return app.Save(section)
}

// ErrSignInRecord is returned by SaveSignInGrant for an entry that is not
// the signed-in person's own, or not in their active workspace.
var ErrSignInRecord = errors.New("entry is not the signed-in person's")

// SignInSectionPrefix starts the key of a section holding a service's entries.
const SignInSectionPrefix = "signin_"

// maxSignInSectionName is the shorter of the section name and key limits, once
// the key has its prefix.
const maxSignInSectionName = 93

// SignInNameKey is the key a name read from the vault is shared under, so a
// service can read it again and see it change.
const SignInNameKey = "name"

// maxSignInNameRunes keeps a long note or a pasted document out of a claim.
const maxSignInNameRunes = 200

// Where a name for a service comes from.
const (
	NameFromRecord   = "record"
	NameFromIdentity = "identity"
)

// SignInNameChoice is the name a person picked for a service.
type SignInNameChoice struct {
	Kind string `json:"kind"`
	ID   string `json:"id"`
}

// ErrSignInName is returned for a name that is not the person's own to give,
// or could not be one.
var ErrSignInName = errors.New("not a usable name")

// RecordNameValue is what a vault entry reads as a name. Sealed entries are
// never read, and a hidden one holds something its owner keeps off the screen,
// not a name.
func RecordNameValue(app core.App, rec *core.Record) (string, bool) {
	f := util.Fields.Record
	if parentID := rec.GetString(f.AliasOf); parentID != "" {
		parent, err := app.FindRecordById(util.Coll.Records, parentID)
		if err != nil || parent == nil {
			return "", false
		}
		rec = parent
	}
	if IsSealed(rec) || rec.GetString(f.Type) != util.TypeText || rec.GetString(f.Format) == util.FormatHidden {
		return "", false
	}
	value := strings.TrimSpace(rec.GetString(f.Value))
	if value == "" || utf8.RuneCountInString(value) > maxSignInNameRunes {
		return "", false
	}
	return value, true
}

// CheckSignInName refuses a name that is not userID's own: relation validation
// checks only that the row exists, and identity ids are public.
func CheckSignInName(app core.App, userID string, choice SignInNameChoice) error {
	switch choice.Kind {
	case NameFromRecord:
		rec, err := app.FindRecordById(util.Coll.Records, choice.ID)
		if err != nil || rec == nil || rec.GetString(util.Fields.Record.User) != userID {
			return ErrSignInName
		}
		if _, ok := RecordNameValue(app, rec); !ok {
			return ErrSignInName
		}
	case NameFromIdentity:
		if identityName(app, userID, choice.ID) == "" {
			return ErrSignInName
		}
	default:
		return ErrSignInName
	}
	return nil
}

func identityName(app core.App, userID, identityID string) string {
	f := util.Fields.Identity
	id, err := app.FindRecordById(util.Coll.Identities, identityID)
	if err != nil || id == nil || id.GetString(f.User) != userID || id.GetString(f.Status) != util.StatusActive {
		return ""
	}
	return id.GetString(f.Name)
}

// SignInName reads the name a person chose for a service from a workspace as
// it stands now. A name from the vault is shared through the service's link,
// so revoking or pausing that link stops the name too.
func SignInName(app core.App, userID, workspace, clientID string) string {
	row := findSignIn(app, userID, workspace, clientID)
	if row == nil {
		return ""
	}
	f := util.Fields.SignIn
	if id := row.GetString(f.NameIdentity); id != "" {
		return identityName(app, userID, id)
	}
	recordID := row.GetString(f.NameRecord)
	if recordID == "" {
		return ""
	}
	link, err := app.FindRecordById(util.Coll.Links, row.GetString(f.Link))
	if err != nil || link == nil || link.GetString(util.Fields.Link.Status) != util.StatusActive {
		return ""
	}
	rec, err := app.FindRecordById(util.Coll.Records, recordID)
	if err != nil || rec == nil || rec.GetString(util.Fields.Record.User) != userID {
		return ""
	}
	value, _ := RecordNameValue(app, rec)
	return value
}

// RememberedSignInName is the choice a person made at their last sign-in at a
// service from a workspace, whether or not it is still usable.
func RememberedSignInName(app core.App, userID, workspace, clientID string) *SignInNameChoice {
	row := findSignIn(app, userID, workspace, clientID)
	if row == nil {
		return nil
	}
	f := util.Fields.SignIn
	if id := row.GetString(f.NameIdentity); id != "" {
		return &SignInNameChoice{Kind: NameFromIdentity, ID: id}
	}
	if id := row.GetString(f.NameRecord); id != "" {
		return &SignInNameChoice{Kind: NameFromRecord, ID: id}
	}
	return nil
}

// DropSignInNameGrant takes the name out of a service's link when the person
// stopped giving it one from the vault: the service's token must not go on
// reading the old entry. A link left with nothing to read is revoked.
func DropSignInNameGrant(app core.App, userID, workspace, clientID string) error {
	f := util.Fields.Link
	link := signInLink(app, userID, workspace, clientID)
	if link == nil {
		return nil
	}
	grants := map[string]string{}
	_ = link.UnmarshalJSONField(f.Grants, &grants)
	if _, ok := grants[SignInNameKey]; !ok {
		return nil
	}
	delete(grants, SignInNameKey)
	records := []string{}
	for _, id := range grants {
		if !slices.Contains(records, id) {
			records = append(records, id)
		}
	}
	link.Set(f.Grants, grants)
	link.Set(f.Records, records)
	if len(grants) == 0 {
		link.Set(f.Status, util.StatusRevoked)
	}
	return app.Save(link)
}

// FindSignIn is a person's row for a service from one of their workspaces, if
// they ever signed in there from it. Each workspace is its own account there.
func FindSignIn(app core.App, userID, workspace, clientID string) *core.Record {
	return findSignIn(app, userID, workspace, clientID)
}

func findSignIn(app core.App, userID, workspace, clientID string) *core.Record {
	f := util.Fields.SignIn
	row, err := app.FindFirstRecordByFilter(util.Coll.SignIns,
		f.User+" = {:u} && "+f.Workspace+" = {:w} && "+f.ClientId+" = {:c}",
		dbx.Params{"u": userID, "w": workspace, "c": clientID})
	if err != nil {
		return nil
	}
	return row
}

// SignInApproval is what one approved sign-in adds to a person's row for a
// service. Name is nil when they gave no name; NameAsked says the service asked
// for one, so that nil means they withdrew it rather than were never asked.
type SignInApproval struct {
	Scopes    []string
	LinkID    string
	NameAsked bool
	Name      *SignInNameChoice
}

// RecordSignIn notes an approved sign-in: one row per person, workspace and
// service.
// Scopes only accumulate, because a service keeps what it once learned. A
// sign-in that shares nothing leaves the row's link alone: the earlier grant
// is still live.
func RecordSignIn(app core.App, userID, workspace, clientID string, approval SignInApproval) (*core.Record, error) {
	f := util.Fields.SignIn
	row := findSignIn(app, userID, workspace, clientID)
	if row == nil {
		col, err := app.FindCollectionByNameOrId(util.Coll.SignIns)
		if err != nil {
			return nil, err
		}
		row = core.NewRecord(col)
		row.Set(f.User, userID)
		row.Set(f.Workspace, workspace)
		row.Set(f.ClientId, clientID)
	}

	learned := []string{}
	_ = row.UnmarshalJSONField(f.Scopes, &learned)
	for _, s := range approval.Scopes {
		if s != util.OIDCScopeOpenID && !slices.Contains(learned, s) {
			learned = append(learned, s)
		}
	}
	row.Set(f.Scopes, learned)
	row.Set(f.LastSignInAt, types.NowDateTime())
	row.Set(f.Status, util.StatusActive)
	row.Set(f.NewIdOnReturn, false)
	if approval.LinkID != "" {
		row.Set(f.Link, approval.LinkID)
	}
	if approval.NameAsked {
		row.Set(f.NameRecord, "")
		row.Set(f.NameIdentity, "")
		if n := approval.Name; n != nil && n.Kind == NameFromRecord {
			row.Set(f.NameRecord, n.ID)
		} else if n != nil {
			row.Set(f.NameIdentity, n.ID)
		}
	}
	if err := app.Save(row); err != nil {
		return nil, err
	}
	return row, nil
}
