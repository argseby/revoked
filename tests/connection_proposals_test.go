package tests

import (
	"net/http"
	"strings"
	"testing"

	"revoked/cmd/revoked/services"
	"revoked/util"

	"github.com/gavv/httpexpect/v2"
)

func toolPost(f checkFixture, path, toolToken string) *httpexpect.Response {
	return f.api.E.POST(path).WithHeader(util.ConnectionHeader, toolToken).Expect()
}

func TestAToolFollowsItsRequestsAttestationsAndChecks(t *testing.T) {
	f := newCheckFixture(t)
	connID, toolToken := connectTool(t, f.api, f.issuerToken)
	setPermissions(f.api, connID, f.issuerToken, map[string]any{"allowRevoke": true}).Status(http.StatusOK)

	_, requestID := setupRequest(t, f.baseURL, f.issuerToken, f.issuerID, f.issuerWs, f.askerIdentity, map[string]any{
		util.Fields.Request.Connection: connID, util.Fields.Request.Ref: "tenant-1",
	})
	attestationID, offerToken := f.offer(t, map[string]any{
		util.Fields.Attestation.Connection: connID, util.Fields.Attestation.Ref: "member-42",
	})
	checkID, present := f.ask(t, map[string]any{
		"type": "membership", "claims": []string{"age_over_18"},
		"connection": connID, "ref": "door",
	})
	if resp := f.answer(t, present, f.presentFor(t, present, []string{"age_over_18"})); resp.StatusCode != http.StatusOK {
		t.Fatalf("answer refused: %d", resp.StatusCode)
	}
	// The owner's own rows stay theirs.
	setupRequest(t, f.baseURL, f.issuerToken, f.issuerID, f.issuerWs, f.askerIdentity, nil)
	f.offer(t, nil)

	t.Run("it sees where they stand and nothing they hold", func(t *testing.T) {
		body := toolGet(f.api, toolToken).Status(http.StatusOK)
		raw := body.Body().Raw()
		for _, secret := range []string{offerToken, present["nonce"].(string), "Ada Lovelace"} {
			if strings.Contains(raw, secret) {
				t.Fatalf("the tool's view holds %q: %s", secret, raw)
			}
		}
		seen := body.JSON().Object()

		requests := seen.Value("requests").Array()
		requests.Length().IsEqual(1)
		r := requests.Value(0).Object()
		r.Value("id").String().IsEqual(requestID)
		r.Value("ref").String().IsEqual("tenant-1")
		r.NotContainsKey("slug")

		attestations := seen.Value("attestations").Array()
		attestations.Length().IsEqual(1)
		a := attestations.Value(0).Object()
		a.Value("ref").String().IsEqual("member-42")
		a.Value("status").String().IsEqual(util.StatusOffered)
		a.NotContainsKey("claims")

		checks := seen.Value("checks").Array()
		checks.Length().IsEqual(1)
		c := checks.Value(0).Object()
		c.Value("id").String().IsEqual(checkID)
		c.Value("status").String().IsEqual(util.CheckStatusAnswered)
		v := c.Value("verdict").Object()
		v.Value("state").String().IsEqual(services.AttestationVerified)
		v.Value("claims").Object().IsEqual(map[string]any{"age_over_18": true})
	})

	t.Run("it closes a request and revokes an attestation", func(t *testing.T) {
		toolPost(f, "/api/connection/requests/"+requestID+"/close", toolToken).Status(http.StatusOK).
			JSON().Object().Value("status").String().IsEqual(util.StatusRevoked)
		toolPost(f, "/api/connection/attestations/"+attestationID+"/revoke", toolToken).Status(http.StatusOK).
			JSON().Object().Value("status").String().IsEqual(util.StatusRevoked)
		f.api.E.GET("/api/collections/"+util.Coll.Attestations+"/records/"+attestationID).
			WithHeader("Authorization", f.issuerToken).Expect().Status(http.StatusOK).
			JSON().Object().Value(util.Fields.Attestation.RevokedAt).String().NotEmpty()
	})

	t.Run("only its own, and only when allowed", func(t *testing.T) {
		_, mine := setupRequest(t, f.baseURL, f.issuerToken, f.issuerID, f.issuerWs, f.askerIdentity, nil)
		toolPost(f, "/api/connection/requests/"+mine+"/close", toolToken).Status(http.StatusNotFound)
		_, other := setupRequest(t, f.baseURL, f.issuerToken, f.issuerID, f.issuerWs, f.askerIdentity, map[string]any{
			util.Fields.Request.Connection: connID,
		})
		setPermissions(f.api, connID, f.issuerToken, map[string]any{"allowRevoke": false}).Status(http.StatusOK)
		toolPost(f, "/api/connection/requests/"+other+"/close", toolToken).Status(http.StatusForbidden)
	})
}

