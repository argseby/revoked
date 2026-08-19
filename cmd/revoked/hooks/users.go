package hooks

import (
	"fmt"
	"net/http"
	"revoked/util"

	validation "github.com/go-ozzo/ozzo-validation/v4"
	"github.com/pocketbase/pocketbase/apis"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/router"
)

// BindUsersHooks wires the users lifecycle: whether self-service registration
// is accepted at all, sensitive-field restrictions and active workspace/role
// validation on update, and adopting an existing membership as the active
// context on sign-in.
func BindUsersHooks(app core.App) {
	// Self-service registration is off unless the operator turns it on. The
	// collection's create rule stays public because a rule cannot read the
	// environment, so the refusal lives here — which also means it applies to
	// requests only: a superuser creating an account through the dashboard, and
	// the seed accounts written directly with app.Save, both still work.
	app.OnRecordCreateRequest(util.Coll.Users).BindFunc(func(e *core.RecordRequestEvent) error {
		if !util.SignupsAllowed() && !e.RequestEvent.HasSuperuserAuth() {
			// Carried in Data, like every other typed hook denial: PocketBase
			// title-cases a bare message, which would stop it being a code.
			return router.NewApiError(http.StatusForbidden,
				util.Errors.SignupsDisabled.ErrorText,
				validation.Errors{
					"signup": validation.NewError(
						util.Errors.SignupsDisabled.ErrorCode,
						util.Errors.SignupsDisabled.ErrorText,
					),
				})
		}
		return e.Next()
	})

	app.OnRecordUpdateRequest(util.Coll.Users).BindFunc(func(e *core.RecordRequestEvent) error {
		// A nil Auth is a system-level update from another hook, not a request.
		if e.Auth == nil {
			return e.Next()
		}

		info, _ := e.RequestInfo()
		requestedWS := info.Body[util.Fields.User.ActiveWorkspace]
		requestedRole := info.Body[util.Fields.User.ActiveRole]

		if requestedWS != nil || requestedRole != nil {
			// The two fields describe one context and may only change as a pair.
			if requestedWS == nil || requestedRole == nil {
				return apis.NewForbiddenError("activeWorkspace and activeRole must be updated together.", nil)
			}

			targetWS := fmt.Sprintf("%v", requestedWS)
			targetRole := fmt.Sprintf("%v", requestedRole)

			// Clearing both is allowed; any other target must match an existing
			// membership.
			if targetWS != "" || targetRole != "" {
				filter := fmt.Sprintf("%s = {:workspace} && %s = {:user} && %s = {:role}",
					util.Fields.WorkspaceMember.Workspace,
					util.Fields.WorkspaceMember.User,
					util.Fields.WorkspaceMember.Role,
				)
				params := map[string]any{
					"workspace": targetWS,
					"user":      e.Record.Id,
					"role":      targetRole,
				}

				member, err := e.App.FindFirstRecordByFilter(util.Coll.WorkspaceMembers, filter, params)
				if err != nil || member == nil {
					return apis.NewForbiddenError("", nil)
				}
			}
		}

		if err := util.RestrictFields(e,
			util.Fields.User.Email,
			util.Fields.User.Verified,
			util.Fields.User.Avatar,
			util.Fields.User.Active,
		); err != nil {
			return err
		}

		return e.Next()
	})

	app.OnRecordAuthRequest(util.Coll.Users).BindFunc(func(e *core.RecordAuthRequestEvent) error {
		if e.Record == nil {
			return e.Next()
		}

		activeWS := e.Record.GetString(util.Fields.User.ActiveWorkspace)

		// An account can exist without a workspace: the client asks on first run
		// whether to create one or join an existing one. Adopt a membership here
		// only when one already exists, so signing in after accepting an invite
		// lands in the right place.
		if activeWS == "" {
			member, err := e.App.FindFirstRecordByFilter(
				util.Coll.WorkspaceMembers,
				"user = {:user}",
				map[string]any{"user": e.Record.Id},
			)
			if err == nil && member != nil {
				e.Record.Set(util.Fields.User.ActiveWorkspace,
					member.GetString(util.Fields.WorkspaceMember.Workspace))
				e.Record.Set(util.Fields.User.ActiveRole,
					member.GetString(util.Fields.WorkspaceMember.Role))
				if err := e.App.Save(e.Record); err != nil {
					e.App.Logger().Error("Failed to adopt a workspace on sign-in", "error", err)
				}
			}
		}

		return e.Next()
	})

}
