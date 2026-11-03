package tests

import (
	"net/http"
	"revoked/tests/testutils"
	"revoked/util"
	"testing"

	"github.com/google/uuid"
)

// A feature is what a person chose to see; a permission is what they may do.
// The catalogue is served so the app renders the server's list, the account's
// set is written through one checked route, an invite seeds it only on an
// account that never chose, and none of it ever widens access.
func TestFeatureCatalogueIsServed(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	body := api.E.GET("/api/features").Expect().Status(http.StatusOK).JSON().Object()

	features := body.Value("features").Array()
	features.Length().IsEqual(len(util.Features))
	for i, f := range util.Features {
		entry := features.Value(i).Object()
		entry.Value("key").String().IsEqual(f.Key)
		entry.Value("label").String().NotEmpty()
		entry.Value("description").String().NotEmpty()
		entry.Value("defaultOn").Boolean().IsEqual(f.DefaultOn)
		if f.Permission != "" {
			if _, known := util.PermissionByKey(f.Permission); !known {
				t.Errorf("feature %s depends on unknown permission %s", f.Key, f.Permission)
			}
		}
	}

	presets := body.Value("presets").Array()
	presets.Length().IsEqual(len(util.FeaturePresets))
	for i, p := range util.FeaturePresets {
		entry := presets.Value(i).Object()
		entry.Value("key").String().IsEqual(p.Key)
		entry.Value("label").String().NotEmpty()
		if _, unknown := util.ExpandPermissions(p.Permissions); len(unknown) > 0 {
			t.Errorf("preset %s grants unknown permissions %v", p.Key, unknown)
		}
		if _, unknown := util.NormalizeFeatures(p.Features); len(unknown) > 0 {
			t.Errorf("preset %s shows unknown features %v", p.Key, unknown)
		}
	}
}

func TestAccountFeaturesAreCheckedAgainstTheCatalogue(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed to create user: %v", err)
	}

	t.Run("signed out is refused", func(t *testing.T) {
		api := api.T(t)
		api.E.PUT("/api/account/features").
			WithJSON(map[string]any{"features": []string{util.FeatureSharing}}).
			Expect().Status(http.StatusUnauthorized)
	})

	t.Run("an unknown key is refused as a whole", func(t *testing.T) {
		api := api.T(t)
		api.E.PUT("/api/account/features").
			WithHeader("Authorization", token).
			WithJSON(map[string]any{"features": []string{util.FeatureSharing, "teleport"}}).
			Expect().Status(http.StatusBadRequest).JSON().Object().
			Value("code").String().IsEqual(util.Errors.UnknownFeature.ErrorCode)

		// Nothing was stored: the account still shows the defaults.
		api.Get(util.Coll.Users, userID, token).Expect().Status(http.StatusOK).
			JSON().Object().Value(util.Fields.User.Features).IsNull()
	})

	t.Run("a known set is stored in catalogue order", func(t *testing.T) {
		api := api.T(t)
		api.E.PUT("/api/account/features").
			WithHeader("Authorization", token).
			WithJSON(map[string]any{"features": []string{util.FeatureDeveloper, util.FeatureSharing, util.FeatureSharing}}).
			Expect().Status(http.StatusOK).JSON().Object().
			Value("features").Array().IsEqual([]string{util.FeatureSharing, util.FeatureDeveloper})

		api.Get(util.Coll.Users, userID, token).Expect().Status(http.StatusOK).
			JSON().Object().Value(util.Fields.User.Features).Array().
			IsEqual([]string{util.FeatureSharing, util.FeatureDeveloper})
	})

	t.Run("an empty set means the vault alone", func(t *testing.T) {
		api := api.T(t)
		api.E.PUT("/api/account/features").
			WithHeader("Authorization", token).
			WithJSON(map[string]any{"features": []string{}}).
			Expect().Status(http.StatusOK).JSON().Object().
			Value("features").Array().Length().IsEqual(0)
	})

	t.Run("the collection API cannot write it", func(t *testing.T) {
		api := api.T(t)
		api.Update(util.Coll.Users, userID, token, map[string]any{
			util.Fields.User.Features: []string{"teleport"},
		}).Expect().Status(http.StatusBadRequest)
	})
}

