package tests

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"revoked/util"
	"strings"
	"sync"
	"testing"

	"revoked/tests/testutils"

	"github.com/google/uuid"
)

// The callback test button fires a real delivery from the server, so it is
// bound by the same SSRF policy a real one is — an authenticated endpoint that
// fetches a caller-chosen URL is otherwise a port scanner with a login form.
func TestCallbackTestRefusesInternalTargets(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	_, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed to create random user: %v", err)
	}

	for _, target := range []string{
		"http://127.0.0.1:8090/admin",
		"http://169.254.169.254/latest/meta-data/",
		"file:///etc/passwd",
	} {
		t.Run(target, func(t *testing.T) {
			body := api.E.POST("/api/requests/callback-test").
				WithHeader("Authorization", token).
				WithJSON(map[string]any{"url": target}).
				Expect().Status(http.StatusOK).JSON().Object()

			body.Value("ok").Boolean().IsFalse()
			body.Value("status").Number().IsEqual(0)
			body.Value("code").String().IsEqual("blocked")
		})
	}
}

// Without a session it is not a test button, it is an open relay.
func TestCallbackTestRequiresAuth(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	api.E.POST("/api/requests/callback-test").
		WithJSON(map[string]any{"url": "https://example.com/hook"}).
		Expect().Status(http.StatusUnauthorized)
}

// The sample delivery must look like the real thing — same headers, same shape
// — or testing a hook proves nothing about the submission that follows.
func TestCallbackTestDeliversSamplePayload(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	// The hook under test is on loopback, which is exactly the case the flag exists
	// for. Read at call time, so setting it here reaches the running server.
	t.Setenv(util.AllowPrivateCallbacksEnv, "true")

	var (
		mu       sync.Mutex
		gotBody  []byte
		gotHead  string
		gotCount int
	)
	hook := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		b, _ := io.ReadAll(r.Body)
		mu.Lock()
		gotBody, gotHead, gotCount = b, r.Header.Get("X-Revoked-Request"), gotCount+1
		mu.Unlock()
		w.WriteHeader(http.StatusOK)
	}))
	defer hook.Close()

	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed to create random user: %v", err)
	}
	wsID := api.Get(util.Coll.Users, userID, token).Expect().
		Status(http.StatusOK).JSON().Object().
		Value(util.Fields.User.ActiveWorkspace).String().Raw()
	identityID, _ := newIdentity(t, baseURL, token, "cbtest-id", userID, wsID)

	slug := "cb" + strings.ReplaceAll(uuid.New().String()[:8], "-", "")
	requestID := extractID(t, baseURL, util.Coll.Requests, token, map[string]any{
		util.Fields.Request.Slug:      slug,
		util.Fields.Request.Label:     "Callback test",
		util.Fields.Request.Status:    util.StatusActive,
		util.Fields.Request.Identity:  identityID,
		util.Fields.Request.User:      userID,
		util.Fields.Request.Workspace: wsID,
	})

	result := api.E.POST("/api/requests/callback-test").
		WithHeader("Authorization", token).
		WithJSON(map[string]any{"url": hook.URL + "/hook", "requestId": requestID}).
		Expect().Status(http.StatusOK).JSON().Object()
	result.Value("ok").Boolean().IsTrue()
	result.Value("status").Number().IsEqual(http.StatusOK)
	result.Value("code").String().IsEqual("ok")

	mu.Lock()
	defer mu.Unlock()
	if gotCount != 1 {
		t.Fatalf("hook hit %d times, want 1", gotCount)
	}
	if gotHead != requestID {
		t.Errorf("X-Revoked-Request = %q, want the request id %q", gotHead, requestID)
	}

	payload := map[string]any{}
	if err := json.Unmarshal(gotBody, &payload); err != nil {
		t.Fatalf("hook received non-JSON: %v", err)
	}
	if payload["test"] != true {
		t.Errorf("sample payload must be flagged test:true, got %v", payload["test"])
	}
	if payload["requestId"] != requestID || payload["slug"] != slug {
		t.Errorf("sample payload names %v/%v, want %v/%v",
			payload["requestId"], payload["slug"], requestID, slug)
	}
	for _, key := range []string{"responseId", "linkId", "identifier", "senderName", "data"} {
		if _, ok := payload[key]; !ok {
			t.Errorf("sample payload is missing %q, so it does not match a real delivery", key)
		}
	}
}

// Lending another owner's request id would let the header name a request the
// caller cannot see.
func TestCallbackTestRefusesAnotherOwnersRequest(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	ownerID, ownerToken, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed to create random user: %v", err)
	}
	wsID := api.Get(util.Coll.Users, ownerID, ownerToken).Expect().
		Status(http.StatusOK).JSON().Object().
		Value(util.Fields.User.ActiveWorkspace).String().Raw()
	identityID, _ := newIdentity(t, baseURL, ownerToken, "cbtest-other", ownerID, wsID)

	requestID := extractID(t, baseURL, util.Coll.Requests, ownerToken, map[string]any{
		util.Fields.Request.Slug:      "cb" + strings.ReplaceAll(uuid.New().String()[:8], "-", ""),
		util.Fields.Request.Label:     "Someone else's",
		util.Fields.Request.Status:    util.StatusActive,
		util.Fields.Request.Identity:  identityID,
		util.Fields.Request.User:      ownerID,
		util.Fields.Request.Workspace: wsID,
	})

	_, intruderToken, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed to create random user: %v", err)
	}
	api.E.POST("/api/requests/callback-test").
		WithHeader("Authorization", intruderToken).
		WithJSON(map[string]any{"url": "https://example.com/hook", "requestId": requestID}).
		Expect().Status(http.StatusForbidden)
}
