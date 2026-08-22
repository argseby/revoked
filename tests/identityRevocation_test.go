package tests

import (
	"net/http"
	"testing"

	"revoked/tests/testutils"
	"revoked/util"

	"github.com/google/uuid"
)

// revokeIdentity withdraws an identity through the record API, the same way the
// owner's client does.
func revokeIdentity(t *testing.T, api *testutils.PBClient, id, token, reason string) {
	t.Helper()
	body := map[string]any{util.Fields.Identity.Status: util.StatusRevoked}
	if reason != "" {
		body[util.Fields.Identity.RevokedReason] = reason
	}
	api.Update(util.Coll.Identities, id, token, body).Expect().Status(http.StatusOK)
}

func identityStatus(t *testing.T, api *testutils.PBClient, id, token string) string {
	t.Helper()
	return api.Get(util.Coll.Identities, id, token).Expect().Status(http.StatusOK).
		JSON().Object().Value(util.Fields.Identity.Status).String().Raw()
}

// A new identity is born active, and the client cannot talk it out of that by
// submitting a status of its own.
func TestNewIdentityIsActiveAndCannotBeBornRevoked(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("CreateRandomUser: %v", err)
	}
	wsID := api.Get(util.Coll.Users, userID, token).Expect().Status(http.StatusOK).
		JSON().Object().Value(util.Fields.User.ActiveWorkspace).String().Raw()

	kp := testutils.NewTestIdentity(t, "born-active")
	created := api.Create(util.Coll.Identities, token, map[string]any{
		util.Fields.Identity.Name:          "born-active",
		util.Fields.Identity.PublicKey:     kp.PublicKeyPem,
		util.Fields.Identity.User:          userID,
		util.Fields.Identity.Workspace:     wsID,
		util.Fields.Identity.Status:        util.StatusRevoked,
		util.Fields.Identity.RevokedReason: util.RevocationKeyCompromise,
	}).Expect().Status(http.StatusOK).JSON().Object()

	created.Value(util.Fields.Identity.Status).String().IsEqual(util.StatusActive)
	created.Value(util.Fields.Identity.RevokedReason).String().IsEqual("")
}

// Revocation is one-way. A caller who could flip the status back would be able
// to un-publish a statement that verifiers have already acted on.
func TestRevokedIdentityCannotBeReinstated(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("CreateRandomUser: %v", err)
	}
	wsID := api.Get(util.Coll.Users, userID, token).Expect().Status(http.StatusOK).
		JSON().Object().Value(util.Fields.User.ActiveWorkspace).String().Raw()

	identityID, _ := newIdentity(t, baseURL, token, "one-way", userID, wsID)
	revokeIdentity(t, api, identityID, token, util.RevocationKeyCompromise)

	if got := identityStatus(t, api, identityID, token); got != util.StatusRevoked {
		t.Fatalf("identity did not revoke: %q", got)
	}

	api.Update(util.Coll.Identities, identityID, token, map[string]any{
		util.Fields.Identity.Status: util.StatusActive,
	}).Expect().Status(http.StatusOK)

	if got := identityStatus(t, api, identityID, token); got != util.StatusRevoked {
		t.Fatalf("a revoked identity was reinstated: %q", got)
	}

	// The reason is pinned too, so the record of why cannot be rewritten later.
	reason := api.Get(util.Coll.Identities, identityID, token).Expect().Status(http.StatusOK).
		JSON().Object().Value(util.Fields.Identity.RevokedReason).String().Raw()
	if reason != util.RevocationKeyCompromise {
		t.Fatalf("revocation reason was overwritten: %q", reason)
	}
}

