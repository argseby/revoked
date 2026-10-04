package tests

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"revoked/cmd/revoked/server"
	"revoked/tests/testutils"
	"revoked/util"
)

// The suite runs one server, so it plays both sides: the requester's server
// and the responder's. PEER_OVERRIDES points its own domain (testDomain) back
// at it, which is also how two development instances find each other without
// DNS. Every call between the two sides still goes over HTTP through the same
// clients, signatures and token checks a real pair of servers uses.
func enableLoopbackPeers(t *testing.T, baseURL string) {
	t.Helper()
	t.Setenv(util.AllowPrivateCallbacksEnv, "true")
	t.Setenv(util.PeerOverridesEnv, testDomain+"="+baseURL)
}

// hookRecorder is a callback URL that keeps every body it receives.
type hookRecorder struct {
	srv    *httptest.Server
	mu     sync.Mutex
	bodies []map[string]any
}

func newHookRecorder(t *testing.T) *hookRecorder {
	t.Helper()
	h := &hookRecorder{}
	h.srv = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		raw, _ := io.ReadAll(r.Body)
		var body map[string]any
		_ = json.Unmarshal(raw, &body)
		h.mu.Lock()
		h.bodies = append(h.bodies, body)
		h.mu.Unlock()
		w.WriteHeader(http.StatusOK)
	}))
	t.Cleanup(h.srv.Close)
	return h
}

// find returns the first body for which match holds.
func (h *hookRecorder) find(match func(map[string]any) bool) map[string]any {
	h.mu.Lock()
	defer h.mu.Unlock()
	for _, b := range h.bodies {
		if match(b) {
			return b
		}
	}
	return nil
}

func eventually(t *testing.T, what string, cond func() bool) {
	t.Helper()
	deadline := time.Now().Add(15 * time.Second)
	for time.Now().Before(deadline) {
		if cond() {
			return
		}
		time.Sleep(100 * time.Millisecond)
	}
	t.Fatalf("timed out waiting for %s", what)
}

type remoteFixture struct {
	baseURL        string
	api            *testutils.PBClient
	requesterToken string
	requestID      string
	slug           string
	responderID    string
	responderToken string
	responderWs    string
	hook           *hookRecorder
}

func newRemoteFixture(t *testing.T, fields map[string]any) remoteFixture {
	t.Helper()
	baseURL, _ := testutils.SetupTestApp(t)
	enableLoopbackPeers(t, baseURL)
	api := testutils.NewPBClient(t, baseURL)

	reqUser, reqToken, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed to create requester: %v", err)
	}
	reqWs := activeWorkspaceOf(t, api, reqUser, reqToken)
	identityID, _ := newIdentity(t, baseURL, reqToken, "remote-requester", reqUser, reqWs)

	hook := newHookRecorder(t)
	merged := map[string]any{util.Fields.Request.CallbackUrl: hook.srv.URL}
	for k, v := range fields {
		merged[k] = v
	}
	slug, requestID := setupRequest(t, baseURL, reqToken, reqUser, reqWs, identityID, merged)

	respUser, respToken, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed to create responder: %v", err)
	}
	return remoteFixture{
		baseURL:        baseURL,
		api:            api,
		requesterToken: reqToken,
		requestID:      requestID,
		slug:           slug,
		responderID:    respUser,
		responderToken: respToken,
		responderWs:    activeWorkspaceOf(t, api, respUser, respToken),
		hook:           hook,
	}
}

// answer relays an answer through the responder's own server.
func (f remoteFixture) answer(body map[string]any) *http.Response {
	payload := map[string]any{"origin": f.baseURL, "slug": f.slug}
	for k, v := range body {
		payload[k] = v
	}
	raw, _ := json.Marshal(payload)
	req, _ := http.NewRequest(http.MethodPost, f.baseURL+"/api/requests/remote", strings.NewReader(string(raw)))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", f.responderToken)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		panic(err)
	}
	return resp
}

func decode(t *testing.T, resp *http.Response) map[string]any {
	t.Helper()
	defer resp.Body.Close()
	var out map[string]any
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		t.Fatalf("decode: %v", err)
	}
	return out
}