func TestInviteFeaturesSeedOnlyAFreshAccount(t *testing.T) {
	f := newInviteFixture(t)

	t.Run("an unknown feature on an invite is refused", func(t *testing.T) {
		f.api.T(t).Create(util.Coll.Invites, f.adminToken, map[string]any{
			util.Fields.Invite.Workspace:   f.workspaceID,
			util.Fields.Invite.Permissions: []string{util.PermVaultRead},
			util.Fields.Invite.Features:    []string{"teleport"},
		}).Expect().Status(http.StatusBadRequest).JSON().Object().
			Value("data").Object().Value(util.Fields.Invite.Features).Object().
			Value("code").String().IsEqual(util.Errors.UnknownFeature.ErrorCode)
	})

	token, created := f.createInvite(t, map[string]any{
		util.Fields.Invite.Label:       "Sharer",
		util.Fields.Invite.Permissions: []string{util.PermVaultRead, util.PermSharesRead},
		util.Fields.Invite.Features:    []string{util.FeatureSharing},
	})
	created.Value(util.Fields.Invite.Features).Array().IsEqual([]string{util.FeatureSharing})

	t.Run("the probe names the starting set", func(t *testing.T) {
		api := f.api.T(t)
		features := api.E.GET("/api/public/invites/" + token).
			Expect().Status(http.StatusOK).JSON().Object().
			Value("features").Array()
		features.Length().IsEqual(1)
		features.Value(0).Object().Value("key").String().IsEqual(util.FeatureSharing)
		features.Value(0).Object().Value("label").String().NotEmpty()
	})

	t.Run("an account that never chose takes the invite's set", func(t *testing.T) {
		api := f.api.T(t)
		freshID, freshToken, err := testutils.CreateRandomUser(f.baseURL)
		if err != nil {
			t.Fatalf("Failed to create invitee: %v", err)
		}
		api.E.POST("/api/public/invites/"+token).
			WithHeader("Authorization", freshToken).
			Expect().Status(http.StatusOK).JSON().Object().
			Value("features").Array().IsEqual([]string{util.FeatureSharing})

		api.Get(util.Coll.Users, freshID, freshToken).Expect().Status(http.StatusOK).
			JSON().Object().Value(util.Fields.User.Features).Array().
			IsEqual([]string{util.FeatureSharing})
	})

	t.Run("an account that chose keeps its own set", func(t *testing.T) {
		api := f.api.T(t)
		chosenID, chosenToken, err := testutils.CreateRandomUser(f.baseURL)
		if err != nil {
			t.Fatalf("Failed to create invitee: %v", err)
		}
		api.E.PUT("/api/account/features").
			WithHeader("Authorization", chosenToken).
			WithJSON(map[string]any{"features": []string{util.FeatureDeveloper}}).
			Expect().Status(http.StatusOK)

		api.E.POST("/api/public/invites/"+token).
			WithHeader("Authorization", chosenToken).
			Expect().Status(http.StatusOK).JSON().Object().
			Value("features").Array().IsEqual([]string{util.FeatureDeveloper})

		api.Get(util.Coll.Users, chosenID, chosenToken).Expect().Status(http.StatusOK).
			JSON().Object().Value(util.Fields.User.Features).Array().
			IsEqual([]string{util.FeatureDeveloper})
	})

	t.Run("an invite without a set leaves the choice to the person", func(t *testing.T) {
		api := f.api.T(t)
		plain, _ := f.createInvite(t, map[string]any{
			util.Fields.Invite.Permissions: []string{util.PermVaultRead},
		})
		api.E.GET("/api/public/invites/" + plain).
			Expect().Status(http.StatusOK).JSON().Object().
			Value("features").IsNull()

		freshID, freshToken, err := testutils.CreateRandomUser(f.baseURL)
		if err != nil {
			t.Fatalf("Failed to create invitee: %v", err)
		}
		api.E.POST("/api/public/invites/"+plain).
			WithHeader("Authorization", freshToken).
			Expect().Status(http.StatusOK)
		api.Get(util.Coll.Users, freshID, freshToken).Expect().Status(http.StatusOK).
			JSON().Object().Value(util.Fields.User.Features).IsNull()
	})
}

// A feature is never a boundary: a member who turned sharing on but holds no
// sharing permission is refused exactly as before.
func TestFeatureOnWithoutPermissionIsStillRefused(t *testing.T) {
	f := newInviteFixture(t)

	token, _ := f.createInvite(t, map[string]any{
		util.Fields.Invite.Permissions: []string{util.PermVaultRead},
		util.Fields.Invite.Features:    []string{util.FeatureSharing},
	})
	memberID, memberToken, err := testutils.CreateRandomUser(f.baseURL)
	if err != nil {
		t.Fatalf("Failed to create member: %v", err)
	}
	f.api.E.POST("/api/public/invites/"+token).
		WithHeader("Authorization", memberToken).
		Expect().Status(http.StatusOK)

	// The feature is on, as the member listing confirms.
	members := f.api.E.GET("/api/workspaces/"+f.workspaceID+"/members").
		WithHeader("Authorization", f.adminToken).
		Expect().Status(http.StatusOK).JSON().Object().Value("members").Array()
	seen := false
	for _, raw := range members.Iter() {
		entry := raw.Object()
		if entry.Value("user").String().Raw() != memberID {
			continue
		}
		seen = true
		entry.Value("features").Array().IsEqual([]string{util.FeatureSharing})
		entry.Value("permissions").Array().Length().IsEqual(1)
	}
	if !seen {
		t.Fatal("the invited member is missing from the listing")
	}

	status := f.api.Create(util.Coll.Links, memberToken, map[string]any{
		util.Fields.Link.Slug:      "ft" + uuid.New().String()[:8],
		util.Fields.Link.Label:     "Not allowed",
		util.Fields.Link.Status:    util.StatusActive,
		util.Fields.Link.User:      memberID,
		util.Fields.Link.Workspace: f.workspaceID,
	}).Expect().Raw().StatusCode
	if status != http.StatusForbidden && status != http.StatusBadRequest {
		t.Fatalf("a member without shares:manage created a link: status %d", status)
	}
}
