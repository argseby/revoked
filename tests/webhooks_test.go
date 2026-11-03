package tests

import (
	"encoding/json"
	"github.com/gavv/httpexpect/v2"
	"io"
	"net/http"
	"net/http/httptest"
	"slices"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"revoked/cmd/revoked/services"
	"revoked/tests/testutils"
	"revoked/util"

	"github.com/google/uuid"
	"github.com/pocketbase/pocketbase"
	"github.com/pocketbase/pocketbase/core"
)

type webhookHit struct {
	Body      map[string]any
	Raw       []byte
	Signature string
	EventType string
}

// webhookReceiver records every delivery and answers with whatever status is
// current.
type webhookReceiver struct {
	srv    *httptest.Server
	status atomic.Int32
	mu     sync.Mutex
	hits   []webhookHit
}

func newWebhookReceiver(t *testing.T) *webhookReceiver {
	t.Helper()
	t.Setenv(util.AllowPrivateCallbacksEnv, "true")
	r := &webhookReceiver{}
	r.status.Store(http.StatusOK)
	r.srv = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		raw, _ := io.ReadAll(req.Body)
		var body map[string]any
		_ = json.Unmarshal(raw, &body)
		r.mu.Lock()
		r.hits = append(r.hits, webhookHit{
			Body:      body,
			Raw:       raw,
			Signature: req.Header.Get(util.WebhookSignatureHeader),
			EventType: req.Header.Get(util.WebhookEventTypeHeader),
		})
		r.mu.Unlock()
		w.WriteHeader(int(r.status.Load()))
		_, _ = w.Write([]byte(`{"received":true}`))
	}))
	t.Cleanup(r.srv.Close)
	return r
}

// waitFor returns the first delivery of the given type, failing after a few
// seconds: delivery runs on the background worker.
func (r *webhookReceiver) waitFor(t *testing.T, eventType string) webhookHit {
	t.Helper()
	deadline := time.Now().Add(8 * time.Second)
	for time.Now().Before(deadline) {
		r.mu.Lock()
		for _, h := range r.hits {
			if h.EventType == eventType {
				r.mu.Unlock()
				return h
			}
		}
		r.mu.Unlock()
		time.Sleep(50 * time.Millisecond)
	}
	t.Fatalf("no %s delivery arrived", eventType)
	return webhookHit{}
}

func (r *webhookReceiver) count(eventType string) int {
	r.mu.Lock()
	defer r.mu.Unlock()
	n := 0
	for _, h := range r.hits {
		if h.EventType == eventType {
			n++
		}
	}
	return n
}

func webhookWorkspaceOf(t *testing.T, app *pocketbase.PocketBase, userID string) string {
	t.Helper()
	u, err := app.FindRecordById(util.Coll.Users, userID)
	if err != nil {
		t.Fatal(err)
	}
	return u.GetString(util.Fields.User.ActiveWorkspace)
}

func createShare(t *testing.T, api *testutils.PBClient, token, workspace string) string {
	t.Helper()
	return api.Create(util.Coll.Links, token, map[string]any{
		util.Fields.Link.Slug:      "wh" + strings.ReplaceAll(uuid.New().String(), "-", ""),
		util.Fields.Link.Label:     "Webhook probe",
		util.Fields.Link.Status:    util.StatusActive,
		util.Fields.Link.Workspace: workspace,
	}).Expect().Status(http.StatusOK).JSON().Object().Value("id").String().Raw()
}

func verifySignature(t *testing.T, header, secret string, raw []byte) {
	t.Helper()
	var ts string
	var sigs []string
	for _, part := range strings.Split(header, ",") {
		k, v, _ := strings.Cut(part, "=")
		switch k {
		case "t":
			ts = v
		case "v1":
			sigs = append(sigs, v)
		}
	}
	if ts == "" || len(sigs) == 0 {
		t.Fatalf("malformed signature header %q", header)
	}
	var unix int64
	if err := json.Unmarshal([]byte(ts), &unix); err != nil {
		t.Fatalf("bad timestamp %q", ts)
	}
	want := services.SignWebhook(secret, time.Unix(unix, 0), raw)
	for _, s := range sigs {
		if s == want {
			return
		}
	}
	t.Fatalf("no signature in %q matches the secret", header)
}

