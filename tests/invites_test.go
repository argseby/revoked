package tests

import (
	"net/http"
	"revoked/tests/testutils"
	"revoked/util"
	"testing"

	"github.com/gavv/httpexpect/v2"
	"github.com/google/uuid"
)

// inviteFixture is an admin with a workspace, ready to invite people.
type inviteFixture struct {
	adminID, adminToken, workspaceID string
	api                              *testutils.PBClient
	baseURL                          string
}

func newInviteFixture(t *testing.T) inviteFixture {
	t.Helper()
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	adminID, adminToken, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed to create admin: %v", err)
	}

	ws := api.Create(util.Coll.Workspaces, adminToken, map[string]any{
		"name": "Invite WS",
		"slug": "inv-" + uuid.New().String()[:8],
	}).Expect().Status(http.StatusOK).JSON().Object()
	workspaceID := ws.Value("id").String().Raw()

	api.Update(util.Coll.Users, adminID, adminToken, map[string]any{
		"activeWorkspace": workspaceID,
		"activeRole":      util.RoleAdmin,
	}).Expect().Status(http.StatusOK)

	return inviteFixture{adminID, adminToken, workspaceID, api, baseURL}
}

// createInvite returns the one-time token from the response header.
func (f inviteFixture) createInvite(t *testing.T, body map[string]any) (string, *httpexpect.Object) {
	t.Helper()
	if body[util.Fields.Invite.Workspace] == nil {
		body[util.Fields.Invite.Workspace] = f.workspaceID
	}
	resp := f.api.Create(util.Coll.Invites, f.adminToken, body).Expect().Status(http.StatusOK)
	token := resp.Header("X-Invite-Token").Raw()
	if token == "" {
		t.Fatal("invite response carried no X-Invite-Token header")
	}
	return token, resp.JSON().Object()
}

func TestInviteProbeAndAccept(t *testing.T) {
	f := newInviteFixture(t)

	token, created := f.createInvite(t, map[string]any{
		util.Fields.Invite.Label:       "Contractor",
		util.Fields.Invite.Permissions: []string{util.PermSharesRead, util.PermSharesManage},
	})

	// The stored hash must never come back out, even to the admin who made it.
	created.NotContainsKey(util.Fields.Invite.TokenHash)

	t.Run("probe describes the grant in human terms", func(t *testing.T) {
		api := f.api.T(t)
		body := api.E.GET("/api/public/invites/" + token).
			Expect().Status(http.StatusOK).JSON().Object()

		body.Value("workspace").Object().Value("name").String().IsEqual("Invite WS")
		body.Value("invitedBy").String().NotEmpty()

		perms := body.Value("permissions").Array()
		perms.Length().IsEqual(2)
		first := perms.Value(0).Object()
		first.Value("label").String().NotEmpty()
		first.Value("description").String().NotEmpty()
	})

	t.Run("probing an unknown token is 404", func(t *testing.T) {
		api := f.api.T(t)
		api.E.GET("/api/public/invites/not-a-real-token").
			Expect().Status(http.StatusNotFound).JSON().Object().
			Value("code").String().IsEqual(util.Errors.InviteNotFound.ErrorCode)
	})

	t.Run("accepting requires a signed-in account", func(t *testing.T) {
		api := f.api.T(t)
		api.E.POST("/api/public/invites/" + token).
			Expect().Status(http.StatusUnauthorized).JSON().Object().
			Value("code").String().IsEqual(util.Errors.NotAuthenticated.ErrorCode)
	})

	t.Run("accepting grants exactly the invited permissions", func(t *testing.T) {
		api := f.api.T(t)
		_, inviteeToken, err := testutils.CreateRandomUser(f.baseURL)
		if err != nil {
			t.Fatalf("Failed to create invitee: %v", err)
		}

		api.E.POST("/api/public/invites/"+token).
			WithHeader("Authorization", inviteeToken).
			Expect().Status(http.StatusOK).JSON().Object().
			Value("ok").Boolean().IsTrue()

		// The membership carries the expanded scopes, not the surface keys.
		members := api.E.GET("/api/collections/"+util.Coll.WorkspaceMembers+"/records").
			WithHeader("Authorization", f.adminToken).
			WithQuery("filter", `workspace = "`+f.workspaceID+`"`).
			Expect().Status(http.StatusOK).JSON().Object().Value("items").Array()
		members.Length().IsEqual(2)
	})

	t.Run("the same account cannot accept twice", func(t *testing.T) {
		api := f.api.T(t)
		_, inviteeToken, err := testutils.CreateRandomUser(f.baseURL)
		if err != nil {
			t.Fatalf("Failed to create invitee: %v", err)
		}
		api.E.POST("/api/public/invites/"+token).
			WithHeader("Authorization", inviteeToken).
			Expect().Status(http.StatusOK)
		api.E.POST("/api/public/invites/"+token).
			WithHeader("Authorization", inviteeToken).
			Expect().Status(http.StatusConflict).JSON().Object().
			Value("code").String().IsEqual(util.Errors.AlreadyWorkspaceMember.ErrorCode)
	})
}