// responses returns the requester's view of its request, keyed by response id.
func (f remoteFixture) responses(t *testing.T) map[string]map[string]any {
	t.Helper()
	items := f.api.E.GET("/api/requests/"+f.requestID+"/links").
		WithHeader("Authorization", f.requesterToken).
		Expect().Status(http.StatusOK).JSON().Object().Value("items").Array()
	out := map[string]map[string]any{}
	for _, v := range items.Iter() {
		item := v.Object().Raw()
		out[item["id"].(string)] = item
	}
	return out
}

func (f remoteFixture) responderLink(t *testing.T, linkID string) map[string]any {
	t.Helper()
	return f.api.Get(util.Coll.Links, linkID, f.responderToken).
		Expect().Status(http.StatusOK).JSON().Object().Raw()
}

func TestRemoteAnswerLivesOnTheRespondersServer(t *testing.T) {
	f := newRemoteFixture(t, nil)

	resp := f.answer(map[string]any{
		"senderName": "Ada",
		"data":       map[string]any{"email": "ada@example.com"},
	})
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("relay refused: %d %v", resp.StatusCode, decode(t, resp))
	}
	out := decode(t, resp)
	linkID := out["linkId"].(string)
	responseID := out["responseId"].(string)
	if out["server"] != testDomain {
		t.Fatalf("server = %v", out["server"])
	}

	link := f.responderLink(t, linkID)
	if link[util.Fields.Link.RemoteDomain] != testDomain || link[util.Fields.Link.RemoteRequest] != f.slug {
		t.Fatalf("link does not name the requester's server: %v", link)
	}
	if _, leaked := link[util.Fields.Link.GrantTokenHash]; leaked {
		t.Fatal("grant token hash is exposed to the link owner")
	}
	grants := map[string]string{}
	switch g := link[util.Fields.Link.Grants].(type) {
	case map[string]any:
		for k, v := range g {
			grants[k] = v.(string)
		}
	}
	recordID := grants["email"]
	if recordID == "" {
		t.Fatalf("no vault entry behind the answer: %v", link)
	}

	t.Run("the requester reads the current value from the responder's server", func(t *testing.T) {
		item := f.responses(t)[responseID]
		if item == nil {
			t.Fatal("remote answer missing from the request's responses")
		}
		if item["remote"] != true || item["server"] != testDomain || item["status"] != util.StatusActive {
			t.Fatalf("unexpected item: %v", item)
		}
		if item["data"].(map[string]any)["email"] != "ada@example.com" {
			t.Fatalf("data = %v", item["data"])
		}
		if item["senderName"] != "Ada" {
			t.Fatalf("senderName = %v", item["senderName"])
		}
	})

	t.Run("the submission callback carries the values once", func(t *testing.T) {
		eventually(t, "submission callback", func() bool {
			return f.hook.find(func(b map[string]any) bool {
				return b["responseId"] == responseID && b["event"] == nil
			}) != nil
		})
		b := f.hook.find(func(b map[string]any) bool { return b["responseId"] == responseID && b["event"] == nil })
		if b["server"] != testDomain || b["data"].(map[string]any)["email"] != "ada@example.com" {
			t.Fatalf("callback = %v", b)
		}
	})

	t.Run("a changed entry reaches the requester as an event", func(t *testing.T) {
		f.api.Update(util.Coll.Records, recordID, f.responderToken, map[string]any{
			util.Fields.Record.Value: "ada@lovelace.example",
		}).Expect().Status(http.StatusOK)

		// The first read was kept for maxAge; only the event clears it early.
		eventually(t, "changed value at the requester", func() bool {
			item := f.responses(t)[responseID]
			return item != nil && item["data"].(map[string]any)["email"] == "ada@lovelace.example"
		})
		eventually(t, "grant.changed callback", func() bool {
			return f.hook.find(func(b map[string]any) bool {
				return b["event"] == util.GrantEventChanged && b["responseId"] == responseID
			}) != nil
		})
		b := f.hook.find(func(b map[string]any) bool { return b["event"] == util.GrantEventChanged })
		if _, hasValue := b["data"]; hasValue {
			t.Fatalf("an event must not carry values: %v", b)
		}
	})

	t.Run("answering again updates the same grant", func(t *testing.T) {
		resp := f.answer(map[string]any{
			"senderName": "Ada L.",
			"data":       map[string]any{"email": "ada@lovelace.example", "phone": "+44 20 7946 0000"},
		})
		if resp.StatusCode != http.StatusOK {
			t.Fatalf("re-answer refused: %d %v", resp.StatusCode, decode(t, resp))
		}
		again := decode(t, resp)
		if again["linkId"] != linkID || again["responseId"] != responseID || again["updated"] != true {
			t.Fatalf("re-answer did not update in place: %v", again)
		}
		eventually(t, "second key at the requester", func() bool {
			item := f.responses(t)[responseID]
			return item != nil && item["data"].(map[string]any)["phone"] == "+44 20 7946 0000"
		})
		count := 0
		for _, item := range f.responses(t) {
			if item["remote"] == true {
				count++
			}
		}
		if count != 1 {
			t.Fatalf("expected one remote response, got %d", count)
		}
	})

	t.Run("revoking reaches the requester and drops the values", func(t *testing.T) {
		f.api.Update(util.Coll.Links, linkID, f.responderToken, map[string]any{
			util.Fields.Link.Status: util.StatusRevoked,
		}).Expect().Status(http.StatusOK)

		eventually(t, "revocation at the requester", func() bool {
			item := f.responses(t)[responseID]
			return item != nil && item["status"] == util.StatusRevoked
		})
		item := f.responses(t)[responseID]
		if len(item["data"].(map[string]any)) != 0 {
			t.Fatalf("a revoked grant still shows values: %v", item["data"])
		}
		eventually(t, "grant.revoked callback", func() bool {
			return f.hook.find(func(b map[string]any) bool {
				return b["event"] == util.GrantEventRevoked && b["responseId"] == responseID
			}) != nil
		})
		notes := f.api.List(util.Coll.Notifications, f.requesterToken).
			WithQuery("filter", "type = '"+util.NotificationLinkRevoked+"'").
			Expect().Status(http.StatusOK).JSON().Object()
		notes.Value("totalItems").Number().Gt(0)
	})
}

