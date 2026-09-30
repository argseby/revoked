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
	// Nobody makes an account through the collection API: an account made
	// here would have a password nothing accepts and no passkey, so it could
	// never be signed into — only squatted on. Registration is the passkey
	// route's, which is also where the operator's signup policy applies. The
	// refusal is for requests only: a superuser creating an account through
	// the dashboard, and the accounts the operator writes directly with
	// app.Save, both still work and get their passkey from a ticket.
	app.OnRecordCreateRequest(util.Coll.Users).BindFunc(func(e *core.RecordRequestEvent) error {
		if !e.RequestEvent.HasSuperuserAuth() {
			reason := util.Errors.PasskeySignupOnly
			if !util.SignupsAllowed() {
				reason = util.Errors.SignupsDisabled
			}
			// Carried in Data, like every other typed hook denial: PocketBase
			// title-cases a bare message, which would stop it being a code.
			return router.NewApiError(http.StatusForbidden,
				reason.ErrorText,
				validation.Errors{
					"signup": validation.NewError(reason.ErrorCode, reason.ErrorText),
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
