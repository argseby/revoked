package tests

import (
	"net/http"

	"github.com/pocketbase/dbx"
	"revoked/tests/testutils"
	"revoked/util"
	"testing"

	"github.com/google/uuid"
)

// activeWorkspaceOf reads the workspace a freshly provisioned account adopted.
func activeWorkspaceOf(t *testing.T, api *testutils.PBClient, userID, token string) string {
	t.Helper()
	return api.Get(util.Coll.Users, userID, token).Expect().Status(http.StatusOK).
		JSON().Object().Value(util.Fields.User.ActiveWorkspace).String().Raw()
}

// seedShare gives the account a record and an active public link exposing it,
// returning the link's slug.
func seedShare(t *testing.T, baseURL, token, userID, workspaceID string) string {
	t.Helper()
	recordID := extractID(t, baseURL, util.Coll.Records, token, map[string]any{
		util.Fields.Record.Key:       "api-key",
		util.Fields.Record.Value:     "sk-live-do-not-outlive-me",
		util.Fields.Record.Label:     "API key",
		util.Fields.Record.Type:      "text",
		util.Fields.Record.Format:    "default",
		util.Fields.Record.User:      userID,
		util.Fields.Record.Workspace: workspaceID,
	})

	identityID, _ := newIdentity(t, baseURL, token, "purge-id", userID, workspaceID)

	slug := "purge-" + uuid.New().String()[:8]
	extractID(t, baseURL, util.Coll.Links, token, map[string]any{
		util.Fields.Link.Slug:      slug,
		util.Fields.Link.Label:     "Live grant",
		util.Fields.Link.Status:    util.StatusActive,
		util.Fields.Link.User:      userID,
		util.Fields.Link.Workspace: workspaceID,
		util.Fields.Link.Identity:  identityID,
		util.Fields.Link.Records:   []string{recordID},
	})
	return slug
}

func TestDeleteAccountRequiresAuthentication(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	api.E.DELETE("/api/account").Expect().Status(http.StatusUnauthorized)
}

// The property the whole feature exists for: no relation to users cascades, so
// a purge that only dropped the users row would leave this slug resolving with
// nobody left who could revoke it.
func TestDeleteAccountStopsItsLiveLinks(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed to create user: %v", err)
	}
	workspaceID := activeWorkspaceOf(t, api, userID, token)
	slug := seedShare(t, baseURL, token, userID, workspaceID)

	api.E.GET("/api/public/links/" + slug).Expect().Status(http.StatusOK)

	api.E.DELETE("/api/account").WithHeader("Authorization", token).
		Expect().Status(http.StatusNoContent)

	api.E.GET("/api/public/links/" + slug).Expect().Status(http.StatusNotFound)
	api.E.GET("/s/" + slug).Expect().Status(http.StatusNotFound)
}

func TestDeleteAccountRemovesItsWorkspaceAndContents(t *testing.T) {
	baseURL, app := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed to create user: %v", err)
	}
	workspaceID := activeWorkspaceOf(t, api, userID, token)
	seedShare(t, baseURL, token, userID, workspaceID)

	api.E.DELETE("/api/account").WithHeader("Authorization", token).
		Expect().Status(http.StatusNoContent)

	if _, err := app.FindRecordById(util.Coll.Users, userID); err == nil {
		t.Fatal("the account survived its own deletion")
	}
	if _, err := app.FindRecordById(util.Coll.Workspaces, workspaceID); err == nil {
		t.Fatal("the sole-owned workspace outlived the account")
	}

	// Scoped to this account's own workspace: the suite shares one server, so
	// other tests' rows live in these collections too.
	//
	// Audit snapshots are secret-redacted, but a surviving row would still pin
	// the account's IP and user agent to everything it did.
	for _, collection := range []string{
		util.Coll.Records, util.Coll.Links, util.Coll.Identities,
		util.Coll.WorkspaceMembers, util.Coll.AuditLogs,
	} {
		left, err := app.FindAllRecords(collection, dbx.HashExp{util.FieldWorkspace: workspaceID})
		if err != nil {
			t.Fatalf("Failed to list %s: %v", collection, err)
		}
		if len(left) != 0 {
			t.Fatalf("%s kept %d row(s) belonging to the deleted account", collection, len(left))
		}
	}

	// The signup row carries no workspace at all, only the account it created.
	orphaned, err := app.FindAllRecords(util.Coll.AuditLogs,
		dbx.HashExp{util.Fields.AuditLog.RecordId: userID})
	if err != nil {
		t.Fatalf("Failed to list %s: %v", util.Coll.AuditLogs, err)
	}
	if len(orphaned) != 0 {
		t.Fatalf("auditLogs kept %d row(s) about the deleted account", len(orphaned))
	}

	api.E.GET("/api/collections/"+util.Coll.Records+"/records").
		WithHeader("Authorization", token).
		Expect().Status(http.StatusOK).
		JSON().Object().Value("items").Array().IsEmpty()
}

