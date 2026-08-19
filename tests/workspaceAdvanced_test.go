package tests

import (
	"net/http"
	"revoked/tests/testutils"
	"revoked/util"
	"testing"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
)

func TestWorkspaceAdvanced_SideEffects_Refactored(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	userA_ID, userA_Token, _ := testutils.CreateRandomUser(baseURL)
	userB_ID, userB_Token, _ := testutils.CreateRandomUser(baseURL)

	var workspaceID string

	t.Run("Setup: User A creates a business workspace and User B is added", func(t *testing.T) {
		api := api.T(t)
		ws := api.Create(util.Coll.Workspaces, userA_Token, map[string]any{
			"name": "Shared Business",
			"slug": "ws-shared-" + uuid.New().String()[:8],
		}).Expect().Status(http.StatusOK)

		workspaceID = testutils.ExtractString(ws, "id")

		// Members can only be managed from the active workspace context.
		api.Update(util.Coll.Users, userA_ID, userA_Token, map[string]any{
			"activeWorkspace": workspaceID,
			"activeRole":      util.RoleAdmin,
		}).Expect().Status(http.StatusOK)

		api.Create(util.Coll.WorkspaceMembers, userA_Token, map[string]any{
			"user":      userB_ID,
			"workspace": workspaceID,
			"role":      util.RoleMember,
		}).Expect().Status(http.StatusOK)
	})

	t.Run("Security: Admin cannot add users to a workspace that is not their active context", func(t *testing.T) {
		api := api.T(t)
		ws := api.Create(util.Coll.Workspaces, userA_Token, map[string]any{
			"name": "User A Private Workspace",
			"slug": "ws-private-" + uuid.New().String()[:8],
		}).Expect().Status(http.StatusOK)

		privateWorkspaceID := testutils.ExtractString(ws, "id")

		api.Update(util.Coll.Users, userA_ID, userA_Token, map[string]any{
			"activeWorkspace": workspaceID,
			"activeRole":      util.RoleAdmin,
		}).Expect().Status(http.StatusOK)

		api.Create(util.Coll.WorkspaceMembers, userA_Token, map[string]any{
			"user":      userB_ID,
			"workspace": privateWorkspaceID,
			"role":      util.RoleMember,
		}).Expect().Status(http.StatusForbidden)
	})

	t.Run("Security: Regular member cannot delete or rename workspace", func(t *testing.T) {
		api := api.T(t)
		api.Update(util.Coll.Users, userB_ID, userB_Token, map[string]any{
			"activeWorkspace": workspaceID,
			"activeRole":      util.RoleMember,
		}).Expect().Status(http.StatusOK)

		// A member already knows the workspace exists, so the refusal is
		// explained rather than hidden behind a 404.
		api.Update(util.Coll.Workspaces, workspaceID, userB_Token, map[string]any{
			"name": "Hacked Name",
		}).Expect().Status(http.StatusForbidden).
			JSON().Object().Value("data").Object().Value("role").Object().
			Value("code").String().IsEqual(util.Errors.NotWorkspaceAdmin.ErrorCode)

		api.Delete(util.Coll.Workspaces, workspaceID, userB_Token).
			Expect().Status(http.StatusForbidden)
	})

	t.Run("Security: User cannot elevate their own role to admin in a workspace they only have member access to", func(t *testing.T) {
		api := api.T(t)
		api.Update(util.Coll.Users, userB_ID, userB_Token, map[string]any{
			"activeWorkspace": workspaceID,
			"activeRole":      util.RoleAdmin,
		}).Expect().Status(http.StatusForbidden)
	})

	t.Run("Side Effect: Workspace deletion clears context for all members", func(t *testing.T) {
		api := api.T(t)
		api.Update(util.Coll.Users, userB_ID, userB_Token, map[string]any{
			"activeWorkspace": workspaceID,
			"activeRole":      util.RoleMember,
		}).Expect().Status(http.StatusOK)

		api.Delete(util.Coll.Workspaces, workspaceID, userA_Token).
			Expect().Status(http.StatusNoContent)

		res := api.Get(util.Coll.Users, userB_ID, userB_Token).
			Expect().Status(http.StatusOK)

		assert.Empty(t, testutils.ExtractString(res, "activeWorkspace"))
		assert.Empty(t, testutils.ExtractString(res, "activeRole"))
	})
}