func TestARowNamesOnlyItsOwnersLiveConnection(t *testing.T) {
	f := newCheckFixture(t)
	connID, _ := connectTool(t, f.api, f.issuerToken)

	t.Run("someone else's connection is refused everywhere", func(t *testing.T) {
		f.api.Create(util.Coll.Requests, f.holderToken, map[string]any{
			util.Fields.Request.Slug: "rq-foreign-" + connID[:6], util.Fields.Request.Label: "x",
			util.Fields.Request.User: f.holderID, util.Fields.Request.Workspace: f.holderWs,
			util.Fields.Request.Identity:   f.identityID,
			util.Fields.Request.Connection: connID,
		}).Expect().Status(http.StatusBadRequest)
		resp := postJSON(t, f.baseURL+"/api/attestation-checks", f.holderToken, map[string]any{
			"type": "membership", "connection": connID,
		})
		if resp.StatusCode != http.StatusBadRequest {
			t.Fatalf("a foreign connection on a check answered %d", resp.StatusCode)
		}
	})

	t.Run("a request keeps the connection it was created with", func(t *testing.T) {
		_, id := setupRequest(t, f.baseURL, f.issuerToken, f.issuerID, f.issuerWs, f.askerIdentity, nil)
		f.api.Update(util.Coll.Requests, id, f.issuerToken, map[string]any{
			util.Fields.Request.Connection: connID,
		}).Expect().Status(http.StatusBadRequest)
		_, proposed := setupRequest(t, f.baseURL, f.issuerToken, f.issuerID, f.issuerWs, f.askerIdentity, map[string]any{
			util.Fields.Request.Connection: connID,
		})
		row := f.api.Get(util.Coll.Requests, proposed, f.issuerToken).Expect().Status(http.StatusOK).JSON().Object()
		row.Value(util.Fields.Request.ProposedBy).String().IsEqual(toolOrigin)
	})

	t.Run("pausing the tool holds its requests, and activating it releases them", func(t *testing.T) {
		_, id := setupRequest(t, f.baseURL, f.issuerToken, f.issuerID, f.issuerWs, f.askerIdentity, map[string]any{
			util.Fields.Request.Connection: connID,
		})
		status := func() string {
			return f.api.Get(util.Coll.Requests, id, f.issuerToken).Expect().Status(http.StatusOK).
				JSON().Object().Value(util.Fields.Request.Status).String().Raw()
		}
		f.api.E.POST("/api/connections/"+connID+"/pause").WithHeader("Authorization", f.issuerToken).
			Expect().Status(http.StatusOK)
		if got := status(); got != util.StatusPaused {
			t.Fatalf("held request is %s", got)
		}
		f.api.E.POST("/api/connections/"+connID+"/resume").WithHeader("Authorization", f.issuerToken).
			Expect().Status(http.StatusOK)
		if got := status(); got != util.StatusActive {
			t.Fatalf("released request is %s", got)
		}

		f.api.E.POST("/api/connections/"+connID+"/disconnect").WithHeader("Authorization", f.issuerToken).
			WithJSON(map[string]any{"revokeLinks": true}).Expect().Status(http.StatusNoContent)
		if got := status(); got != util.StatusRevoked {
			t.Fatalf("request after disconnect with revoke is %s", got)
		}
	})
}
