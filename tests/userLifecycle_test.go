package tests

import (
	"fmt"
	"net/http"
	"revoked/tests/testutils"
	"revoked/util"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestUserLifecycle_Refactored(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	var token, userID, signupWorkspaceID string

	email := "lifecycle@test.com"
	device := testutils.NewPasskeyDevice(baseURL)

	t.Run("create user and authenticate", func(t *testing.T) {
		api := api.T(t)
		session, err := device.Register(map[string]any{"email": email})
		if err != nil {
			t.Fatalf("register: %v", err)
		}
		userID, token = session.UserID, session.Token
		assert.NotEmpty(t, userID)
		assert.NotEmpty(t, token)

		// An account starts with no workspace: the client asks on first run
		// whether to create one or join one by invite.
		api.Get(util.Coll.Users, userID, token).Expect().Status(http.StatusOK).
			JSON().Object().Value(util.Fields.User.ActiveWorkspace).String().IsEmpty()
	})

	t.Run("create the first workspace and adopt it", func(t *testing.T) {
		api := api.T(t)
		res := api.Create(util.Coll.Workspaces, token, map[string]any{
			"name": "First",
			"slug": "ws-first",
		}).Expect().Status(http.StatusOK)

		signupWorkspaceID = testutils.ExtractString(res, "id")
		assert.NotEmpty(t, signupWorkspaceID)

		api.Update(util.Coll.Users, userID, token, map[string]any{
			"activeWorkspace": signupWorkspaceID,
			"activeRole":      util.RoleAdmin,
		}).Expect().Status(http.StatusOK)

		userRes := api.Get(util.Coll.Users, userID, token).
			Expect().Status(http.StatusOK).JSON().Object()
		userRes.Value(util.Fields.User.ActiveWorkspace).IsEqual(signupWorkspaceID)
		userRes.Value(util.Fields.User.ActiveRole).IsEqual(util.RoleAdmin)
	})

	// The first workspace was created above, so the cap is reached after
	// creating MaximumWorkspacesPerUser-1 more.
	for i := 1; i < util.MaximumWorkspacesPerUser; i++ {
		t.Run(fmt.Sprintf("create workspace %d", i), func(t *testing.T) {
			api := api.T(t)
			api.Create(util.Coll.Workspaces, token, map[string]any{
				"name": "Workspace",
				"slug": fmt.Sprintf("ws-extra-%d", i),
			}).Expect().Status(http.StatusOK)
		})
	}

	t.Run("reject one workspace past the cap", func(t *testing.T) {
		api := api.T(t)
		resp := api.Create(util.Coll.Workspaces, token, map[string]any{
			"name": "Over the cap",
			"slug": "ws-over-cap",
		}).Expect()

		testutils.AssertBadRequestErrors(t, resp, map[string]util.AppError{
			"user": util.Errors.WorkspaceLimitReached,
		})
	})

	t.Run("delete the first workspace and verify user context", func(t *testing.T) {
		api := api.T(t)
		api.Delete(util.Coll.Workspaces, signupWorkspaceID, token).
			Expect().Status(http.StatusNoContent)

		user := api.Get(util.Coll.Users, userID, token).
			Expect().Status(http.StatusOK).JSON().Object()

		user.Value(util.Fields.User.ActiveWorkspace).IsEqual("")
	})

	t.Run("delete user completely", func(t *testing.T) {
		api := api.T(t)
		api.Delete(util.Coll.Users, userID, token).
			Expect().Status(http.StatusNoContent)

		// Its passkey went with it.
		if _, err := device.SignIn(); err == nil {
			t.Fatal("a deleted account's passkey still signs in")
		}
	})
}
