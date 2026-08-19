package tests

import (
	"net/http"
	"revoked/tests/testutils"
	"revoked/util"
	"testing"
)

// The collection API cannot answer "who is in this workspace" — users.viewRule
// is self-only, so expanding the relation hides every other member.
func TestWorkspaceMembersListing(t *testing.T) {
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

	path := "/api/workspaces/" + f.workspaceID + "/members"

	t.Run("lists both members with readable permissions", func(t *testing.T) {
		body := f.api.E.GET(path).
			WithHeader("Authorization", f.adminToken).
			Expect().Status(http.StatusOK).JSON().Object()

		members := body.Value("members").Array()
		members.Length().IsEqual(2)
		body.Value("canManage").Boolean().IsTrue()
		body.Value("grantable").Array().NotEmpty()

		var invited map[string]any
		for _, raw := range members.Iter() {
			entry := raw.Object().Raw()
			if entry["user"] == inviteeID {
				invited = entry
			}
		}
		if invited == nil {
			t.Fatal("the invited member is missing from the listing")
		}
		if invited["email"] == "" || invited["email"] == nil {
			t.Fatal("a member listing without an email cannot identify anyone")
		}
		perms := invited["permissions"].([]any)
		if len(perms) == 0 {
			t.Fatal("expected the granted permission to be listed")
		}
		if invited["isSelf"] != false {
			t.Fatal("the invitee is not the caller")
		}
	})

	t.Run("the sole administrator is flagged so removal can be prevented", func(t *testing.T) {
		body := f.api.E.GET(path).
			WithHeader("Authorization", f.adminToken).
			Expect().Status(http.StatusOK).JSON().Object()

		for _, raw := range body.Value("members").Array().Iter() {
			entry := raw.Object().Raw()
			if entry["isSelf"] == true {
				if entry["isLastAdmin"] != true {
					t.Fatal("the only member able to invite should be flagged")
				}
			}
		}
	})

	t.Run("an outsider cannot list members", func(t *testing.T) {
		_, outsider, err := testutils.CreateRandomUser(f.baseURL)
		if err != nil {
			t.Fatalf("Failed to create outsider: %v", err)
		}
		f.api.E.GET(path).
			WithHeader("Authorization", outsider).
			Expect().Status(http.StatusForbidden).JSON().Object().
			Value("code").String().IsEqual(util.Errors.NotWorkspaceMember.ErrorCode)
	})
}

// A member's permissions are updated by sending permission keys, the same
// vocabulary the invite picker uses.
func TestMemberPermissionsCanBeUpdatedByKey(t *testing.T) {
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

	var memberID string
	body := f.api.E.GET("/api/workspaces/"+f.workspaceID+"/members").
		WithHeader("Authorization", f.adminToken).
		Expect().Status(http.StatusOK).JSON().Object()
	for _, raw := range body.Value("members").Array().Iter() {
		entry := raw.Object().Raw()
		if entry["user"] == inviteeID {
			memberID = entry["id"].(string)
		}
	}
	if memberID == "" {
		t.Fatal("could not find the invited member")
	}

	f.api.Update(util.Coll.WorkspaceMembers, memberID, f.adminToken, map[string]any{
		util.Fields.WorkspaceMember.Permissions: []string{
			util.PermVaultRead, util.PermSharesManage,
		},
	}).Expect().Status(http.StatusOK)

	updated := f.api.E.GET("/api/workspaces/"+f.workspaceID+"/members").
		WithHeader("Authorization", f.adminToken).
		Expect().Status(http.StatusOK).JSON().Object()
	for _, raw := range updated.Value("members").Array().Iter() {
		entry := raw.Object().Raw()
		if entry["user"] != inviteeID {
			continue
		}
		keys := map[string]bool{}
		for _, p := range entry["permissions"].([]any) {
			keys[p.(map[string]any)["key"].(string)] = true
		}
		if !keys[util.PermVaultRead] || !keys[util.PermSharesManage] {
			t.Fatalf("permissions were not applied: %v", keys)
		}
	}

	f.api.Delete(util.Coll.WorkspaceMembers, memberID, f.adminToken).
		Expect().Status(http.StatusNoContent)
}