func TestDeleteAccountRefusedWhileLastAdminOfSharedWorkspace(t *testing.T) {
	f := newInviteFixture(t)

	inviteToken, _ := f.createInvite(t, map[string]any{
		util.Fields.Invite.Permissions: []string{util.PermSharesRead},
	})
	_, inviteeToken, err := testutils.CreateRandomUser(f.baseURL)
	if err != nil {
		t.Fatalf("Failed to create invitee: %v", err)
	}
	f.api.E.POST("/api/public/invites/"+inviteToken).
		WithHeader("Authorization", inviteeToken).
		Expect().Status(http.StatusOK)

	resp := f.api.E.DELETE("/api/account").WithHeader("Authorization", f.adminToken).
		Expect().Status(http.StatusConflict)
	resp.JSON().Object().Value("code").
		IsEqual(util.Errors.LastAdminProtected.ErrorCode)

	// Refusing must leave the account entirely intact, not half-purged.
	f.api.Get(util.Coll.Users, f.adminID, f.adminToken).Expect().Status(http.StatusOK)
}

// A member who is not the last admin leaves rather than taking the shared
// workspace with them: their grants die, the workspace and its content do not.
func TestDeleteAccountLeavesSharedWorkspaceStanding(t *testing.T) {
	f := newInviteFixture(t)
	_, app := testutils.SetupTestApp(t)

	inviteToken, _ := f.createInvite(t, map[string]any{
		util.Fields.Invite.Permissions: []string{
			util.PermVaultWrite, util.PermSharesManage, util.PermIdentitiesManage,
		},
	})
	inviteeID, inviteeToken, err := testutils.CreateRandomUser(f.baseURL)
	if err != nil {
		t.Fatalf("Failed to create invitee: %v", err)
	}
	f.api.E.POST("/api/public/invites/"+inviteToken).
		WithHeader("Authorization", inviteeToken).
		Expect().Status(http.StatusOK)

	// A create binds to the caller's active workspace and refuses anything
	// else, so the invitee has to switch into the shared one first.
	f.api.Update(util.Coll.Users, inviteeID, inviteeToken, map[string]any{
		util.Fields.User.ActiveWorkspace: f.workspaceID,
		util.Fields.User.ActiveRole:      util.RoleMember,
	}).Expect().Status(http.StatusOK)

	slug := seedShare(t, f.baseURL, inviteeToken, inviteeID, f.workspaceID)
	f.api.E.GET("/api/public/links/" + slug).Expect().Status(http.StatusOK)

	f.api.E.DELETE("/api/account").WithHeader("Authorization", inviteeToken).
		Expect().Status(http.StatusNoContent)

	f.api.E.GET("/api/public/links/" + slug).Expect().Status(http.StatusNotFound)
	f.api.Get(util.Coll.Workspaces, f.workspaceID, f.adminToken).
		Expect().Status(http.StatusOK)
	f.api.Get(util.Coll.Users, f.adminID, f.adminToken).Expect().Status(http.StatusOK)

	// The workspace's content stays, under someone who is still in it — a row
	// left pointing at the deleted account would refuse the deletion outright.
	kept, err := app.FindAllRecords(util.Coll.Records, dbx.HashExp{util.FieldWorkspace: f.workspaceID})
	if err != nil {
		t.Fatalf("Failed to list records: %v", err)
	}
	if len(kept) != 1 {
		t.Fatalf("expected the shared record to survive, found %d", len(kept))
	}
	if owner := kept[0].GetString(util.FieldUser); owner != f.adminID {
		t.Fatalf("shared record went to %q, wanted the remaining admin %q", owner, f.adminID)
	}
}
