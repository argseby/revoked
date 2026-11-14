package services

import (
	"slices"
	"strings"

	"revoked/util"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
)

// Credential kinds: a key the workspace made for its own scripts, or a tool
// someone connected from the app.
const (
	CredentialApiKey     = "apiKey"
	CredentialConnection = "connection"
)

// Credential is what a key or a connected tool may do, and where in the vault:
// one shape for both, so the vault routes check them the same way.
type Credential struct {
	Kind      string
	Id        string
	Name      string
	User      string
	Workspace string
	Scopes    []string

	VaultAccess string
	// WholeVault is the owner's own records, all of them. Only a connection
	// answered on the owner's machine holds it.
	WholeVault bool
	// Sections are every section within reach; Writable are those it may
	// add records to.
	Sections []string
	Writable []string

	Record *core.Record
}

// ConnectionCredential describes a connection as presented by one of its
// tokens: a token collected by polling never reaches the whole vault.
func ConnectionCredential(conn, token *core.Record) Credential {
	f := util.Fields.Connection
	c := Credential{
		Kind:        CredentialConnection,
		Id:          conn.Id,
		Name:        conn.GetString(f.ClientName),
		User:        conn.GetString(f.User),
		Workspace:   conn.GetString(f.Workspace),
		Scopes:      conn.GetStringSlice(f.Scopes),
		VaultAccess: conn.GetString(f.VaultAccess),
		WholeVault: conn.GetBool(f.AllowVaultRead) &&
			token != nil && !token.GetBool(util.Fields.ConnectionToken.Poll),
		Record: conn,
	}
	if c.Name == "" {
		c.Name = conn.GetString(f.ClientId)
	}
	if own := conn.GetString(f.Section); own != "" && !conn.GetBool(f.SectionOff) {
		c.Sections = append(c.Sections, own)
		c.Writable = append(c.Writable, own)
	}
	for _, s := range conn.GetStringSlice(f.Sections) {
		if !slices.Contains(c.Sections, s) {
			c.Sections = append(c.Sections, s)
		}
	}
	return c
}

// ApiKeyCredential describes a key. Every section chosen for it is its own to
// write to: the key is the workspace's own script.
func ApiKeyCredential(key *core.Record) Credential {
	f := util.Fields.ApiKey
	sections := key.GetStringSlice(f.Sections)
	return Credential{
		Kind:        CredentialApiKey,
		Id:          key.Id,
		Name:        key.GetString(f.Label),
		User:        key.GetString(f.User),
		Workspace:   key.GetString(f.Workspace),
		Scopes:      key.GetStringSlice(f.Scopes),
		VaultAccess: key.GetString(f.VaultAccess),
		Sections:    sections,
		Writable:    sections,
		Record:      key,
	}
}

// ToolSectionPrefix namespaces a connection's groups under its own grant.
func (c Credential) ToolSectionPrefix() string {
	if c.Kind != CredentialConnection || c.Record == nil || c.Record.GetBool(util.Fields.Connection.SectionOff) {
		return ""
	}
	parent := c.Record.GetString(util.Fields.Connection.Section)
	if parent == "" {
		return ""
	}
	return "tool_" + c.Id + "_" + parent + "_"
}

func (c Credential) CanWriteSection(app core.App, id string) bool {
	if !c.WritesVault() {
		return false
	}
	for _, section := range c.ReachedSections(app) {
		if section.Id == id && (slices.Contains(c.Writable, id) || (c.ToolSectionPrefix() != "" && strings.HasPrefix(section.GetString(util.Fields.Section.Key), c.ToolSectionPrefix()) && section.GetString(util.Fields.Section.User) == c.User)) {
			return true
		}
	}
	return false
}

// Has reports whether the credential holds a scope.
func (c Credential) Has(scope string) bool {
	return slices.Contains(c.Scopes, scope)
}

// ReadsVault reports whether it reaches any part of the vault.
func (c Credential) ReadsVault() bool {
	return c.VaultAccess != "" && (c.WholeVault || len(c.Sections) > 0)
}

// WritesVault reports whether it may add records anywhere.
func (c Credential) WritesVault() bool {
	return c.VaultAccess == util.VaultAccessWrite && len(c.Writable) > 0
}

// Wrote reports whether this credential wrote the record. Only those it may
// change: a record the owner put in its section is the owner's.
func (c Credential) Wrote(rec *core.Record) bool {
	return rec.GetString(util.Fields.Record.WrittenBy) == c.Id
}

// inWorkspaceVault is the part of the workspace any reach is drawn from: the
// owner's entries, never what arrived by answering a request, and never one
// this server cannot read.
func (c Credential) inWorkspaceVault(app core.App, rec *core.Record) bool {
	f := util.Fields.Record
	return rec.GetString(f.Workspace) == c.Workspace &&
		rec.GetString(f.RequestedBy) == "" &&
		!IsSealedThroughAlias(app, rec)
}

