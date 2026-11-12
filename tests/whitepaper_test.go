package tests

import (
	"encoding/json"
	"github.com/google/uuid"
	"io"
	"net/http"
	"net/http/httptest"
	"sort"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/pocketbase/pocketbase/core"
	"revoked/cmd/revoked/services"
	"revoked/tests/testutils"
	"revoked/util"
)

// A controlled origin isolates cache behavior from asynchronous grant events.
func TestWhitepaperCacheLifecycle(t *testing.T) {
	_, app := testutils.SetupTestApp(t)
	t.Setenv(util.AllowPrivateCallbacksEnv, "true")
	t.Setenv(services.GrantMaxAgeEnv, "")
	if services.GrantMaxAge() != 60 {
		t.Fatal("default freshness changed")
	}
	var calls atomic.Int64
	var revoked atomic.Bool
	var offline atomic.Bool
	origin := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls.Add(1)
		if offline.Load() {
			w.WriteHeader(http.StatusServiceUnavailable)
			return
		}
		var body struct {
			Grants []services.GrantReadItem `json:"grants"`
		}
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			t.Error(err)
			return
		}
		out := []services.GrantReadResult{}
		for _, item := range body.Grants {
			result := services.GrantReadResult{ID: item.ID, Status: util.StatusActive, Values: map[string]string{"address": "B"}, ETag: "B", MaxAge: 60}
			if revoked.Load() {
				result.Status = util.StatusRevoked
				result.Values = nil
				result.ETag = "revoked"
			}
			out = append(out, result)
		}
		_ = json.NewEncoder(w).Encode(map[string]any{"items": out})
	}))
	defer origin.Close()
	domain := "whitepaper.invalid"
	t.Setenv(util.PeerOverridesEnv, domain+"="+origin.URL)
	col, err := app.FindCollectionByNameOrId(util.Coll.RemoteGrants)
	if err != nil {
		t.Fatal(err)
	}
	rec := core.NewRecord(col)
	rec.Id = "paperremote0001"
	f := util.Fields.RemoteGrant
	rec.Set(f.Domain, domain)
	rec.Set(f.Grant, "papergrant00001")
	rec.Set(f.Token, "experiment")
	rec.Set(f.Status, util.StatusActive)
	t.Cleanup(func() { services.ForgetRemoteGrant(domain, "papergrant00001") })
	cached := services.GrantReadResult{Status: util.StatusActive, Values: map[string]string{"address": "A"}, ETag: "A", MaxAge: 60}
	read := func() services.RemoteResolution {
		return services.ResolveRemoteGrants(app, []*core.Record{rec})[rec.Id]
	}
	services.RememberRemoteGrant(domain, "papergrant00001", cached, time.Now())
	got := read()
	if got.Values["address"] != "A" || calls.Load() != 0 {
		t.Fatalf("fresh cache: %+v calls=%d", got, calls.Load())
	}
	t.Log("fresh cache: address A; origin calls=0 despite origin holding B")
	services.RememberRemoteGrant(domain, "papergrant00001", cached, time.Now().Add(-61*time.Second))
	got = read()
	if got.Values["address"] != "B" || calls.Load() != 1 {
		t.Fatalf("expired cache: %+v", got)
	}
	t.Log("expired cache: address B; origin calls=1")
	revoked.Store(true)
	got = read()
	if got.Values["address"] != "B" || calls.Load() != 1 {
		t.Fatalf("cached after revocation: %+v", got)
	}
	services.ForgetRemoteGrant(domain, "papergrant00001")
	got = read()
	if got.Status != util.StatusRevoked || len(got.Values) != 0 {
		t.Fatalf("fresh revoked read: %+v", got)
	}
	t.Log("revocation: cached B survives until invalidation; fresh read returns revoked without values")
	offline.Store(true)
	services.RememberRemoteGrant(domain, "papergrant00001", cached, time.Now().Add(-61*time.Second))
	got = read()
	if !got.Unreachable || len(got.Values) != 0 {
		t.Fatalf("outage: %+v", got)
	}
	t.Log("expired cache plus HTTP 503: unreachable without stale values")
	cached.MaxAge = 0
	services.RememberRemoteGrant(domain, "papergrant00001", cached, time.Now())
	before := calls.Load()
	got = read()
	if calls.Load() != before+1 || !got.Unreachable {
		t.Fatalf("zero freshness: %+v", got)
	}
	t.Log("zero freshness: no cache reuse; origin contacted")
}

func TestWhitepaperConcurrentViewCap(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed to create random user: %v", err)
	}
	wsID := api.Get(util.Coll.Users, userID, token).Expect().
		Status(http.StatusOK).JSON().Object().
		Value(util.Fields.User.ActiveWorkspace).String().Raw()

	recordID := extractID(t, baseURL, util.Coll.Records, token, map[string]any{
		util.Fields.Record.Key:       "once_key",
		util.Fields.Record.Value:     "read-once",
		util.Fields.Record.Label:     "Once",
		util.Fields.Record.Type:      util.TypeText,
		util.Fields.Record.Format:    util.FormatDefault,
		util.Fields.Record.User:      userID,
		util.Fields.Record.Workspace: wsID,
	})

	slug := "once-" + uuid.New().String()[:6]
	extractID(t, baseURL, util.Coll.Links, token, map[string]any{
		util.Fields.Link.Slug:      slug,
		util.Fields.Link.Label:     "Read once",
		util.Fields.Link.Status:    util.StatusActive,
		util.Fields.Link.MaxViews:  1,
		util.Fields.Link.Records:   []string{recordID},
		util.Fields.Link.User:      userID,
		util.Fields.Link.Workspace: wsID,
	})

	const n = 32
	start := make(chan struct{})
	var wg sync.WaitGroup
	var success atomic.Int64
	var failures atomic.Int64
	elapsed := make([]time.Duration, n)
	client := &http.Client{Timeout: 10 * time.Second}
	for i := 0; i < n; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			<-start
			begin := time.Now()
			resp, err := client.Post(baseURL+"/api/public/links/"+slug, "application/json", strings.NewReader("{}"))
			if err != nil {
				failures.Add(1)
				return
			}
			_, err = io.Copy(io.Discard, resp.Body)
			resp.Body.Close()
			elapsed[i] = time.Since(begin)
			if err != nil {
				failures.Add(1)
				return
			}
			if resp.StatusCode == http.StatusOK {
				success.Add(1)
			} else if resp.StatusCode >= 500 {
				failures.Add(1)
			}
		}(i)
	}
	close(start)
	wg.Wait()
	if success.Load() != 1 || failures.Load() != 0 {
		t.Fatalf("successful=%d transport/server failures=%d", success.Load(), failures.Load())
	}
	sort.Slice(elapsed, func(i, j int) bool { return elapsed[i] < elapsed[j] })
	t.Logf("32 concurrent readers, maxViews=1: success=%d rejected=%d; latency all responses p50=%s p95=%s max=%s", success.Load(), n-success.Load(), elapsed[15], elapsed[30], elapsed[31])
}
