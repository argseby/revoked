package tests

import (
	"net/http"
	"sync"
	"testing"
	"time"

	"revoked/cmd/revoked/services"
	"revoked/tests/testutils"
	"revoked/util"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
)

// Pause the production resolver at its first value lookup, after the state check.
type pausedGrantApp struct {
	core.App
	recordID string
	reached  chan struct{}
	resume   chan struct{}
	once     sync.Once
}

func (a *pausedGrantApp) FindRecordById(collection any, id string, filters ...func(*dbx.SelectQuery) error) (*core.Record, error) {
	if collection == util.Coll.Records && id == a.recordID {
		a.once.Do(func() { close(a.reached) })
		<-a.resume
	}
	return a.App.FindRecordById(collection, id, filters...)
}

func TestWhitepaperInFlightRevocation(t *testing.T) {
	f := newRemoteFixture(t, nil)
	response := f.answer(map[string]any{"data": map[string]any{"email": "ada@example.com"}})
	if response.StatusCode != http.StatusOK {
		t.Fatalf("answer: %d %v", response.StatusCode, decode(t, response))
	}
	id := decode(t, response)["linkId"].(string)
	_, app := testutils.SetupTestApp(t)
	link, err := app.FindRecordById(util.Coll.Links, id)
	if err != nil {
		t.Fatal(err)
	}
	recordID := services.LinkGrantMap(link)["email"]
	if recordID == "" {
		t.Fatal("missing granted record")
	}
	paused := &pausedGrantApp{App: app, recordID: recordID, reached: make(chan struct{}), resume: make(chan struct{})}
	var release sync.Once
	defer release.Do(func() { close(paused.resume) })
	result := make(chan services.GrantResolution, 1)
	go func() { result <- services.ResolveGrant(paused, link) }()
	select {
	case <-paused.reached:
	case <-time.After(10 * time.Second):
		t.Fatal("resolver did not reach value lookup")
	}
	f.api.Update(util.Coll.Links, id, f.responderToken, map[string]any{util.Fields.Link.Status: util.StatusRevoked}).Expect().Status(http.StatusOK)
	fresh, err := app.FindRecordById(util.Coll.Links, id)
	if err != nil {
		t.Fatal(err)
	}
	if fresh.GetString(util.Fields.Link.Status) != util.StatusRevoked {
		t.Fatal("revocation not persisted")
	}
	t.Log("barrier reached after active-state check; HTTP revocation acknowledged; persisted status confirmed revoked")
	release.Do(func() { close(paused.resume) })
	select {
	case got := <-result:
		if got.Status != util.StatusActive || got.Values["email"] != "ada@example.com" {
			t.Fatalf("overlapping read: %+v", got)
		}
	case <-time.After(10 * time.Second):
		t.Fatal("resolver did not finish")
	}
	got := services.ResolveGrant(app, fresh)
	if got.Status != util.StatusRevoked || len(got.Values) != 0 {
		t.Fatalf("fresh read: %+v", got)
	}
	t.Log("overlapping production service read returned active plus value after revocation; fresh read returned revoked without values")
}
