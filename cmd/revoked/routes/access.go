package routes

import (
	"net/http"
	"slices"

	"revoked/cmd/revoked/services"
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
)

// AccessRoute tells the app who sees and who edits an item (VISIBILITY.md):
//
//	GET /api/access/{collection}/{id}   sections, records, links, requests
//
// The answer is services.Access's, computed on the spot rather than read from
// the stored columns. Only a member who sees the item gets an answer; anyone
// else gets the same 404 as for a missing id. The names behind the counts are
// shown to the owner and to members who may view members; others get counts.
// For people only.
func AccessRoute(app core.App) {
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		e.Router.GET("/api/access/{collection}/{id}", func(re *core.RequestEvent) error {
			if re.Auth == nil {
				return appErrorResponse(re, http.StatusUnauthorized, &util.Errors.NotAuthenticated)
			}
			if re.Auth.Collection().Name != util.Coll.Users {
				return appErrorResponse(re, http.StatusForbidden, &util.Errors.ApiKeyNotPermitted)
			}
			return describeAccess(app, re)
		})
		return e.Next()
	})
}

func describeAccess(app core.App, re *core.RequestEvent) error {
	collection := re.Request.PathValue("collection")
	if collection != util.Coll.Records && !services.HasAudience(collection) {
		return appErrorResponse(re, http.StatusNotFound, &util.Errors.RecordNotFound)
	}
	item, err := app.FindRecordById(collection, re.Request.PathValue("id"))
	me := re.Auth.Id
	if err != nil || item == nil ||
		item.GetString(util.FieldWorkspace) != re.Auth.GetString(util.Fields.User.ActiveWorkspace) ||
		!services.CanSee(app, me, item) {
		return appErrorResponse(re, http.StatusNotFound, &util.Errors.RecordNotFound)
	}

	sum := services.SummarizeAccess(app, item)
	member, _ := util.WorkspaceMemberOf(app, item.GetString(util.FieldWorkspace), me)
	perms := member.GetStringSlice(util.Fields.WorkspaceMember.Permissions)
	namesShown := sum.Owner == me || len(perms) == 0 || slices.Contains(perms, util.ScopeWorkspaceMembersRead)

	emails := map[string]string{}
	email := func(id string) string {
		if e, ok := emails[id]; ok {
			return e
		}
		e := ""
		if u, err := app.FindRecordById(util.Coll.Users, id); err == nil && u != nil {
			e = u.GetString(util.Fields.User.Email)
		}
		emails[id] = e
		return e
	}
	people := func(ids []string) map[string]any {
		out := map[string]any{"count": len(ids)}
		if namesShown {
			list := make([]map[string]any, 0, len(ids))
			for _, id := range ids {
				list = append(list, map[string]any{"id": id, "email": email(id)})
			}
			out["members"] = list
		}
		return out
	}

	body := map[string]any{
		"collection":        collection,
		"id":                item.Id,
		"owner":             map[string]any{"id": sum.Owner, "email": email(sum.Owner)},
		"readers":           people(sum.Readers),
		"editors":           people(sum.Editors),
		"canEdit":           slices.Contains(sum.Editors, me),
		"canChangeAudience": services.HasAudience(collection) && sum.Owner == me,
		"audience":          nil,
	}
	if a := sum.Audience; a != nil {
		groups := make([]map[string]any, 0, len(a.Groups))
		for _, id := range a.Groups {
			if g, err := app.FindRecordById(util.Coll.Groups, id); err == nil && g != nil {
				groups = append(groups, map[string]any{
					"id": g.Id, "key": g.GetString(util.Fields.Group.Key), "name": g.GetString(util.Fields.Group.Name),
				})
			}
		}
		body["audience"] = map[string]any{"kind": a.Kind, "groups": groups, "editing": a.Editing}
	}
	return re.JSON(http.StatusOK, body)
}
