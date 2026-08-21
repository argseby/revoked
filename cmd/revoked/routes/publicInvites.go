package routes

import (
	"fmt"
	"net/http"
	"revoked/cmd/revoked/server"
	"revoked/cmd/revoked/services"
	"revoked/util"
	"strings"

	"github.com/pocketbase/pocketbase/core"
)

// PublicInvitesRoute exposes probing and accepting a workspace invite by token.
// The token is the capability — there is no listing endpoint — and the probe
// deliberately shows the workspace and exact permissions before anyone accepts.
func PublicInvitesRoute(app core.App, root *server.RootKey) {
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		e.Router.GET("/api/public/invites/{token}", func(re *core.RequestEvent) error {
			if !allowRequest(re, probeLimiter, "") {
				return rateLimitedResponse(re)
			}
			invite, appErr := findLiveInvite(app, re.Request.PathValue("token"))
			if appErr != nil {
				return inviteErrorResponse(re, appErr)
			}
			return re.JSON(http.StatusOK, inviteProbe(app, root, invite))
		})

		e.Router.POST("/api/public/invites/{token}", func(re *core.RequestEvent) error {
			if !allowRequest(re, gatePasswordLimiter, "invite") {
				return rateLimitedResponse(re)
			}
			if re.Auth == nil || re.Auth.Collection().Name != util.Coll.Users {
				return appErrorResponse(re, http.StatusUnauthorized, &util.Errors.NotAuthenticated)
			}

			invite, appErr := findLiveInvite(app, re.Request.PathValue("token"))
			if appErr != nil {
				return inviteErrorResponse(re, appErr)
			}

			// An email-bound invite is not transferable by forwarding the token.
			if want := invite.GetString(util.Fields.Invite.Email); want != "" &&
				!strings.EqualFold(want, re.Auth.GetString(util.Fields.User.Email)) {
				return appErrorResponse(re, http.StatusForbidden, &util.Errors.InviteWrongAccount)
			}

			workspaceId := invite.GetString(util.Fields.Invite.Workspace)
			if _, already := util.WorkspaceMemberOf(app, workspaceId, re.Auth.Id); already {
				return appErrorResponse(re, http.StatusConflict, &util.Errors.AlreadyWorkspaceMember)
			}

			// An invite is a delegation of the inviter's own authority, and a
			// token minted before they lost it must not outlive it — otherwise
			// anyone removed from a workspace keeps a working back door into it
			// for as long as their invites have uses left.
			if !inviterCanStillInvite(app, invite) {
				return appErrorResponse(re, http.StatusForbidden, &util.Errors.InviteInviterLostAccess)
			}

			if err := services.ClaimInviteUse(app, invite); err != nil {
				return appErrorResponse(re, http.StatusGone, &util.Errors.InviteExhausted)
			}

			members, err := app.FindCollectionByNameOrId(util.Coll.WorkspaceMembers)
			if err != nil {
				return re.InternalServerError("Membership collection missing", nil)
			}
			member := core.NewRecord(members)
			member.Set(util.Fields.WorkspaceMember.User, re.Auth.Id)
			member.Set(util.Fields.WorkspaceMember.Workspace, workspaceId)
			member.Set(util.Fields.WorkspaceMember.Permissions, services.InviteGrantedScopes(invite))
			role := invite.GetString(util.Fields.Invite.Role)
			if role == "" {
				role = util.RoleMember
			}
			member.Set(util.Fields.WorkspaceMember.Role, role)
			if err := app.Save(member); err != nil {
				app.Logger().Error("Failed to accept invite", "error", err, "invite", invite.Id)
				return re.InternalServerError("Failed to join the workspace", nil)
			}

			services.EmitNotification(app, invite.GetString(util.Fields.Invite.InvitedBy), workspaceId,
				util.NotificationInviteAccepted,
				"Invite accepted",
				re.Auth.GetString(util.Fields.User.Email)+" joined the workspace.",
				util.Coll.Invites, invite.Id)

			return re.JSON(http.StatusOK, map[string]any{
				"ok":          true,
				"workspace":   workspaceId,
				"membership":  member.Id,
				"permissions": util.SurfacesFor(services.InviteGrantedScopes(invite)),
			})
		})

		return e.Next()
	})
}

// findLiveInvite resolves a plaintext token to an invite that may still be
// spent; only the hash is stored.
func findLiveInvite(app core.App, token string) (*core.Record, *util.AppError) {
	if token == "" {
		return nil, &util.Errors.InviteNotFound
	}
	invite, err := app.FindFirstRecordByFilter(util.Coll.Invites,
		"tokenHash = {:h}", map[string]any{"h": util.HashToken(token)})
	if err != nil || invite == nil {
		return nil, &util.Errors.InviteNotFound
	}
	if appErr := services.RefreshInviteStatus(app, invite); appErr != nil {
		return nil, appErr
	}
	return invite, nil
}