// A share's life reaches the endpoint as signed events, and the signing
// secret is handed out once, on create, and never in a list.
func TestWebhookDeliversSignedLinkEvents(t *testing.T) {
	baseURL, app := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)
	rcv := newWebhookReceiver(t)

	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatal(err)
	}
	ws := webhookWorkspaceOf(t, app, userID)

	created := api.E.POST("/api/webhooks/endpoints").WithHeader("Authorization", token).
		WithJSON(map[string]any{"url": rcv.srv.URL + "/hook", "events": []string{"link.created", "link.paused"}}).
		Expect().Status(http.StatusCreated).JSON().Object()
	secret := created.Value("secret").String().Raw()
	if !strings.HasPrefix(secret, util.WebhookSecretPrefix) {
		t.Fatalf("secret %q lacks its prefix", secret)
	}
	endpointID := created.Value("id").String().Raw()

	list := api.E.GET("/api/webhooks/endpoints").WithHeader("Authorization", token).
		Expect().Status(http.StatusOK).Body().Raw()
	if strings.Contains(list, secret) {
		t.Fatal("the endpoint list carries the signing secret")
	}

	linkID := createShare(t, api, token, ws)
	hit := rcv.waitFor(t, util.WebhookLinkCreated)
	verifySignature(t, hit.Signature, secret, hit.Raw)
	data := hit.Body["data"].(map[string]any)
	if data["id"] != linkID || data["kind"] != "share" || hit.Body["workspace"] != ws {
		t.Fatalf("unexpected payload %v", hit.Body)
	}
	if _, leaked := data["slug"]; leaked {
		t.Fatal("a link event carries the slug")
	}

	api.Update(util.Coll.Links, linkID, token, map[string]any{util.Fields.Link.Status: util.StatusPaused}).
		Expect().Status(http.StatusOK)
	rcv.waitFor(t, util.WebhookLinkPaused)

	// Not subscribed, so never sent.
	api.Update(util.Coll.Links, linkID, token, map[string]any{util.Fields.Link.Status: util.StatusRevoked}).
		Expect().Status(http.StatusOK)
	time.Sleep(300 * time.Millisecond)
	if n := rcv.count(util.WebhookLinkRevoked); n != 0 {
		t.Fatalf("an unsubscribed event was delivered %d times", n)
	}

	api.E.GET("/api/webhooks/deliveries").WithHeader("Authorization", token).
		WithQuery("endpoint", endpointID).WithQuery("status", "succeeded").
		Expect().Status(http.StatusOK).JSON().Object().Value("items").Array().Length().IsEqual(2)
}

