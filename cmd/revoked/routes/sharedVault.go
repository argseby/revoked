package routes

import (
	"net/http"
	"slices"

	"revoked/cmd/revoked/services"
	"revoked/util"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
)

// SharedVaultRoute serves what other members shared with the caller:
//
//	GET /api/shared/vault   the sections shared in the active workspace by
//	                        anyone else, and the records in them
//
// Read-only: changing a record stays with its owner, through the collection
// rules that were never widened for this. Membership and the vault-read
// permission are checked here, in Go, because a rule cannot follow a record
// into the sections that hold it (ACCESS.md). For people only: a key or a tool
// reaches the vault through /api/vault.
//
// Encrypted records come as ciphertext, readable on devices given the
// workspace key. Files and aliases are left out: a file's bytes have no
// member download path yet, and an alias would show a record its owner never
// shared.
func SharedVaultRoute(app core.App) {
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		e.Router.GET("/api/shared/vault", func(re *core.RequestEvent) error {
			if re.Auth == nil {
				return appErrorResponse(re, http.StatusUnauthorized, &util.Errors.NotAuthenticated)
			}
			if re.Auth.Collection().Name != util.Coll.Users {
				return appErrorResponse(re, http.StatusForbidden, &util.Errors.ApiKeyNotPermitted)
			}
			return listSharedVault(app, re)
		})
		return e.Next()
	})
}

func listSharedVault(app core.App, re *core.RequestEvent) error {
	workspace := re.Auth.GetString(util.Fields.User.ActiveWorkspace)
	member, isMember := util.WorkspaceMemberOf(app, workspace, re.Auth.Id)
	if workspace == "" || !isMember {
		return appErrorResponse(re, http.StatusForbidden, &util.Errors.NotWorkspaceMember)
	}
	if !services.MemberCanReadRecords(member) {
		return appErrorResponse(re, http.StatusForbidden, &util.Errors.MissingPermission)
	}

	s := util.Fields.Section
	rows, err := app.FindRecordsByFilter(util.Coll.Sections,
		s.Workspace+" = {:w} && "+s.Shared+" = true && "+s.User+" != {:me}", s.Name, 0, 0,
		dbx.Params{"w": workspace, "me": re.Auth.Id})
	if err != nil {
		return re.InternalServerError("Failed to read sections.", err)
	}

	r := util.Fields.Record
	owners := map[string]string{}
	ownerEmail := func(id string) string {
		if email, ok := owners[id]; ok {
			return email
		}
		email := ""
		if user, err := app.FindRecordById(util.Coll.Users, id); err == nil && user != nil {
			email = user.GetString(util.Fields.User.Email)
		}
		owners[id] = email
		return email
	}

	sections := make([]map[string]any, 0, len(rows))
	records := []map[string]any{}
	seen := map[string]bool{}
	for _, section := range rows {
		owner := section.GetString(s.User)
		ids := []string{}
		for _, id := range section.GetStringSlice(s.Records) {
			rec, err := app.FindRecordById(util.Coll.Records, id)
			// Only the section owner's own records in this workspace: a section
			// naming someone else's record shares nothing of theirs.
			if err != nil || rec == nil ||
				rec.GetString(r.Workspace) != workspace || rec.GetString(r.User) != owner ||
				rec.GetString(r.Type) == util.TypeFile || rec.GetString(r.AliasOf) != "" {
				continue
			}
			ids = append(ids, rec.Id)
			if seen[rec.Id] {
				continue
			}
			seen[rec.Id] = true
			records = append(records, sharedRecordJSON(rec))
		}
		sections = append(sections, map[string]any{
			"id":         section.Id,
			"key":        section.GetString(s.Key),
			"name":       section.GetString(s.Name),
			"user":       owner,
			"ownerEmail": ownerEmail(owner),
			"workspace":  workspace,
			"records":    ids,
			"shared":     true,
		})
	}
	slices.SortStableFunc(records, func(a, b map[string]any) int {
		if a["label"].(string) < b["label"].(string) {
			return -1
		}
		if a["label"].(string) > b["label"].(string) {
			return 1
		}
		return 0
	})
	return re.JSON(http.StatusOK, map[string]any{"sections": sections, "records": records})
}

// sharedRecordJSON is a record as the collection API would show its owner, minus
// what only the owner needs: the hash salt, and who wrote it on their behalf.
func sharedRecordJSON(rec *core.Record) map[string]any {
	r := util.Fields.Record
	out := map[string]any{"id": rec.Id}
	for _, name := range []string{
		r.Key, r.Label, r.Type, r.Format, r.User, r.Workspace, r.Created, r.Updated,
		r.Sealed, r.SealedValue, r.SealedVersion, r.KeyEpoch, r.KeyWrap,
	} {
		out[name] = rec.Get(name)
	}
	if rec.GetBool(r.Sealed) {
		out[r.Value] = ""
	} else {
		out[r.Value] = rec.GetString(r.Value)
	}
	return out
}
