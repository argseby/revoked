package tests

import (
	"net/http"
	"testing"

	"revoked/tests/testutils"
	"revoked/util"
)

// The client pins a primary identity with a single PATCH and relies on the
// server to demote the others. It used to flip the flag in memory only, so the
// pin vanished on the next load.
func TestSetPrimaryIdentityDemotesTheOthers(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("CreateRandomUser: %v", err)
	}
	wsID := api.Get(util.Coll.Users, userID, token).Expect().Status(http.StatusOK).
		JSON().Object().Value(util.Fields.User.ActiveWorkspace).String().Raw()

	firstID, _ := newIdentity(t, baseURL, token, "primary-a", userID, wsID)
	secondID, _ := newIdentity(t, baseURL, token, "primary-b", userID, wsID)

	pin := func(id string) {
		t.Helper()
		api.Update(util.Coll.Identities, id, token, map[string]any{
			util.Fields.Identity.IsPrimary: true,
		}).Expect().Status(http.StatusOK)
	}
	isPrimary := func(id string) bool {
		t.Helper()
		return api.Get(util.Coll.Identities, id, token).Expect().Status(http.StatusOK).
			JSON().Object().Value(util.Fields.Identity.IsPrimary).Boolean().Raw()
	}

	pin(firstID)
	if !isPrimary(firstID) {
		t.Fatal("the pinned identity did not persist isPrimary")
	}

	pin(secondID)
	if !isPrimary(secondID) {
		t.Fatal("the newly pinned identity did not persist isPrimary")
	}
	if isPrimary(firstID) {
		t.Fatal("the previously pinned identity was not demoted")
	}
}