// A failing receiver keeps the delivery pending for a retry, and a resend
// that lands marks it delivered while the log keeps both attempts.
func TestWebhookRetryAndResend(t *testing.T) {
	baseURL, app := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)
	rcv := newWebhookReceiver(t)
	rcv.status.Store(http.StatusInternalServerError)

	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatal(err)
	}
	ws := webhookWorkspaceOf(t, app, userID)
	endpointID := api.E.POST("/api/webhooks/endpoints").WithHeader("Authorization", token).
		WithJSON(map[string]any{"url": rcv.srv.URL, "events": []string{"*"}}).
		Expect().Status(http.StatusCreated).JSON().Object().Value("id").String().Raw()

	createShare(t, api, token, ws)
	rcv.waitFor(t, util.WebhookLinkCreated)

	var deliveryID string
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		items := api.E.GET("/api/webhooks/deliveries").WithHeader("Authorization", token).
			WithQuery("type", util.WebhookLinkCreated).
			Expect().Status(http.StatusOK).JSON().Object().Value("items").Array()
		if items.Length().Raw() > 0 {
			d := items.Value(0).Object()
			if d.Value("attempts").Number().Raw() == 1 {
				d.Value("status").String().IsEqual(util.WebhookDeliveryPending)
				d.Value("lastStatus").Number().IsEqual(500)
				deliveryID = d.Value("id").String().Raw()
				break
			}
		}
		time.Sleep(50 * time.Millisecond)
	}
	if deliveryID == "" {
		t.Fatal("the failed delivery was not recorded")
	}

	rcv.status.Store(http.StatusOK)
	detail := api.E.POST("/api/webhooks/deliveries/"+deliveryID+"/resend").WithHeader("Authorization", token).
		Expect().Status(http.StatusOK).JSON().Object()
	detail.Value("status").String().IsEqual(util.WebhookDeliverySucceeded)
	log := detail.Value("attemptLog").Array()
	log.Length().IsEqual(2)
	log.Value(0).Object().Value("manual").Boolean().IsTrue()
	log.Value(0).Object().Value("responseStatus").Number().IsEqual(200)
	log.Value(1).Object().Value("responseStatus").Number().IsEqual(500)
	detail.Value("payload").Object().Value("type").String().IsEqual(util.WebhookLinkCreated)

	t.Run("its metrics count both attempts and the event sent", func(t *testing.T) {
		metrics := func(r string) *httpexpect.Object {
			return api.E.GET("/api/webhooks/endpoints/"+endpointID+"/metrics").WithHeader("Authorization", token).
				WithQuery("range", r).Expect().Status(http.StatusOK).JSON().Object()
		}
		m := metrics("24h")
		m.Value("range").String().IsEqual("24h")
		buckets := m.Value("buckets").Array()
		buckets.Length().IsEqual(24)
		last := buckets.Value(23).Object()
		last.Value("delivered").Number().Ge(1)
		last.Value("failed").Number().Ge(1)
		m.Value("codes").Object().Value("2xx").Number().Ge(1)
		m.Value("codes").Object().Value("5xx").Number().Ge(1)
		m.Value("deliveries").Number().Ge(1)
		types := []string{}
		for _, e := range m.Value("events").Array().Iter() {
			types = append(types, e.Object().Value("type").String().Raw())
		}
		if !slices.Contains(types, util.WebhookLinkCreated) {
			t.Fatalf("link.created missing from the event counts: %v", types)
		}
		metrics("1h").Value("buckets").Array().Length().IsEqual(12)
		metrics("7d").Value("buckets").Array().Length().IsEqual(28)
		metrics("nonsense").Value("range").String().IsEqual("24h")

		api.E.GET("/api/webhooks/endpoints").WithHeader("Authorization", token).
			Expect().Status(http.StatusOK).JSON().Object().Value("items").Array().
			Value(0).Object().Value("series").Array().Length().IsEqual(24)

		other := testutils.NewPBClient(t, baseURL)
		_, otherToken, _ := testutils.CreateRandomUser(baseURL)
		other.E.GET("/api/webhooks/endpoints/"+endpointID+"/metrics").WithHeader("Authorization", otherToken).
			Expect().Status(http.StatusNotFound)
	})
}

// The test button sends a marked sample through the real path.
func TestWebhookTestEvent(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)
	rcv := newWebhookReceiver(t)

	_, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatal(err)
	}
	id := api.E.POST("/api/webhooks/endpoints").WithHeader("Authorization", token).
		WithJSON(map[string]any{"url": rcv.srv.URL}).
		Expect().Status(http.StatusCreated).JSON().Object().Value("id").String().Raw()

	res := api.E.POST("/api/webhooks/endpoints/"+id+"/test").WithHeader("Authorization", token).
		WithJSON(map[string]any{"type": util.WebhookResponseSubmitted}).
		Expect().Status(http.StatusOK).JSON().Object()
	res.Value("status").String().IsEqual(util.WebhookDeliverySucceeded)
	res.Value("test").Boolean().IsTrue()

	hit := rcv.waitFor(t, util.WebhookResponseSubmitted)
	if hit.Body["test"] != true {
		t.Fatalf("a test event is not marked: %v", hit.Body)
	}
}

