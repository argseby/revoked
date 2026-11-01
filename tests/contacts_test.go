package tests

import (
	"net/http"
	"testing"

	"revoked/tests/testutils"
	"revoked/util"
)

// workspaceOf returns the caller's active workspace, read from a refreshed
// token: the signup provisions the workspace after issuing the first one.
func workspaceOf(t *testing.T, baseURL, token string) (string, string) {
	t.Helper()
	api := testutils.NewPBClient(t, baseURL)
	refreshed := api.AuthRefresh(util.Coll.Users, token).Expect().Status(http.StatusOK)
	return refreshed.JSON().Object().Value("record").Object().
			Value(util.Fields.User.ActiveWorkspace).String().Raw(),
		testutils.ExtractString(refreshed, "token")
}

func TestContactsBelongToTheirWorkspace(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	_, ownerToken, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed to create user: %v", err)
	}
	ownerWorkspace, ownerToken := workspaceOf(t, baseURL, ownerToken)

	_, strangerToken, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed to create user: %v", err)
	}
	_, strangerToken = workspaceOf(t, baseURL, strangerToken)

	id := extractID(t, baseURL, util.Coll.Contacts, ownerToken, map[string]any{
		util.Fields.Contact.Workspace: ownerWorkspace,
		util.Fields.Contact.Name:      "Ada Lovelace",
		util.Fields.Contact.Email:     "ada@example.com",
	})

	t.Run("a new contact is unverified, whatever it says", func(t *testing.T) {
		api := api.T(t)
		api.Get(util.Coll.Contacts, id, ownerToken).Expect().Status(http.StatusOK).
			JSON().Object().Value(util.Fields.Contact.TrustState).
			String().IsEqual(util.ContactUnverified)
	})

	t.Run("another workspace can neither see nor touch it", func(t *testing.T) {
		api := api.T(t)
		api.List(util.Coll.Contacts, strangerToken).Expect().Status(http.StatusOK).
			JSON().Object().Value("items").Array().Length().IsEqual(0)
		api.Get(util.Coll.Contacts, id, strangerToken).Expect().Status(http.StatusNotFound)
		api.Update(util.Coll.Contacts, id, strangerToken, map[string]any{
			util.Fields.Contact.Name: "hijacked",
		}).Expect().Status(http.StatusNotFound)
		api.Delete(util.Coll.Contacts, id, strangerToken).Expect().Status(http.StatusNotFound)
	})

	t.Run("a contact reaching nobody is refused", func(t *testing.T) {
		api := api.T(t)
		api.Create(util.Coll.Contacts, ownerToken, map[string]any{
			util.Fields.Contact.Workspace: ownerWorkspace,
			util.Fields.Contact.Name:      "Nobody",
		}).Expect().Status(http.StatusBadRequest)
	})

}

// A member who could mark a contact verified could dress an address they
// control up as a proven peer, and a co-member reading the list would send the
// vault to it. The server owns that verdict.
func TestContactTrustIsNotTheClientsToClaim(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	_, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed to create user: %v", err)
	}
	workspace, token := workspaceOf(t, baseURL, token)

	for _, field := range []string{
		util.Fields.Contact.TrustState,
		util.Fields.Contact.VerifiedAt,
		util.Fields.Contact.PeerFingerprint,
	} {
		t.Run("create refuses "+field, func(t *testing.T) {
			api := api.T(t)
			body := map[string]any{
				util.Fields.Contact.Workspace:  workspace,
				util.Fields.Contact.Name:       "Claimed peer",
				util.Fields.Contact.PeerDomain: "peer.test",
			}
			switch field {
			case util.Fields.Contact.TrustState:
				body[field] = util.ContactVerified
			case util.Fields.Contact.VerifiedAt:
				body[field] = "2026-01-01 00:00:00.000Z"
			default:
				body[field] = "cd"
			}
			api.Create(util.Coll.Contacts, token, body).
				Expect().Status(http.StatusBadRequest)
		})
	}

	t.Run("update refuses it too", func(t *testing.T) {
		api := api.T(t)
		id := extractID(t, baseURL, util.Coll.Contacts, token, map[string]any{
			util.Fields.Contact.Workspace:  workspace,
			util.Fields.Contact.Name:       "Grace Hopper",
			util.Fields.Contact.PeerDomain: "peer.test",
		})
		api.Update(util.Coll.Contacts, id, token, map[string]any{
			util.Fields.Contact.TrustState: util.ContactVerified,
		}).Expect().Status(http.StatusBadRequest)
		api.Get(util.Coll.Contacts, id, token).Expect().Status(http.StatusOK).
			JSON().Object().Value(util.Fields.Contact.TrustState).
			String().IsEqual(util.ContactUnverified)
	})
}