// The scenario the whole feature exists for: someone leaves the workspace, and
// the certificate asserting they belong to it stops being honoured.
func TestRemovingAMemberRevokesTheirWorkspaceIdentities(t *testing.T) {
	baseURL, app := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	adminID, adminToken, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("CreateRandomUser: %v", err)
	}
	memberID, memberToken, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("CreateRandomUser: %v", err)
	}

	// Captured before any workspace switching: an identity here must survive,
	// because revocation is scoped to the membership that ended, not the person.
	personalWS := api.Get(util.Coll.Users, memberID, memberToken).Expect().Status(http.StatusOK).
		JSON().Object().Value(util.Fields.User.ActiveWorkspace).String().Raw()
	outsideID, _ := newIdentity(t, baseURL, memberToken, "at-home", memberID, personalWS)

	ws := api.Create(util.Coll.Workspaces, adminToken, map[string]any{
		"name": "BMW",
		"slug": "ws-bmw-" + uuid.New().String()[:8],
	}).Expect().Status(http.StatusOK)
	wsID := testutils.ExtractString(ws, "id")
	if wsID == personalWS {
		t.Fatal("the shared workspace and the personal one must differ")
	}

	api.Update(util.Coll.Users, adminID, adminToken, map[string]any{
		util.Fields.User.ActiveWorkspace: wsID,
		util.Fields.User.ActiveRole:      util.RoleAdmin,
	}).Expect().Status(http.StatusOK)

	membership := api.Create(util.Coll.WorkspaceMembers, adminToken, map[string]any{
		util.Fields.WorkspaceMember.User:      memberID,
		util.Fields.WorkspaceMember.Workspace: wsID,
		util.Fields.WorkspaceMember.Role:      util.RoleMember,
	}).Expect().Status(http.StatusOK)
	membershipID := testutils.ExtractString(membership, "id")

	api.Update(util.Coll.Users, memberID, memberToken, map[string]any{
		util.Fields.User.ActiveWorkspace: wsID,
		util.Fields.User.ActiveRole:      util.RoleMember,
	}).Expect().Status(http.StatusOK)

	insideID, _ := newIdentity(t, baseURL, memberToken, "at-bmw", memberID, wsID)

	api.Delete(util.Coll.WorkspaceMembers, membershipID, adminToken).
		Expect().Status(http.StatusNoContent)

	// Read through the app: losing membership also removes the read rule that
	// would let the departing member fetch the record over the API.
	statusOf := func(id string) string {
		t.Helper()
		rec, err := app.FindRecordById(util.Coll.Identities, id)
		if err != nil || rec == nil {
			t.Fatalf("identity %s vanished: %v", id, err)
		}
		return rec.GetString(util.Fields.Identity.Status)
	}

	if got := statusOf(insideID); got != util.StatusRevoked {
		t.Fatalf("the departing member's workspace identity is still %q", got)
	}
	if got := statusOf(outsideID); got != util.StatusActive {
		t.Fatalf("an identity in an unrelated workspace was revoked: %q", got)
	}
}