func TestRemoteAnswerRefusedLeavesNothingBehind(t *testing.T) {
	f := newRemoteFixture(t, map[string]any{util.Fields.Request.Password: "topsecret"})

	resp := f.answer(map[string]any{
		"password": "wrong",
		"data":     map[string]any{"refused_key": "value"},
	})
	if resp.StatusCode != http.StatusUnauthorized {
		t.Fatalf("status = %d", resp.StatusCode)
	}
	if code := decode(t, resp)["code"]; code != util.Errors.RequestPasswordInvalid.ErrorCode {
		t.Fatalf("the requester's refusal was not passed on: %v", code)
	}

	links := f.api.List(util.Coll.Links, f.responderToken).
		WithQuery("filter", "remoteRequest = '"+f.slug+"'").
		Expect().Status(http.StatusOK).JSON().Object()
	links.Value("totalItems").Number().IsEqual(0)

	records := f.api.List(util.Coll.Records, f.responderToken).
		WithQuery("filter", "key = 'refused_key'").
		Expect().Status(http.StatusOK).JSON().Object()
	records.Value("totalItems").Number().IsEqual(0)

	resp = f.answer(map[string]any{
		"password": "topsecret",
		"data":     map[string]any{"refused_key": "value"},
	})
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("correct password refused: %d %v", resp.StatusCode, decode(t, resp))
	}
}

