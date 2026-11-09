package routes

import (
	"net/http"
	"slices"

	"revoked/cmd/revoked/services"
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
)

// SharedVaultRoute serves what other members shared with the caller:
//
//	GET /api/shared/vault   the sections shared in the active workspace by
//	                        anyone else, and the records in them
//
// Who sees what comes from services.Access (VISIBILITY.md). The same rows are
// also open through the collection API, whose rules match the readers and
// editors the server keeps; this route groups them by section and names the
// owner, which the app shows. For people only: a key or a tool reaches the
// vault through /api/vault.
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
	_, isMember := util.WorkspaceMemberOf(app, workspace, re.Auth.Id)
	if workspace == "" || !isMember {
		return appErrorResponse(re, http.StatusForbidden, &util.Errors.NotWorkspaceMember)
	}

	// Who sees what is services.Access's answer (VISIBILITY.md): the section's
	// audience, the member's permissions, the owner's own records only.
	rows, held, err := services.SharedWithMember(app, workspace, re.Auth.Id)
	if err != nil {
		return re.InternalServerError("Failed to read sections.", err)
	}

	s := util.Fields.Section
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
		for _, rec := range held[section.Id] {
			ids = append(ids, rec.Id)
			if seen[rec.Id] {
				continue
			}
			seen[rec.Id] = true
			records = append(records, sharedRecordJSON(rec))
		}
		a := services.SectionAudience(section)
		sections = append(sections, map[string]any{
			"id":             section.Id,
			"key":            section.GetString(s.Key),
			"name":           section.GetString(s.Name),
			"user":           owner,
			"ownerEmail":     ownerEmail(owner),
			"workspace":      workspace,
			"records":        ids,
			"shared":         a.Kind == util.AudienceWorkspace,
			"audienceKind":   a.Kind,
			"audienceGroups": nonNilIds(a.Groups),
			"editing":        a.Editing,
			"canEdit":        services.CanEdit(app, re.Auth.Id, section),
		})
	}
	// Entries shared on their own, outside any section shared with this
	// member: listed by id under entries.
	direct, err := services.DirectlySharedRecords(app, workspace, re.Auth.Id)
	if err != nil {
		return re.InternalServerError("Failed to read entries.", err)
	}
	entries := make([]map[string]any, 0, len(direct))
	for _, rec := range direct {
		owner := rec.GetString(util.Fields.Record.User)
		entries = append(entries, map[string]any{
			"id": rec.Id, "user": owner, "ownerEmail": ownerEmail(owner),
			"canEdit": services.CanEdit(app, re.Auth.Id, rec),
		})
		if !seen[rec.Id] {
			seen[rec.Id] = true
			records = append(records, sharedRecordJSON(rec))
		}
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
	return re.JSON(http.StatusOK, map[string]any{"sections": sections, "records": records, "entries": entries})
}

func nonNilIds(ids []string) []string {
	if ids == nil {
		return []string{}
	}
	return ids
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