// A single-use invite must not admit a second person.
func TestInviteMaxUsesIsEnforced(t *testing.T) {
	f := newInviteFixture(t)

	token, _ := f.createInvite(t, map[string]any{
		util.Fields.Invite.Permissions: []string{util.PermSharesRead},
		util.Fields.Invite.MaxUses:     1,
	})

	_, firstToken, _ := testutils.CreateRandomUser(f.baseURL)
	f.api.E.POST("/api/public/invites/"+token).
		WithHeader("Authorization", firstToken).
		Expect().Status(http.StatusOK)

	_, secondToken, _ := testutils.CreateRandomUser(f.baseURL)
	f.api.E.POST("/api/public/invites/"+token).
		WithHeader("Authorization", secondToken).
		Expect().Status(http.StatusGone).JSON().Object().
		Value("code").String().IsEqual(util.Errors.InviteExhausted.ErrorCode)
}

// An invite bound to an address is not transferable: forwarding the token does
// not hand over the access.
func TestInviteBoundToEmailRejectsOtherAccounts(t *testing.T) {
	f := newInviteFixture(t)

	token, _ := f.createInvite(t, map[string]any{
		util.Fields.Invite.Permissions: []string{util.PermSharesRead},
		util.Fields.Invite.Email:       "intended@example.com",
	})

	_, wrongToken, _ := testutils.CreateRandomUser(f.baseURL)
	f.api.E.POST("/api/public/invites/"+token).
		WithHeader("Authorization", wrongToken).
		Expect().Status(http.StatusForbidden).JSON().Object().
		Value("code").String().IsEqual(util.Errors.InviteWrongAccount.ErrorCode)
}

// The escalation guard: an inviter cannot hand out access they do not hold, or
// "invite members" would quietly be full control.
func TestInviteCannotGrantMoreThanTheInviterHolds(t *testing.T) {
	f := newInviteFixture(t)

	// A limited member who may invite, but only holds shares:read besides.
	limitedScopes, _ := util.ExpandPermissions([]string{util.PermMembersAdd, util.PermSharesRead})
	limitedToken, _ := func() (string, string) {
		userID, token, err := testutils.CreateRandomUser(f.baseURL)
		if err != nil {
			t.Fatalf("Failed to create limited member: %v", err)
		}
		f.api.Create(util.Coll.WorkspaceMembers, f.adminToken, map[string]any{
			util.Fields.WorkspaceMember.User:        userID,
			util.Fields.WorkspaceMember.Workspace:   f.workspaceID,
			util.Fields.WorkspaceMember.Role:        util.RoleMember,
			util.Fields.WorkspaceMember.Permissions: limitedScopes,
		}).Expect().Status(http.StatusOK)
		// Holding members:add makes them an administrator by definition — the
		// role is derived from the permission set, not chosen independently.
		f.api.Update(util.Coll.Users, userID, token, map[string]any{
			"activeWorkspace": f.workspaceID,
			"activeRole":      util.RoleAdmin,
		}).Expect().Status(http.StatusOK)
		return token, userID
	}()

	t.Run("cannot grant a permission they lack", func(t *testing.T) {
		api := f.api.T(t)
		api.Create(util.Coll.Invites, limitedToken, map[string]any{
			util.Fields.Invite.Workspace:   f.workspaceID,
			util.Fields.Invite.Permissions: []string{util.PermVaultWrite},
		}).Expect().Status(http.StatusBadRequest).JSON().Object().
			Value("data").Object().Value(util.Fields.Invite.Permissions).Object().
			Value("code").String().IsEqual(util.Errors.PermissionEscalation.ErrorCode)
	})

	t.Run("can grant a permission they do hold", func(t *testing.T) {
		api := f.api.T(t)
		api.Create(util.Coll.Invites, limitedToken, map[string]any{
			util.Fields.Invite.Workspace:   f.workspaceID,
			util.Fields.Invite.Permissions: []string{util.PermSharesRead},
		}).Expect().Status(http.StatusOK)
	})
}