func TestRemoteAnswerWithIdentityProof(t *testing.T) {
	f := newRemoteFixture(t, map[string]any{util.Fields.Request.RequireHandshake: true})
	identityID, kp := newIdentity(t, f.baseURL, f.responderToken, "remote-responder", f.responderID, f.responderWs)

	t.Run("without a signed challenge it is refused", func(t *testing.T) {
		resp := f.answer(map[string]any{
			"identityId": identityID,
			"data":       map[string]any{"name": "Ada"},
		})
		if resp.StatusCode != http.StatusUnauthorized {
			t.Fatalf("status = %d", resp.StatusCode)
		}
		if code := decode(t, resp)["code"]; code != util.Errors.ChallengeRequired.ErrorCode {
			t.Fatalf("code = %v", code)
		}
	})

	t.Run("the requester verifies the identity with its issuer", func(t *testing.T) {
		nonce := f.api.E.GET("/api/challenges/request/"+f.slug).
			WithQuery("identityId", identityID).
			Expect().Status(http.StatusOK).JSON().Object().Value("nonce").String().Raw()
		resp := f.answer(map[string]any{
			"identityId":         identityID,
			"challengeNonce":     nonce,
			"challengeSignature": kp.SignChallenge(t, nonce),
			"data":               map[string]any{"name": "Ada"},
		})
		if resp.StatusCode != http.StatusOK {
			t.Fatalf("relay refused: %d %v", resp.StatusCode, decode(t, resp))
		}
		responseID := decode(t, resp)["responseId"].(string)
		item := f.responses(t)[responseID]
		if item["identity"] == "" || item["identityName"] != "remote-responder" || item["identityDomain"] != testDomain {
			t.Fatalf("identity not recorded: %v", item)
		}
	})

	t.Run("an identity of someone else cannot be relayed", func(t *testing.T) {
		otherUser, otherToken, err := testutils.CreateRandomUser(f.baseURL)
		if err != nil {
			t.Fatal(err)
		}
		otherWs := activeWorkspaceOf(t, f.api, otherUser, otherToken)
		foreignID, _ := newIdentity(t, f.baseURL, otherToken, "someone-else", otherUser, otherWs)
		resp := f.answer(map[string]any{"identityId": foreignID, "data": map[string]any{"name": "Ada"}})
		if resp.StatusCode != http.StatusForbidden {
			t.Fatalf("status = %d", resp.StatusCode)
		}
	})
}

func TestGrantReadsAreTokenBound(t *testing.T) {
	f := newRemoteFixture(t, nil)
	resp := f.answer(map[string]any{"data": map[string]any{"city": "London"}})
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("relay refused: %d %v", resp.StatusCode, decode(t, resp))
	}
	linkID := decode(t, resp)["linkId"].(string)

	t.Run("a wrong token reads as not found", func(t *testing.T) {
		items := f.api.E.POST("/api/grants/resolve").
			WithJSON(map[string]any{"grants": []map[string]any{
				{"id": linkID, "token": "not-the-token"},
				{"id": "doesnotexist000", "token": "x"},
			}}).
			Expect().Status(http.StatusOK).JSON().Object().Value("items").Array()
		items.Length().IsEqual(2)
		for _, v := range items.Iter() {
			obj := v.Object()
			obj.Value("status").String().IsEqual("not_found")
			obj.NotContainsKey("values")
		}
	})

	t.Run("a batch that is too large is refused", func(t *testing.T) {
		batch := make([]map[string]any, 101)
		for i := range batch {
			batch[i] = map[string]any{"id": "x", "token": "y"}
		}
		f.api.E.POST("/api/grants/resolve").
			WithJSON(map[string]any{"grants": batch}).
			Expect().Status(http.StatusBadRequest)
	})

	t.Run("a local share cannot be read as a grant", func(t *testing.T) {
		shareID := extractID(t, f.baseURL, util.Coll.Links, f.responderToken, map[string]any{
			util.Fields.Link.Slug:      "plain-share-" + linkID,
			util.Fields.Link.Label:     "Plain share",
			util.Fields.Link.Status:    util.StatusActive,
			util.Fields.Link.User:      f.responderID,
			util.Fields.Link.Workspace: f.responderWs,
		})
		f.api.E.POST("/api/grants/resolve").
			WithJSON(map[string]any{"grants": []map[string]any{{"id": shareID, "token": ""}}}).
			Expect().Status(http.StatusOK).JSON().Object().
			Value("items").Array().Value(0).Object().Value("status").String().IsEqual("not_found")
	})
}

