package tests

import (
	"net/http"
	"testing"

	"revoked/tests/testutils"
	"revoked/util"
)

// A viewer can only walk the DNS chain if the probe hands them the sharer's
// signing material and this server's root claim. Without them a signed share is
// indistinguishable from an unsigned one, so the client has nothing to warn on.
func TestPublicLinkProbeCarriesSignerAndServerClaim(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("CreateRandomUser: %v", err)
	}
	wsID := api.Get(util.Coll.Users, userID, token).Expect().Status(http.StatusOK).
		JSON().Object().Value(util.Fields.User.ActiveWorkspace).String().Raw()

	identityID, _ := newIdentity(t, baseURL, token, "sharer-id", userID, wsID)

	slug := "probe-claim-" + identityID[:6]
	extractID(t, baseURL, util.Coll.Links, token, map[string]any{
		util.Fields.Link.Slug:      slug,
		util.Fields.Link.Label:     "Signed share",
		util.Fields.Link.Identity:  identityID,
		util.Fields.Link.User:      userID,
		util.Fields.Link.Workspace: wsID,
	})

	probe := testutils.NewPBClient(t, baseURL).E.
		GET("/api/public/links/" + slug).Expect().
		Status(http.StatusOK).JSON().Object()

	sharer := probe.Value("sharer").Object()
	sharer.Value("identityId").String().IsEqual(identityID)
	sharer.Value("fingerprint").String().NotEmpty()
	sharer.Value("parentSignature").String().NotEmpty()
	sharer.Value("domainAtIssue").String().NotEmpty()

	server := probe.Value("server").Object()
	server.Value("domain").String().NotEmpty()
	server.Value("rootFingerprint").String().NotEmpty()

	// The probe is unauthenticated: it must never leak a private key.
	probe.NotContainsKey(util.Fields.Identity.PrivateKey)
}
