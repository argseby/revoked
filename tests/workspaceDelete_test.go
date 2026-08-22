package tests

import (
	"net/http"
	"revoked/cmd/revoked/server"
	"revoked/tests/testutils"
	"revoked/util"
	"testing"

	"github.com/google/uuid"
	"github.com/pocketbase/dbx"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Deleting a workspace has to take its contents with it. Every child holds a
// required workspace relation that does not cascade, so before the teardown a
// workspace could be deleted only while it was empty — the moment anyone used
// it, it became permanent.
func TestWorkspaceDelete(t *testing.T) {
	baseURL, app := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)
	userID, token, _ := testutils.CreateRandomUser(baseURL)

	ws := api.Create(util.Coll.Workspaces, token, map[string]any{
		"name": "Doomed",
		"slug": "ws-doomed-" + uuid.New().String()[:8],
	}).Expect().Status(http.StatusOK)
	wsID := testutils.ExtractString(ws, "id")

	api.Update(util.Coll.Users, userID, token, map[string]any{
		"activeWorkspace": wsID,
		"activeRole":      util.RoleAdmin,
	}).Expect().Status(http.StatusOK)

	rec := api.Create(util.Coll.Records, token, map[string]any{
		"key": "k1", "value": "v1", "label": "L1",
		"type": "text", "format": "default",
		"user": userID, "workspace": wsID,
	}).Expect().Status(http.StatusOK)
	recordID := testutils.ExtractString(rec, "id")

	kp := testutils.NewTestIdentity(t, "Doomed Identity")
	id := api.Create(util.Coll.Identities, token, map[string]any{
		"name": "Doomed Identity", "publicKey": kp.PublicKeyPem,
		"user": userID, "workspace": wsID,
	}).Expect().Status(http.StatusOK)
	fingerprint := testutils.ExtractString(id, "fingerprint")
	require.NotEmpty(t, fingerprint)

	api.Delete(util.Coll.Workspaces, wsID, token).Expect().Status(http.StatusNoContent)

	t.Run("the workspace and its contents are gone", func(t *testing.T) {
		_, err := app.FindRecordById(util.Coll.Workspaces, wsID)
		assert.Error(t, err, "workspace row should be gone")
		_, err = app.FindRecordById(util.Coll.Records, recordID)
		assert.Error(t, err, "its records should be gone")

		members, err := app.FindAllRecords(util.Coll.WorkspaceMembers,
			dbx.HashExp{util.Fields.WorkspaceMember.Workspace: wsID})
		require.NoError(t, err)
		assert.Empty(t, members, "its memberships should be gone")
	})

	t.Run("its identities leave a revocation tombstone", func(t *testing.T) {
		api := api.T(t)
		// Without this the certificates it issued go on asserting membership of
		// a workspace that no longer exists, with nothing left to contradict them.
		body, err := fetchStatusAssertion(t, api, fingerprint).Body()
		require.NoError(t, err)
		assert.Equal(t, server.IdentityStatusRevoked, body.Status)
		assert.Equal(t, util.RevocationDeleted, body.Reason)
	})

	t.Run("the deletion itself is audited", func(t *testing.T) {
		logs, err := app.FindAllRecords(util.Coll.AuditLogs,
			dbx.HashExp{util.Fields.AuditLog.RecordId: wsID, util.Fields.AuditLog.Action: "delete"})
		require.NoError(t, err)
		assert.Len(t, logs, 1, "a workspace delete must leave an audit row")
	})

	t.Run("the member is left without an active workspace", func(t *testing.T) {
		user, err := app.FindRecordById(util.Coll.Users, userID)
		require.NoError(t, err)
		assert.Empty(t, user.GetString(util.Fields.User.ActiveWorkspace))
	})
}

// Deletion is gated by the same permission that renames the workspace, so a
// member without it must not be able to end the workspace for everyone else.
func TestWorkspaceDeleteRequiresPermission(t *testing.T) {
	baseURL, app := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	adminID, adminToken, _ := testutils.CreateRandomUser(baseURL)
	memberID, memberToken, _ := testutils.CreateRandomUser(baseURL)

	ws := api.Create(util.Coll.Workspaces, adminToken, map[string]any{
		"name": "Shared",
		"slug": "ws-shared-" + uuid.New().String()[:8],
	}).Expect().Status(http.StatusOK)
	wsID := testutils.ExtractString(ws, "id")

	api.Update(util.Coll.Users, adminID, adminToken, map[string]any{
		"activeWorkspace": wsID, "activeRole": util.RoleAdmin,
	}).Expect().Status(http.StatusOK)

	readOnly, unknown := util.ExpandPermissions([]string{util.PermVaultRead})
	require.Empty(t, unknown)
	api.Create(util.Coll.WorkspaceMembers, adminToken, map[string]any{
		"user": memberID, "workspace": wsID,
		"role": util.RoleMember, "permissions": readOnly,
	}).Expect().Status(http.StatusOK)

	api.Update(util.Coll.Users, memberID, memberToken, map[string]any{
		"activeWorkspace": wsID, "activeRole": util.RoleMember,
	}).Expect().Status(http.StatusOK)

	resp := api.Delete(util.Coll.Workspaces, wsID, memberToken).Expect()
	assert.NotEqual(t, http.StatusNoContent, resp.Raw().StatusCode,
		"a member without the manage permission must not delete the workspace")

	_, err := app.FindRecordById(util.Coll.Workspaces, wsID)
	assert.NoError(t, err, "the workspace must survive a refused delete")
}

// The permission is what counts, not the derived role. `role` is set to admin
// only for members who may invite, so a member granted "manage workspace" and
// nothing else still holds workspaces:delete and must be able to use it.
func TestWorkspaceDeleteByNonAdminHolderOfThePermission(t *testing.T) {
	baseURL, app := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	ownerID, ownerToken, _ := testutils.CreateRandomUser(baseURL)
	managerID, managerToken, _ := testutils.CreateRandomUser(baseURL)

	ws := api.Create(util.Coll.Workspaces, ownerToken, map[string]any{
		"name": "Managed",
		"slug": "ws-managed-" + uuid.New().String()[:8],
	}).Expect().Status(http.StatusOK)
	wsID := testutils.ExtractString(ws, "id")

	api.Update(util.Coll.Users, ownerID, ownerToken, map[string]any{
		"activeWorkspace": wsID, "activeRole": util.RoleAdmin,
	}).Expect().Status(http.StatusOK)

	manage, unknown := util.ExpandPermissions([]string{util.PermSettingsManage})
	require.Empty(t, unknown)
	member := api.Create(util.Coll.WorkspaceMembers, ownerToken, map[string]any{
		"user": managerID, "workspace": wsID, "permissions": manage,
	}).Expect().Status(http.StatusOK)

	// Derived, not chosen: managing settings does not make someone an admin.
	member.JSON().Object().Value("role").String().IsEqual(util.RoleMember)

	api.Update(util.Coll.Users, managerID, managerToken, map[string]any{
		"activeWorkspace": wsID, "activeRole": util.RoleMember,
	}).Expect().Status(http.StatusOK)

	api.Delete(util.Coll.Workspaces, wsID, managerToken).
		Expect().Status(http.StatusNoContent)

	_, err := app.FindRecordById(util.Coll.Workspaces, wsID)
	assert.Error(t, err, "the workspace should be gone")
}