func TestGrantEventsMustBeSignedByTheSender(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	enableLoopbackPeers(t, baseURL)
	api := testutils.NewPBClient(t, baseURL)

	// A key that is not the test server's, claiming to be it.
	impostor, err := server.Load(testDomain, t.TempDir()+"/impostor.pem")
	if err != nil {
		t.Fatal(err)
	}
	signed, err := impostor.SignGrantEvents(testDomain, []server.GrantEvent{
		{Grant: "anything", Type: util.GrantEventRevoked, Status: util.StatusRevoked, At: time.Now().UnixMilli()},
	}, time.Now())
	if err != nil {
		t.Fatal(err)
	}
	api.E.POST("/api/grants/events").WithJSON(signed).
		Expect().Status(http.StatusUnauthorized).
		JSON().Object().Value("code").String().IsEqual(util.Errors.GrantEventsUnverified.ErrorCode)

	api.E.POST("/api/grants/events").WithJSON(map[string]any{"payload": "!!", "signature": "00"}).
		Expect().Status(http.StatusUnauthorized)
}

// A grant on this server's own request also tells the request's callback when
// it changes, so a tool behind a request learns of changes without polling
// whichever server the answer lives on.
func TestLocalGrantEventsReachTheCallback(t *testing.T) {
	f := newRemoteFixture(t, nil)

	resp := f.api.E.POST("/api/public/requests/"+f.slug).
		WithHeader("Authorization", f.responderToken).
		WithJSON(map[string]any{"data": map[string]any{"iban": "GB33BUKB20201555555555"}}).
		Expect().Status(http.StatusOK).JSON().Object()
	linkID := resp.Value("linkId").String().Raw()

	link := f.responderLink(t, linkID)
	recordID := link[util.Fields.Link.Grants].(map[string]any)["iban"].(string)

	f.api.Update(util.Coll.Records, recordID, f.responderToken, map[string]any{
		util.Fields.Record.Value: "GB94BARC10201530093459",
	}).Expect().Status(http.StatusOK)

	eventually(t, "grant.changed callback", func() bool {
		return f.hook.find(func(b map[string]any) bool {
			return b["event"] == util.GrantEventChanged && b["responseId"] == linkID
		}) != nil
	})

	f.api.Delete(util.Coll.Records, recordID, f.responderToken).Expect().Status(http.StatusNoContent)
	eventually(t, "grant.revoked callback after the only entry was deleted", func() bool {
		return f.hook.find(func(b map[string]any) bool {
			return b["event"] == util.GrantEventRevoked && b["responseId"] == linkID
		}) != nil
	})
}

func TestRemoteLinkFieldsAreServerSet(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)
	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatal(err)
	}
	wsID := activeWorkspaceOf(t, api, userID, token)

	api.Create(util.Coll.Links, token, map[string]any{
		util.Fields.Link.Slug:         "forged-remote-link",
		util.Fields.Link.Label:        "Forged",
		util.Fields.Link.User:         userID,
		util.Fields.Link.Workspace:    wsID,
		util.Fields.Link.RemoteDomain: "victim.example",
	}).Expect().Status(http.StatusBadRequest)
}

func TestRelayRefusesUnusableOrigins(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)
	_, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatal(err)
	}
	for _, origin := range []string{"", "http://example.com", "ftp://example.com", "not a url"} {
		api.E.POST("/api/requests/remote").
			WithHeader("Authorization", token).
			WithJSON(map[string]any{"origin": origin, "slug": "abc"}).
			Expect().Status(http.StatusBadRequest).
			JSON().Object().Value("code").String().IsEqual(util.Errors.RemoteOriginInvalid.ErrorCode)
	}
	api.E.POST("/api/requests/remote").
		WithJSON(map[string]any{"origin": "https://example.com", "slug": "abc"}).
		Expect().Status(http.StatusUnauthorized)
}