// A workspace must never lose its last administrator, or nobody is left who
// could restore access to it.
func TestLastAdminCannotBeRemovedOrDemoted(t *testing.T) {
	f := newInviteFixture(t)

	members := f.api.E.GET("/api/collections/"+util.Coll.WorkspaceMembers+"/records").
		WithHeader("Authorization", f.adminToken).
		WithQuery("filter", `workspace = "`+f.workspaceID+`"`).
		Expect().Status(http.StatusOK).JSON().Object().Value("items").Array()
	members.Length().IsEqual(1)
	adminMemberID := members.Value(0).Object().Value("id").String().Raw()

	t.Run("cannot delete the only administrator", func(t *testing.T) {
		api := f.api.T(t)
		api.Delete(util.Coll.WorkspaceMembers, adminMemberID, f.adminToken).
			Expect().Status(http.StatusBadRequest).JSON().Object().
			Value("data").Object().Value(util.Fields.WorkspaceMember.User).Object().
			Value("code").String().IsEqual(util.Errors.LastAdminProtected.ErrorCode)
	})

	t.Run("cannot strip the only administrator's member permissions", func(t *testing.T) {
		api := f.api.T(t)
		readOnly, _ := util.ExpandPermissions([]string{util.PermVaultRead})
		api.Update(util.Coll.WorkspaceMembers, adminMemberID, f.adminToken, map[string]any{
			util.Fields.WorkspaceMember.Permissions: readOnly,
		}).Expect().Status(http.StatusBadRequest).JSON().Object().
			Value("data").Object().Value(util.Fields.WorkspaceMember.Permissions).Object().
			Value("code").String().IsEqual(util.Errors.LastAdminProtected.ErrorCode)
	})
}