func inviteProbe(app core.App, root *server.RootKey, invite *core.Record) map[string]any {
	out := map[string]any{
		"label":         invite.GetString(util.Fields.Invite.Label),
		"role":          invite.GetString(util.Fields.Invite.Role),
		"permissions":   permissionDetails(services.InviteGrantedScopes(invite)),
		"requiresEmail": invite.GetString(util.Fields.Invite.Email) != "",
		"expiresAt":     invite.GetString(util.Fields.Invite.ExpiresAt),
		// Without this the recipient has nothing to walk the DNS chain against,
		// and an invite from a spoofed server is indistinguishable from a real
		// one — which matters more here than anywhere else, because accepting
		// hands an account to whoever is on the other end.
		"server": map[string]any{
			"domain":          root.Domain(),
			"rootFingerprint": root.Fingerprint(),
		},
	}
	if ws, err := app.FindRecordById(util.Coll.Workspaces, invite.GetString(util.Fields.Invite.Workspace)); err == nil && ws != nil {
		out["workspace"] = map[string]any{
			"name": ws.GetString(util.Fields.Workspace.Name),
		}
	}
	if by, err := app.FindRecordById(util.Coll.Users, invite.GetString(util.Fields.Invite.InvitedBy)); err == nil && by != nil {
		email := by.GetString(util.Fields.User.Email)
		// Kept as a bare string beside the block below: an older client reads
		// this key as a string and would crash on a changed type.
		out["invitedBy"] = email
		out["inviter"] = inviterAttestation(app, root, invite, by, email)
	}
	return out
}

// inviterAttestation reports what this server can actually prove about whoever
// created the invite, and nothing more.
//
// The email is not a claim the server can vouch for on its own — there is no
// address-confirmation flow, so a `verified` flag would be theatre. What it can
// state is whose account the address belongs to here, whether the address even
// sits in this server's own domain (an address elsewhere is one the operator
// demonstrably does not control), whether that account may still invite, and
// which identity it holds — the last of which the recipient can verify all the
// way back to DNS, revocation included.
func inviterAttestation(app core.App, root *server.RootKey, invite, by *core.Record, email string) map[string]any {
	att := map[string]any{
		"email":          email,
		"emailDomain":    emailDomain(email),
		"serverDomain":   root.Domain(),
		"canStillInvite": inviterCanStillInvite(app, invite),
	}

	// Exact match only. Treating a parent domain as equivalent needs a public
	// suffix list to be safe, and a wrong "same organisation" is worse than
	// naming both domains and letting the reader judge.
	att["emailMatchesServer"] = emailDomain(email) != "" &&
		strings.EqualFold(emailDomain(email), root.Domain())

	if id := primaryIdentityFor(app, by.Id, invite.GetString(util.Fields.Invite.Workspace)); id != nil {
		identity := map[string]any{
			"name":            id.GetString(util.Fields.Identity.Name),
			"fingerprint":     id.GetString(util.Fields.Identity.Fingerprint),
			"parentSignature": id.GetString(util.Fields.Identity.ParentSignature),
			"domainAtIssue":   id.GetString(util.Fields.Identity.DomainAtIssue),
			"status":          services.IdentityStatusOf(id),
		}
		stapleIdentityStatus(app, root, identity, id.GetString(util.Fields.Identity.Fingerprint))
		att["identity"] = identity
	}
	return att
}

// inviterCanStillInvite reports whether the invite's creator remains a member
// who may invite. An invite with no recorded creator (minted by an API key or a
// superuser) is not attributed to anyone, so there is no authority to re-check.
func inviterCanStillInvite(app core.App, invite *core.Record) bool {
	userId := invite.GetString(util.Fields.Invite.InvitedBy)
	if userId == "" {
		return true
	}
	member, ok := util.WorkspaceMemberOf(app, invite.GetString(util.Fields.Invite.Workspace), userId)
	if !ok {
		return false
	}
	return services.MemberCanAdminister(member)
}

// primaryIdentityFor returns the identity a user signs with in a workspace,
// preferring the one they pinned as primary.
func primaryIdentityFor(app core.App, userId, workspaceId string) *core.Record {
	filter := fmt.Sprintf("%s = {:user} && %s = {:workspace}",
		util.Fields.Identity.User, util.Fields.Identity.Workspace)
	params := map[string]any{"user": userId, "workspace": workspaceId}

	found, err := app.FindRecordsByFilter(
		util.Coll.Identities, filter, "-"+util.Fields.Identity.IsPrimary, 1, 0, params)
	if err != nil || len(found) == 0 {
		return nil
	}
	return found[0]
}

// emailDomain returns the part after the last @, lowercased, or "" when the
// address has no recognisable domain.
func emailDomain(email string) string {
	at := strings.LastIndex(email, "@")
	if at < 0 || at == len(email)-1 {
		return ""
	}
	return strings.ToLower(email[at+1:])
}

// permissionDetails labels granted scopes so screens never show raw scope strings.
func permissionDetails(scopes []string) []map[string]any {
	out := []map[string]any{}
	for _, key := range util.SurfacesFor(scopes) {
		perm, ok := util.PermissionByKey(key)
		if !ok {
			continue
		}
		out = append(out, map[string]any{
			"key":         perm.Key,
			"label":       perm.Label,
			"description": perm.Description,
			"destructive": perm.Destructive,
		})
	}
	return out
}

func inviteErrorResponse(re *core.RequestEvent, appErr *util.AppError) error {
	status := http.StatusGone
	if appErr.ErrorCode == util.Errors.InviteNotFound.ErrorCode {
		status = http.StatusNotFound
	}
	return appErrorResponse(re, status, appErr)
}
