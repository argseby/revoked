package tests

import (
	"net/http"
	"revoked/tests/testutils"
	"revoked/util"
	"testing"
	"time"

	"github.com/google/uuid"
)

// extractID posts a create payload and returns the "id" of the resulting record.
func extractID(t *testing.T, baseURL, path, token string, payload map[string]any) string {
	t.Helper()
	api := testutils.NewPBClient(t, baseURL)
	resp := api.Create(path, token, payload).Expect().Status(http.StatusOK).JSON().Object()
	return resp.Value("id").String().Raw()
}

// newIdentity registers an identity from a fresh local keypair (the client
// submits only its public key) and returns its id plus the keypair for signing.
func newIdentity(t *testing.T, baseURL, token, name, user, workspace string) (string, *testutils.IdentityKeyPair) {
	t.Helper()
	kp := testutils.NewTestIdentity(t, name)
	id := extractID(t, baseURL, util.Coll.Identities, token, map[string]any{
		util.Fields.Identity.Name:      name,
		util.Fields.Identity.PublicKey: kp.PublicKeyPem,
		util.Fields.Identity.User:      user,
		util.Fields.Identity.Workspace: workspace,
	})
	return id, kp
}

func TestLinksPasswordProtection(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed to create random user: %v", err)
	}

	userObj := api.Get(util.Coll.Users, userID, token).Expect().Status(http.StatusOK).JSON().Object()
	wsID := userObj.Value(util.Fields.User.ActiveWorkspace).String().Raw()

	identityID, _ := newIdentity(t, baseURL, token, "lp-id", userID, wsID)

	slug := "pwdlink-" + uuid.New().String()[:6]
	linkID := extractID(t, baseURL, util.Coll.Links, token, map[string]any{
		util.Fields.Link.Slug:      slug,
		util.Fields.Link.Label:     "Locked Link",
		util.Fields.Link.Status:    util.StatusActive,
		util.Fields.Link.User:      userID,
		util.Fields.Link.Workspace: wsID,
		util.Fields.Link.Identity:  identityID,
		util.Fields.Link.Password:  "supersecret",
	})

	t.Run("Anonymous cannot scan links table", func(t *testing.T) {
		// The row-level rule filters out every record, so an anonymous list is
		// a 200 with no items rather than a refusal.
		api := testutils.NewPBClient(t, baseURL)
		body := api.E.GET("/api/collections/" + util.Coll.Links + "/records").
			Expect().Status(http.StatusOK).JSON().Object()
		body.Value("items").Array().Length().IsEqual(0)
	})

	t.Run("Anonymous cannot view link by id", func(t *testing.T) {
		api := testutils.NewPBClient(t, baseURL)
		api.E.GET("/api/collections/" + util.Coll.Links + "/records/" + linkID).
			Expect().Status(http.StatusNotFound)
	})

	t.Run("Public probe reveals only metadata", func(t *testing.T) {
		api := testutils.NewPBClient(t, baseURL)
		body := api.E.GET("/api/public/links/" + slug).
			Expect().Status(http.StatusOK).JSON().Object()
		body.Value("requiresPassword").Boolean().IsTrue()
		body.NotContainsKey("sections")
		body.NotContainsKey("records")
	})

	t.Run("Submitting without password is unauthorized", func(t *testing.T) {
		api := testutils.NewPBClient(t, baseURL)
		api.E.POST("/api/public/links/" + slug).WithJSON(map[string]any{}).
			Expect().Status(http.StatusUnauthorized)
	})

	t.Run("Submitting with wrong password is unauthorized", func(t *testing.T) {
		api := testutils.NewPBClient(t, baseURL)
		api.E.POST("/api/public/links/" + slug).WithJSON(map[string]any{
			"password": "wrong",
		}).Expect().Status(http.StatusUnauthorized)
	})

	t.Run("Correct password grants access", func(t *testing.T) {
		api := testutils.NewPBClient(t, baseURL)
		body := api.E.POST("/api/public/links/" + slug).WithJSON(map[string]any{
			"password": "supersecret",
		}).Expect().Status(http.StatusOK).JSON().Object()
		body.Value("slug").String().IsEqual(slug)
	})
}

func TestLinksAutoExpire(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed to create random user: %v", err)
	}
	wsID := api.Get(util.Coll.Users, userID, token).Expect().Status(http.StatusOK).
		JSON().Object().Value(util.Fields.User.ActiveWorkspace).String().Raw()

	identityID, _ := newIdentity(t, baseURL, token, "exp-id", userID, wsID)

	pastSlug := "exp-" + uuid.New().String()[:6]
	extractID(t, baseURL, util.Coll.Links, token, map[string]any{
		util.Fields.Link.Slug:      pastSlug,
		util.Fields.Link.Label:     "Expired",
		util.Fields.Link.Status:    util.StatusActive,
		util.Fields.Link.User:      userID,
		util.Fields.Link.Workspace: wsID,
		util.Fields.Link.Identity:  identityID,
		util.Fields.Link.ExpiresAt: time.Now().Add(-1 * time.Hour).UTC().Format("2006-01-02 15:04:05.000Z"),
	})

	t.Run("Expired link refuses public access", func(t *testing.T) {
		api := testutils.NewPBClient(t, baseURL)
		resp := api.E.POST("/api/public/links/" + pastSlug).WithJSON(map[string]any{}).
			Expect().Status(http.StatusGone).JSON().Object()
		resp.Value("code").String().IsEqual(util.Errors.LinkExpired.ErrorCode)
	})
}

func TestLinksMaxViews(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed to create random user: %v", err)
	}
	wsID := api.Get(util.Coll.Users, userID, token).Expect().Status(http.StatusOK).
		JSON().Object().Value(util.Fields.User.ActiveWorkspace).String().Raw()

	identityID, _ := newIdentity(t, baseURL, token, "mv-id", userID, wsID)

	slug := "mv-" + uuid.New().String()[:6]
	extractID(t, baseURL, util.Coll.Links, token, map[string]any{
		util.Fields.Link.Slug:      slug,
		util.Fields.Link.Label:     "Max views",
		util.Fields.Link.Status:    util.StatusActive,
		util.Fields.Link.User:      userID,
		util.Fields.Link.Workspace: wsID,
		util.Fields.Link.Identity:  identityID,
		util.Fields.Link.MaxViews:  2,
	})

	pub := testutils.NewPBClient(t, baseURL)

	pub.E.POST("/api/public/links/" + slug).WithJSON(map[string]any{}).
		Expect().Status(http.StatusOK)
	pub.E.POST("/api/public/links/" + slug).WithJSON(map[string]any{}).
		Expect().Status(http.StatusOK)
	pub.E.POST("/api/public/links/" + slug).WithJSON(map[string]any{}).
		Expect().Status(http.StatusGone)
}