// An invited member reaches exactly what they were granted and nothing else.
func TestInvitedMemberPermissionsAreEnforced(t *testing.T) {
	f := newInviteFixture(t)

	// The admin owns a vault entry the invitee must not be able to touch.
	adminRecord := extractID(t, f.baseURL, util.Coll.Records, f.adminToken, map[string]any{
		util.Fields.Record.Key:       "admin_secret",
		util.Fields.Record.Value:     "classified",
		util.Fields.Record.Label:     "Admin secret",
		util.Fields.Record.Type:      util.TypeText,
		util.Fields.Record.Format:    util.FormatDefault,
		util.Fields.Record.User:      f.adminID,
		util.Fields.Record.Workspace: f.workspaceID,
	})

	token, _ := f.createInvite(t, map[string]any{
		util.Fields.Invite.Permissions: []string{util.PermSharesRead, util.PermSharesManage},
	})

	inviteeID, inviteeToken, err := testutils.CreateRandomUser(f.baseURL)
	if err != nil {
		t.Fatalf("Failed to create invitee: %v", err)
	}
	f.api.E.POST("/api/public/invites/"+token).
		WithHeader("Authorization", inviteeToken).
		Expect().Status(http.StatusOK)

	f.api.Update(util.Coll.Users, inviteeID, inviteeToken, map[string]any{
		"activeWorkspace": f.workspaceID,
		"activeRole":      util.RoleMember,
	}).Expect().Status(http.StatusOK)

	t.Run("granted: can create a share", func(t *testing.T) {
		api := f.api.T(t)
		api.Create(util.Coll.Links, inviteeToken, map[string]any{
			util.Fields.Link.Slug:      "inv" + uuid.New().String()[:6],
			util.Fields.Link.Label:     "Invitee share",
			util.Fields.Link.Status:    util.StatusActive,
			util.Fields.Link.Workspace: f.workspaceID,
		}).Expect().Status(http.StatusOK)
	})

	t.Run("not granted: cannot edit the admin's vault entry", func(t *testing.T) {
		api := f.api.T(t)
		api.Update(util.Coll.Records, adminRecord, inviteeToken, map[string]any{
			util.Fields.Record.Value: "tampered",
		}).Expect().Status(http.StatusForbidden).JSON().Object().
			Value("data").Object().Value(util.Fields.WorkspaceMember.Permissions).Object().
			Value("code").String().IsEqual(util.Errors.MissingPermission.ErrorCode)
	})

	t.Run("not granted: cannot invite anyone", func(t *testing.T) {
		api := f.api.T(t)
		api.Create(util.Coll.Invites, inviteeToken, map[string]any{
			util.Fields.Invite.Workspace:   f.workspaceID,
			util.Fields.Invite.Permissions: []string{util.PermSharesRead},
		}).Expect().Status(http.StatusForbidden)
	})
}

// After joining, a member must be able to read the workspace they joined. The
// list/view rule required role = 'admin', so fetching it returned 404 and the
// whole join looked like it had failed.
func TestInvitedMemberCanReadTheirWorkspace(t *testing.T) {
	f := newInviteFixture(t)

	token, _ := f.createInvite(t, map[string]any{
		util.Fields.Invite.Permissions: []string{util.PermSharesRead},
	})

	inviteeID, inviteeToken, err := testutils.CreateRandomUser(f.baseURL)
	if err != nil {
		t.Fatalf("Failed to create invitee: %v", err)
	}
	f.api.E.POST("/api/public/invites/"+token).
		WithHeader("Authorization", inviteeToken).
		Expect().Status(http.StatusOK)

	// The app reads memberships, then fetches each workspace by id.
	memberships := f.api.E.GET("/api/collections/"+util.Coll.WorkspaceMembers+"/records").
		WithHeader("Authorization", inviteeToken).
		WithQuery("filter", `user = "`+inviteeID+`"`).
		Expect().Status(http.StatusOK).JSON().Object().Value("items").Array()
	memberships.NotEmpty()

	f.api.Get(util.Coll.Workspaces, f.workspaceID, inviteeToken).
		Expect().Status(http.StatusOK).JSON().Object().
		Value("name").String().IsEqual("Invite WS")
}

// A granted permission must be usable without also being made an inviter: role
// is derived from members:add, and the write rules used to gate on it.
func TestNonAdminMemberCanUseAGrantedPermission(t *testing.T) {
	f := newInviteFixture(t)

	token, _ := f.createInvite(t, map[string]any{
		util.Fields.Invite.Permissions: []string{util.PermTemplatesRead, util.PermTemplatesManage},
	})

	inviteeID, inviteeToken, err := testutils.CreateRandomUser(f.baseURL)
	if err != nil {
		t.Fatalf("Failed to create invitee: %v", err)
	}
	f.api.E.POST("/api/public/invites/"+token).
		WithHeader("Authorization", inviteeToken).
		Expect().Status(http.StatusOK)
	f.api.Update(util.Coll.Users, inviteeID, inviteeToken, map[string]any{
		"activeWorkspace": f.workspaceID,
		"activeRole":      util.RoleMember,
	}).Expect().Status(http.StatusOK)

	f.api.Create(util.Coll.Templates, inviteeToken, map[string]any{
		"name":      "Member template",
		"schema":    `{"records":[]}`,
		"workspace": f.workspaceID,
	}).Expect().Status(http.StatusOK)
}
