package routes

import (
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"unicode/utf8"

	"revoked/cmd/revoked/services"
	"revoked/util"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
)

// GroupsRoute manages the groups of the caller's active workspace (HR,
// Service, Techs), which an item's audience can name (VISIBILITY.md §6):
//
//	GET    /api/groups                         every group, with its members
//	POST   /api/groups                         {name}: a new group
//	PATCH  /api/groups/{id}                    {name}: rename it
//	DELETE /api/groups/{id}                    delete it; its items fall back to their owner
//	PUT    /api/groups/{id}/members/{user}     add a member of the workspace
//	DELETE /api/groups/{id}/members/{user}     take them out
//
// Every member may list groups. Changing them takes the permission to invite
// members, as it widens or narrows who sees what. People only. Who sees what
// follows on every change, through the group hooks (services.RecomputeGroup).
func GroupsRoute(app core.App) {
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		e.Router.GET("/api/groups", func(re *core.RequestEvent) error {
			ws, ok := groupsCaller(app, re, false)
			if !ok {
				return nil
			}
			return listGroups(app, re, ws)
		})
		e.Router.POST("/api/groups", func(re *core.RequestEvent) error {
			ws, ok := groupsCaller(app, re, true)
			if !ok {
				return nil
			}
			name, ok := groupName(re)
			if !ok {
				return nil
			}
			coll, err := app.FindCollectionByNameOrId(util.Coll.Groups)
			if err != nil {
				return re.InternalServerError("Groups collection missing", nil)
			}
			g := core.NewRecord(coll)
			g.Set(util.Fields.Group.Workspace, ws)
			g.Set(util.Fields.Group.Name, name)
			g.Set(util.Fields.Group.Key, uniqueGroupKey(app, ws, name))
			if err := app.Save(g); err != nil {
				return re.InternalServerError("Failed to create the group", err)
			}
			return re.JSON(http.StatusCreated, groupJSON(app, g))
		})
		e.Router.PATCH("/api/groups/{id}", func(re *core.RequestEvent) error {
			g, ok := groupOfCaller(app, re)
			if !ok {
				return nil
			}
			name, ok := groupName(re)
			if !ok {
				return nil
			}
			g.Set(util.Fields.Group.Name, name)
			if err := app.Save(g); err != nil {
				return re.InternalServerError("Failed to rename the group", err)
			}
			return re.JSON(http.StatusOK, groupJSON(app, g))
		})
		e.Router.DELETE("/api/groups/{id}", func(re *core.RequestEvent) error {
			g, ok := groupOfCaller(app, re)
			if !ok {
				return nil
			}
			if err := app.Delete(g); err != nil {
				return re.InternalServerError("Failed to delete the group", err)
			}
			return re.NoContent(http.StatusNoContent)
		})
		e.Router.PUT("/api/groups/{id}/members/{user}", func(re *core.RequestEvent) error {
			g, ok := groupOfCaller(app, re)
			if !ok {
				return nil
			}
			user := re.Request.PathValue("user")
			if _, member := util.WorkspaceMemberOf(app, g.GetString(util.Fields.Group.Workspace), user); !member {
				return appErrorResponse(re, http.StatusBadRequest, &util.Errors.NotWorkspaceMember)
			}
			gm := util.Fields.GroupMember
			if existing, _ := app.FindFirstRecordByFilter(util.Coll.GroupMembers,
				gm.Group+" = {:g} && "+gm.User+" = {:u}", dbx.Params{"g": g.Id, "u": user}); existing == nil {
				coll, err := app.FindCollectionByNameOrId(util.Coll.GroupMembers)
				if err != nil {
					return re.InternalServerError("Group members collection missing", nil)
				}
				row := core.NewRecord(coll)
				row.Set(gm.Group, g.Id)
				row.Set(gm.User, user)
				if err := app.Save(row); err != nil {
					return re.InternalServerError("Failed to add the member", err)
				}
			}
			return re.JSON(http.StatusOK, groupJSON(app, g))
		})
		e.Router.DELETE("/api/groups/{id}/members/{user}", func(re *core.RequestEvent) error {
			g, ok := groupOfCaller(app, re)
			if !ok {
				return nil
			}
			gm := util.Fields.GroupMember
			if row, _ := app.FindFirstRecordByFilter(util.Coll.GroupMembers,
				gm.Group+" = {:g} && "+gm.User+" = {:u}",
				dbx.Params{"g": g.Id, "u": re.Request.PathValue("user")}); row != nil {
				if err := app.Delete(row); err != nil {
					return re.InternalServerError("Failed to remove the member", err)
				}
			}
			return re.JSON(http.StatusOK, groupJSON(app, g))
		})
		return e.Next()
	})
}