// Holding the private key is not the same as still being vouched for: the
// signature verifies and the submission is still refused.
func TestRevokedIdentityCannotCompleteAHandshake(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("CreateRandomUser: %v", err)
	}
	wsID := api.Get(util.Coll.Users, userID, token).Expect().Status(http.StatusOK).
		JSON().Object().Value(util.Fields.User.ActiveWorkspace).String().Raw()

	requesterID, _ := newIdentity(t, baseURL, token, "rev-requester", userID, wsID)
	responderID, responderKP := newIdentity(t, baseURL, token, "rev-responder", userID, wsID)

	slug, _ := setupRequest(t, baseURL, token, userID, wsID, requesterID, map[string]any{
		util.Fields.Request.RequireHandshake: true,
	})

	pub := testutils.NewPBClient(t, baseURL)

	nonce := pub.E.GET("/api/challenges/request/"+slug).
		WithQuery("identityId", responderID).
		Expect().Status(http.StatusOK).
		JSON().Object().Value("nonce").String().Raw()

	first := pub.E.POST("/api/public/requests/" + slug).WithJSON(map[string]any{
		"identityId":         responderID,
		"challengeNonce":     nonce,
		"challengeSignature": responderKP.SignChallenge(t, nonce),
		"data":               map[string]any{"before": true},
	}).Expect().Status(http.StatusOK)

	handshakeToken := first.Header("X-Handshake-Token").Raw()
	if handshakeToken == "" {
		t.Fatal("expected a handshake token before revocation")
	}

	revokeIdentity(t, api, responderID, token, util.RevocationKeyCompromise)

	// The token issued before revocation must stop working too, or revoking
	// would only lock out identities that had never been used.
	stale := pub.E.POST("/api/public/requests/" + slug).WithJSON(map[string]any{
		"identityId":     responderID,
		"handshakeToken": handshakeToken,
		"data":           map[string]any{"after": true},
	}).Expect().Status(http.StatusForbidden).JSON().Object()
	stale.Value("code").String().IsEqual(util.Errors.IdentityRevoked.ErrorCode)

	fresh := pub.E.GET("/api/challenges/request/"+slug).
		WithQuery("identityId", responderID).
		Expect().Status(http.StatusOK).
		JSON().Object().Value("nonce").String().Raw()

	resigned := pub.E.POST("/api/public/requests/" + slug).WithJSON(map[string]any{
		"identityId":         responderID,
		"challengeNonce":     fresh,
		"challengeSignature": responderKP.SignChallenge(t, fresh),
		"data":               map[string]any{"after": true},
	}).Expect().Status(http.StatusForbidden).JSON().Object()
	resigned.Value("code").String().IsEqual(util.Errors.IdentityRevoked.ErrorCode)
}

// A revoked identity may still be read for grants it already signed, but it may
// not sign a new one.
func TestRevokedIdentityCannotBeAttachedToANewGrant(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("CreateRandomUser: %v", err)
	}
	wsID := api.Get(util.Coll.Users, userID, token).Expect().Status(http.StatusOK).
		JSON().Object().Value(util.Fields.User.ActiveWorkspace).String().Raw()

	identityID, _ := newIdentity(t, baseURL, token, "no-new-grants", userID, wsID)
	revokeIdentity(t, api, identityID, token, util.RevocationManual)

	api.Create(util.Coll.Links, token, map[string]any{
		util.Fields.Link.Slug:      "lk-" + uuid.New().String()[:8],
		util.Fields.Link.Status:    util.StatusActive,
		util.Fields.Link.User:      userID,
		util.Fields.Link.Workspace: wsID,
		util.Fields.Link.Identity:  identityID,
	}).Expect().Status(http.StatusForbidden)
}

// Deleting an identity must leave a tombstone, so a fingerprint whose row is
// gone still resolves to a definite answer instead of silence.
func TestDeletedIdentityLeavesARevocationTombstone(t *testing.T) {
	baseURL, app := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("CreateRandomUser: %v", err)
	}
	wsID := api.Get(util.Coll.Users, userID, token).Expect().Status(http.StatusOK).
		JSON().Object().Value(util.Fields.User.ActiveWorkspace).String().Raw()

	identityID, _ := newIdentity(t, baseURL, token, "to-be-deleted", userID, wsID)
	fingerprint := api.Get(util.Coll.Identities, identityID, token).Expect().Status(http.StatusOK).
		JSON().Object().Value(util.Fields.Identity.Fingerprint).String().Raw()

	api.Delete(util.Coll.Identities, identityID, token).Expect().Status(http.StatusNoContent)

	tombstone, err := app.FindFirstRecordByFilter(
		util.Coll.IdentityRevocations,
		util.Fields.IdentityRevocation.Fingerprint+" = {:fp}",
		map[string]any{"fp": fingerprint},
	)
	if err != nil || tombstone == nil {
		t.Fatalf("no tombstone was written for a deleted identity: %v", err)
	}
	if got := tombstone.GetString(util.Fields.IdentityRevocation.Reason); got != util.RevocationDeleted {
		t.Fatalf("tombstone reason = %q, want %q", got, util.RevocationDeleted)
	}
}
