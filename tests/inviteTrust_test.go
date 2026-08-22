package tests

import (
	"encoding/json"
	"net/http"
	"testing"
	"time"

	"revoked/cmd/revoked/server"
	"revoked/tests/testutils"
	"revoked/util"
)

// Accepting an invite hands an account to whoever is on the other end, so the
// probe has to carry what a recipient needs to walk the DNS chain — the same
// block links and requests already publish.
func TestInviteProbePublishesTheServerTrustBlock(t *testing.T) {
	f := newInviteFixture(t)
	token, _ := f.createInvite(t, map[string]any{
		util.Fields.Invite.Permissions: []string{util.ScopeRecordRead},
	})

	probe := f.api.E.GET("/api/public/invites/" + token).
		Expect().Status(http.StatusOK).JSON().Object()

	srv := probe.Value("server").Object()
	srv.Value("domain").String().IsEqual(testDomain)
	srv.Value("rootFingerprint").String().NotEmpty()
}

// The email is reported with what the server can actually back it up with:
// whose account it is, whether it even sits in this server's own domain, and
// the identity behind it — never a bare claim the reader has to take on faith.
func TestInviteProbeAttestsTheInviter(t *testing.T) {
	f := newInviteFixture(t)

	identityID, _ := newIdentity(t, f.baseURL, f.adminToken, "inviter-id", f.adminID, f.workspaceID)
	fingerprint := f.api.Get(util.Coll.Identities, identityID, f.adminToken).
		Expect().Status(http.StatusOK).JSON().Object().
		Value(util.Fields.Identity.Fingerprint).String().Raw()

	token, _ := f.createInvite(t, map[string]any{
		util.Fields.Invite.Permissions: []string{util.ScopeRecordRead},
	})

	probe := f.api.E.GET("/api/public/invites/" + token).
		Expect().Status(http.StatusOK).JSON().Object()

	inviter := probe.Value("inviter").Object()
	inviter.Value("email").String().NotEmpty()
	inviter.Value("serverDomain").String().IsEqual(testDomain)
	inviter.Value("canStillInvite").Boolean().IsTrue()

	// The harness registers accounts on random addresses, which are not in the
	// server's own domain — so the honest answer here is "no", and the probe
	// must say so rather than implying the server vouches for the address.
	inviter.Value("emailMatchesServer").Boolean().IsFalse()
	inviter.Value("emailDomain").String().NotEqual(testDomain)

	identity := inviter.Value("identity").Object()
	identity.Value("fingerprint").String().IsEqual(fingerprint)
	identity.Value("parentSignature").String().NotEmpty()
	identity.Value("status").String().IsEqual(util.StatusActive)

	// The stapled status verifies under the same root key that signed the
	// identity, so the recipient needs no extra round-trip and no extra trust.
	raw, err := json.Marshal(identity.Value("statusAssertion").Object().Raw())
	if err != nil {
		t.Fatalf("re-encoding the stapled assertion: %v", err)
	}
	var stapled server.IdentityStatusAssertion
	if err := json.Unmarshal(raw, &stapled); err != nil {
		t.Fatalf("decoding the stapled assertion: %v", err)
	}
	body, err := server.VerifyIdentityStatus(
		stapled, serverRootPublicKey(t, f.api), testDomain, fingerprint, time.Now())
	if err != nil {
		t.Fatalf("the invite's stapled assertion did not verify: %v", err)
	}
	if body.Status != server.IdentityStatusActive {
		t.Fatalf("stapled status = %q, want active", body.Status)
	}
}

// An invite delegates the inviter's authority; a token minted before they lost
// it must not outlive it, or removal leaves a working back door behind.
func TestInviteDiesWithTheInvitersAuthority(t *testing.T) {
	f := newInviteFixture(t)

	// A second admin does the inviting, so removing them cannot trip the
	// last-admin guard.
	inviterID, inviterToken, err := testutils.CreateRandomUser(f.baseURL)
	if err != nil {
		t.Fatalf("CreateRandomUser: %v", err)
	}
	// Members carry expanded scopes; holding members:add is what makes them an
	// administrator, since the role is derived from the permission set.
	inviterScopes, _ := util.ExpandPermissions([]string{util.PermMembersAdd, util.PermSharesRead})
	membership := f.api.Create(util.Coll.WorkspaceMembers, f.adminToken, map[string]any{
		util.Fields.WorkspaceMember.User:        inviterID,
		util.Fields.WorkspaceMember.Workspace:   f.workspaceID,
		util.Fields.WorkspaceMember.Permissions: inviterScopes,
	}).Expect().Status(http.StatusOK).JSON().Object().Value("id").String().Raw()

	f.api.Update(util.Coll.Users, inviterID, inviterToken, map[string]any{
		util.Fields.User.ActiveWorkspace: f.workspaceID,
		util.Fields.User.ActiveRole:      util.RoleAdmin,
	}).Expect().Status(http.StatusOK)

	invite := f.api.Create(util.Coll.Invites, inviterToken, map[string]any{
		util.Fields.Invite.Workspace:   f.workspaceID,
		util.Fields.Invite.Permissions: []string{util.PermSharesRead},
	}).Expect().Status(http.StatusOK)
	token := invite.Header("X-Invite-Token").Raw()
	if token == "" {
		t.Fatal("invite response carried no token")
	}

	f.api.E.GET("/api/public/invites/" + token).
		Expect().Status(http.StatusOK).JSON().Object().
		Value("inviter").Object().Value("canStillInvite").Boolean().IsTrue()

	f.api.Delete(util.Coll.WorkspaceMembers, membership, f.adminToken).
		Expect().Status(http.StatusNoContent)

	// The probe must say so before anyone decides...
	f.api.E.GET("/api/public/invites/" + token).
		Expect().Status(http.StatusOK).JSON().Object().
		Value("inviter").Object().Value("canStillInvite").Boolean().IsFalse()

	// ...and accepting must actually be refused, not merely warned about.
	_, joinerToken, err := testutils.CreateRandomUser(f.baseURL)
	if err != nil {
		t.Fatalf("CreateRandomUser: %v", err)
	}
	refused := f.api.E.POST("/api/public/invites/"+token).
		WithHeader("Authorization", joinerToken).
		Expect().Status(http.StatusForbidden).JSON().Object()
	refused.Value("code").String().IsEqual(util.Errors.InviteInviterLostAccess.ErrorCode)
}