// ReachedSections loads the sections within reach that still exist in its
// workspace, in reach order.
func (c Credential) ReachedSections(app core.App) []*core.Record {
	if len(c.Sections) == 0 {
		return nil
	}
	found, err := app.FindRecordsByIds(util.Coll.Sections, c.Sections)
	if err != nil {
		return nil
	}
	byId := map[string]*core.Record{}
	ids := slices.Clone(c.Sections)
	if prefix := c.ToolSectionPrefix(); prefix != "" {
		parentPresent := slices.ContainsFunc(found, func(s *core.Record) bool {
			return s.Id == c.Record.GetString(util.Fields.Connection.Section) && s.GetString(util.Fields.Section.User) == c.User && s.GetString(util.Fields.Section.Workspace) == c.Workspace
		})
		if parentPresent {
			children, _ := app.FindRecordsByFilter(util.Coll.Sections, "workspace = {:ws} && user = {:user} && key ~ {:prefix}", "created", 0, 0, dbx.Params{"ws": c.Workspace, "user": c.User, "prefix": prefix})
			for _, child := range children {
				if strings.HasPrefix(child.GetString(util.Fields.Section.Key), prefix) && child.GetString(util.Fields.Section.RequestedBy) == "" && !slices.Contains(ids, child.Id) {
					found = append(found, child)
					ids = append(ids, child.Id)
				}
			}
		}
	}
	for _, s := range found {
		if s.GetString(util.Fields.Section.Workspace) == c.Workspace {
			byId[s.Id] = s
		}
	}
	out := []*core.Record{}
	for _, id := range ids {
		if s, ok := byId[id]; ok {
			out = append(out, s)
		}
	}
	return out
}

// RecordsInReach lists the records it may read, by key. Checked on every
// request, never cached: taking a record out of a section takes it out of
// reach at once.
func (c Credential) RecordsInReach(app core.App) ([]*core.Record, error) {
	if !c.ReadsVault() {
		return nil, nil
	}
	var rows []*core.Record
	if c.WholeVault {
		found, err := app.FindRecordsByFilter(util.Coll.Records,
			"workspace = {:ws} && user = {:user} && requestedBy = ''", "key", 1000, 0,
			dbx.Params{"ws": c.Workspace, "user": c.User})
		if err != nil {
			return nil, err
		}
		rows = found
	} else {
		ids := []string{}
		for _, s := range c.ReachedSections(app) {
			for _, id := range s.GetStringSlice(util.Fields.Section.Records) {
				if !slices.Contains(ids, id) {
					ids = append(ids, id)
				}
			}
		}
		if len(ids) == 0 {
			return nil, nil
		}
		found, err := app.FindRecordsByIds(util.Coll.Records, ids)
		if err != nil {
			return nil, err
		}
		slices.SortFunc(found, func(a, b *core.Record) int {
			if a.GetString(util.Fields.Record.Key) < b.GetString(util.Fields.Record.Key) {
				return -1
			}
			return 1
		})
		rows = found
	}
	out := make([]*core.Record, 0, len(rows))
	for _, rec := range rows {
		if c.inWorkspaceVault(app, rec) {
			out = append(out, rec)
		}
	}
	return out, nil
}

// RecordInReach reports whether it may read one record.
func (c Credential) RecordInReach(app core.App, rec *core.Record) bool {
	if !c.ReadsVault() || rec == nil || !c.inWorkspaceVault(app, rec) {
		return false
	}
	if c.WholeVault {
		return rec.GetString(util.Fields.Record.User) == c.User
	}
	return len(c.SectionsHolding(app, rec)) > 0
}

// SectionsHolding lists the reached sections a record sits in.
func (c Credential) SectionsHolding(app core.App, rec *core.Record) []string {
	out := []string{}
	for _, s := range c.ReachedSections(app) {
		if slices.Contains(s.GetStringSlice(util.Fields.Section.Records), rec.Id) {
			out = append(out, s.Id)
		}
	}
	return out
}

// SectionInReach reports whether a section is within reach, for sharing it.
func (c Credential) SectionInReach(app core.App, id string) bool {
	if !c.ReadsVault() {
		return false
	}
	if c.WholeVault {
		s, err := app.FindRecordById(util.Coll.Sections, id)
		return err == nil && s != nil && s.GetString(util.Fields.Section.Workspace) == c.Workspace &&
			s.GetString(util.Fields.Section.User) == c.User && s.GetString(util.Fields.Section.RequestedBy) == ""
	}
	return slices.ContainsFunc(c.ReachedSections(app), func(s *core.Record) bool { return s.Id == id })
}

// StoredBytes is what this credential keeps in the vault: the size of the
// files it wrote and the length of its values.
func (c Credential) StoredBytes(app core.App, except string) (int64, error) {
	var total float64
	err := app.DB().
		NewQuery("SELECT COALESCE(SUM(size), 0) + COALESCE(SUM(LENGTH(value)), 0) FROM " + util.Coll.Records +
			" WHERE writtenBy = {:by} AND id != {:id}").
		Bind(dbx.Params{"by": c.Id, "id": except}).Row(&total)
	return int64(total), err
}