// Another workspace's webhooks answer as missing, and a caller without the
// permission or a session is refused.
func TestWebhookAccess(t *testing.T) {
	baseURL, app := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)
	t.Setenv(util.AllowPrivateCallbacksEnv, "true")

	ownerID, owner, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatal(err)
	}
	_, stranger, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatal(err)
	}
	id := api.E.POST("/api/webhooks/endpoints").WithHeader("Authorization", owner).
		WithJSON(map[string]any{"url": "http://127.0.0.1:9/hook"}).
		Expect().Status(http.StatusCreated).JSON().Object().Value("id").String().Raw()

	api.E.GET("/api/webhooks/endpoints").Expect().Status(http.StatusUnauthorized)
	api.E.GET("/api/webhooks/endpoints/"+id).WithHeader("Authorization", stranger).
		Expect().Status(http.StatusNotFound).JSON().Object().
		Value("code").String().IsEqual(util.Errors.WebhookNotFound.ErrorCode)
	api.E.GET("/api/webhooks/endpoints/"+id+"/secret").WithHeader("Authorization", stranger).
		Expect().Status(http.StatusNotFound)

	ws := webhookWorkspaceOf(t, app, ownerID)
	keys, _ := app.FindCollectionByNameOrId(util.Coll.ApiKeys)
	mkKey := func(scopes []string) string {
		tok := uuid.New().String()
		k := core.NewRecord(keys)
		k.Set("label", "key")
		k.Set("token", util.HashToken(tok))
		k.Set("user", ownerID)
		k.Set("workspace", ws)
		k.Set("scopes", scopes)
		if err := app.Save(k); err != nil {
			t.Fatal(err)
		}
		return tok
	}
	api.E.GET("/api/webhooks/endpoints").WithHeader("X-API-Key", mkKey([]string{util.ScopeLinkRead})).
		Expect().Status(http.StatusForbidden)
	api.E.GET("/api/webhooks/endpoints").WithHeader("X-API-Key", mkKey([]string{util.ScopeWebhookManage})).
		Expect().Status(http.StatusOK).JSON().Object().Value("items").Array().Length().IsEqual(1)
}

func TestWebhookValidation(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	_, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatal(err)
	}
	refused := func(body map[string]any, code string) {
		api.E.POST("/api/webhooks/endpoints").WithHeader("Authorization", token).
			WithJSON(body).Expect().Status(http.StatusBadRequest).JSON().Object().
			Value("code").String().IsEqual(code)
	}
	refused(map[string]any{"url": "http://169.254.169.254/latest"}, util.Errors.WebhookUrlInvalid.ErrorCode)
	refused(map[string]any{"url": "https://example.com/hook", "events": []string{"link.exploded"}},
		util.Errors.WebhookEventsInvalid.ErrorCode)
	refused(map[string]any{"url": "https://example.com/hook", "events": []string{}},
		util.Errors.WebhookEventsInvalid.ErrorCode)
	t.Run("the app learns whether local addresses can receive anything", func(t *testing.T) {
		types := func() *httpexpect.Object {
			return api.E.GET("/api/webhooks/event-types").WithHeader("Authorization", token).
				Expect().Status(http.StatusOK).JSON().Object()
		}
		t.Setenv(util.AllowPrivateCallbacksEnv, "")
		types().Value("privateCallbacks").Boolean().IsFalse()
		refused(map[string]any{"url": "http://127.0.0.1:47381/"}, util.Errors.WebhookUrlInvalid.ErrorCode)
		t.Setenv(util.AllowPrivateCallbacksEnv, "true")
		types().Value("privateCallbacks").Boolean().IsTrue()
	})
}

// "*" leaves the noisy types out unless they are named.
func TestWebhookSubscribes(t *testing.T) {
	all := []string{util.WebhookAllEvents}
	if !util.WebhookSubscribes(all, util.WebhookLinkRevoked) {
		t.Fatal("* misses link.revoked")
	}
	if util.WebhookSubscribes(all, util.WebhookLinkViewed) {
		t.Fatal("* includes the noisy link.viewed")
	}
	if !util.WebhookSubscribes([]string{util.WebhookLinkViewed}, util.WebhookLinkViewed) {
		t.Fatal("a named noisy type is not sent")
	}
}