// groupsCaller checks the caller is a person and a member of their active
// workspace, and, to change groups, may invite members.
func groupsCaller(app core.App, re *core.RequestEvent, toChange bool) (string, bool) {
	if re.Auth == nil {
		_ = appErrorResponse(re, http.StatusUnauthorized, &util.Errors.NotAuthenticated)
		return "", false
	}
	if re.Auth.Collection().Name != util.Coll.Users {
		_ = appErrorResponse(re, http.StatusForbidden, &util.Errors.ApiKeyNotPermitted)
		return "", false
	}
	ws := re.Auth.GetString(util.Fields.User.ActiveWorkspace)
	if _, member := util.WorkspaceMemberOf(app, ws, re.Auth.Id); ws == "" || !member {
		_ = appErrorResponse(re, http.StatusForbidden, &util.Errors.NotWorkspaceMember)
		return "", false
	}
	if toChange && !services.HoldsPermission(app, ws, re.Auth.Id, util.ScopeWorkspaceMembersCreate) {
		_ = appErrorResponse(re, http.StatusForbidden, &util.Errors.MissingPermission)
		return "", false
	}
	return ws, true
}

// groupOfCaller loads the group in the path, which must be of the caller's
// active workspace; anything else is a 404.
func groupOfCaller(app core.App, re *core.RequestEvent) (*core.Record, bool) {
	ws, ok := groupsCaller(app, re, true)
	if !ok {
		return nil, false
	}
	g, err := app.FindRecordById(util.Coll.Groups, re.Request.PathValue("id"))
	if err != nil || g == nil || g.GetString(util.Fields.Group.Workspace) != ws {
		_ = appErrorResponse(re, http.StatusNotFound, &util.Errors.GroupNotFound)
		return nil, false
	}
	return g, true
}

func groupName(re *core.RequestEvent) (string, bool) {
	var body struct {
		Name string `json:"name"`
	}
	if err := re.BindBody(&body); err != nil {
		_ = appErrorResponse(re, http.StatusBadRequest, &util.Errors.GroupNameInvalid)
		return "", false
	}
	name := strings.Join(strings.Fields(body.Name), " ")
	if name == "" || utf8.RuneCountInString(name) > 80 {
		_ = appErrorResponse(re, http.StatusBadRequest, &util.Errors.GroupNameInvalid)
		return "", false
	}
	return name, true
}

var groupKeyChars = regexp.MustCompile(`[^a-z0-9_-]+`)

// uniqueGroupKey derives a key from a name, unique in the workspace.
func uniqueGroupKey(app core.App, workspace, name string) string {
	base := strings.Trim(groupKeyChars.ReplaceAllString(strings.ToLower(name), "-"), "-")
	if base == "" {
		base = "group"
	}
	if len(base) > 32 {
		base = base[:32]
	}
	key := base
	for i := 2; ; i++ {
		taken, _ := app.FindFirstRecordByFilter(util.Coll.Groups, "workspace = {:w} && key = {:k}",
			dbx.Params{"w": workspace, "k": key})
		if taken == nil {
			return key
		}
		key = base + "-" + strconv.Itoa(i)
	}
}

func listGroups(app core.App, re *core.RequestEvent, ws string) error {
	rows, err := app.FindRecordsByFilter(util.Coll.Groups, "workspace = {:w}", util.Fields.Group.Name, 0, 0,
		dbx.Params{"w": ws})
	if err != nil {
		return re.InternalServerError("Failed to load groups", err)
	}
	out := make([]map[string]any, 0, len(rows))
	for _, g := range rows {
		out = append(out, groupJSON(app, g))
	}
	return re.JSON(http.StatusOK, map[string]any{
		"groups":    out,
		"canManage": services.HoldsPermission(app, ws, re.Auth.Id, util.ScopeWorkspaceMembersCreate),
	})
}

func groupJSON(app core.App, g *core.Record) map[string]any {
	members := []map[string]any{}
	rows, _ := app.FindAllRecords(util.Coll.GroupMembers, dbx.HashExp{util.Fields.GroupMember.Group: g.Id})
	for _, r := range rows {
		id := r.GetString(util.Fields.GroupMember.User)
		email := ""
		if u, err := app.FindRecordById(util.Coll.Users, id); err == nil && u != nil {
			email = u.GetString(util.Fields.User.Email)
		}
		members = append(members, map[string]any{"id": id, "email": email})
	}
	return map[string]any{
		"id":      g.Id,
		"key":     g.GetString(util.Fields.Group.Key),
		"name":    g.GetString(util.Fields.Group.Name),
		"members": members,
	}
}
