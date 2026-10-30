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
)

// One person asks another to show an attestation. The asker's server stands
// in for the service: it makes the present link, receives the answer,
// verifies it on arrival and keeps only the verdict.

type checkFixture struct {
	attestationFixture
	askerIdentity string
	credential    string
}

func newCheckFixture(t *testing.T) checkFixture {
	t.Helper()
	f := newAttestationFixture(t)
	_, token := f.offer(t, nil)
	credential := f.acceptLocal(t, token)[util.Fields.Credential.Credential].(string)
	askerIdentity, _ := newIdentity(t, f.baseURL, f.issuerToken, "Ben", f.issuerID, f.issuerWs)
	return checkFixture{attestationFixture: f, askerIdentity: askerIdentity, credential: credential}
}

// ask creates a check as the asker and returns its id and present query.
func (f checkFixture) ask(t *testing.T, body map[string]any) (string, map[string]any) {
	t.Helper()
	resp := postJSON(t, f.baseURL+"/api/attestation-checks", f.issuerToken, body)
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("creating a check answered %d: %v", resp.StatusCode, decode(t, resp))
	}
	out := decode(t, resp)
	return out["id"].(string), out["present"].(map[string]any)
}

func (f checkFixture) answer(t *testing.T, present map[string]any, presentation string) *http.Response {
	t.Helper()
	return postJSON(t, present["response_uri"].(string), "", map[string]any{
		"presentation": presentation,
		"state":        present["state"],
	})
}

func (f checkFixture) presentFor(t *testing.T, present map[string]any, disclose []string) string {
	return f.present(t, f.credential, disclose, present["client_id"].(string), present["nonce"].(string))
}

func (f checkFixture) check(t *testing.T, id, token string) map[string]any {
	t.Helper()
	return f.api.E.GET("/api/collections/"+util.Coll.AttestationChecks+"/records/"+id).
		WithHeader("Authorization", token).
		Expect().Status(http.StatusOK).JSON().Object().Raw()
}

func TestAttestationCheckIsAnsweredOnceAndVerified(t *testing.T) {
	f := newCheckFixture(t)
	id, present := f.ask(t, map[string]any{
		"type": "membership", "issuers": []string{testDomain},
		"claims": []string{"age_over_18"}, "identityId": f.askerIdentity,
	})

	t.Run("the link is the ordinary present link, answered at this server", func(t *testing.T) {
		if present["client_id"] != f.baseURL || present["response_uri"] != f.baseURL+"/api/public/attestation-checks/answer" {
			t.Fatalf("present = %v", present)
		}
		if present["state"] != id || present["type"] != "membership" || present["claims"] != "age_over_18" {
			t.Fatalf("present = %v", present)
		}
		if nonce, _ := present["nonce"].(string); len(nonce) < 32 {
			t.Fatalf("nonce %q is too short to be unguessable", nonce)
		}
	})

	t.Run("the other app learns who asks", func(t *testing.T) {
		probe := f.api.E.GET("/api/public/attestation-checks/" + id).
			Expect().Status(http.StatusOK).JSON().Object()
		asker := probe.Value("asker").Object()
		asker.Value("name").String().IsEqual("Ben")
		asker.Value("fingerprint").String().NotEmpty()
		probe.Value("server").Object().Value("domain").String().IsEqual(testDomain)
	})

	t.Run("an answer that is not a presentation leaves the check open", func(t *testing.T) {
		if resp := f.answer(t, present, "not-a-credential"); resp.StatusCode != http.StatusBadRequest {
			t.Fatalf("garbage answered %d", resp.StatusCode)
		}
		// Made for another verifier: it does not bind to this check.
		other := f.present(t, f.credential, nil, "https://shop.example", present["nonce"].(string))
		if resp := f.answer(t, present, other); resp.StatusCode != http.StatusBadRequest {
			t.Fatalf("another audience answered %d", resp.StatusCode)
		}
		if got := f.check(t, id, f.issuerToken)[util.Fields.AttestationCheck.Status]; got != util.CheckStatusOpen {
			t.Fatalf("status = %v", got)
		}
	})

	t.Run("the answer is verified and only the verdict is kept", func(t *testing.T) {
		resp := f.answer(t, present, f.presentFor(t, present, []string{"age_over_18"}))
		if resp.StatusCode != http.StatusOK {
			t.Fatalf("answer refused: %d %v", resp.StatusCode, decode(t, resp))
		}
		if got := decode(t, resp)["state"]; got != services.AttestationVerified {
			t.Fatalf("state = %v", got)
		}
		row := f.check(t, id, f.issuerToken)
		if row[util.Fields.AttestationCheck.Status] != util.CheckStatusAnswered {
			t.Fatalf("status = %v", row[util.Fields.AttestationCheck.Status])
		}
		if _, leaked := row[util.Fields.AttestationCheck.Nonce]; leaked {
			t.Fatal("the nonce is readable through the collection API")
		}
		result := row[util.Fields.AttestationCheck.Result].(map[string]any)
		claims := result["claims"].(map[string]any)
		if result["state"] != services.AttestationVerified || len(claims) != 1 || claims["age_over_18"] != true {
			t.Fatalf("result = %v", result)
		}
		if result["withheld"] != float64(2) {
			t.Fatalf("withheld = %v", result["withheld"])
		}
	})

	t.Run("it is answered once, and then nobody learns who asked", func(t *testing.T) {
		resp := f.answer(t, present, f.presentFor(t, present, nil))
		if resp.StatusCode != http.StatusGone {
			t.Fatalf("second answer: %d", resp.StatusCode)
		}
		f.api.E.GET("/api/public/attestation-checks/" + id).Expect().Status(http.StatusGone).
			JSON().Object().Value("code").String().IsEqual(util.Errors.AttestationCheckClosed.ErrorCode)
	})

	t.Run("the asker is told", func(t *testing.T) {
		items := f.api.E.GET("/api/collections/"+util.Coll.Notifications+"/records").
			WithHeader("Authorization", f.issuerToken).
			WithQuery("filter", util.Fields.Notification.Type+"='"+util.NotificationAttestationChecked+"'").
			Expect().Status(http.StatusOK).JSON().Object().Value("items").Array()
		items.Length().IsEqual(1)
		items.Value(0).Object().Value(util.Fields.Notification.RefId).String().IsEqual(id)
	})

	t.Run("the result is the asker's alone", func(t *testing.T) {
		f.api.E.GET("/api/collections/"+util.Coll.AttestationChecks+"/records/"+id).
			WithHeader("Authorization", f.holderToken).
			Expect().Status(http.StatusNotFound)
	})
}

// Two answers racing each other: the guarded UPDATE lets exactly one land.
func TestAttestationCheckAnswersRaceForOneSlot(t *testing.T) {
	f := newCheckFixture(t)
	_, present := f.ask(t, map[string]any{"type": "membership"})
	presentation := f.presentFor(t, present, nil)

	const racers = 6
	statuses := make([]int, racers)
	var wg sync.WaitGroup
	for i := range racers {
		wg.Add(1)
		go func() {
			defer wg.Done()
			statuses[i] = f.answer(t, present, presentation).StatusCode
		}()
	}
	wg.Wait()

	ok := 0
	for _, s := range statuses {
		switch s {
		case http.StatusOK:
			ok++
		case http.StatusGone:
		default:
			t.Fatalf("unexpected status %d", s)
		}
	}
	if ok != 1 {
		t.Fatalf("%d answers landed, want exactly 1 (%v)", ok, statuses)
	}
}

func TestAttestationCheckRefusals(t *testing.T) {
	f := newCheckFixture(t)

	t.Run("the asker cannot appear as someone else's identity", func(t *testing.T) {
		resp := postJSON(t, f.baseURL+"/api/attestation-checks", f.issuerToken, map[string]any{
			"type": "membership", "identityId": f.identityID,
		})
		if resp.StatusCode != http.StatusForbidden {
			t.Fatalf("foreign identity: %d", resp.StatusCode)
		}
	})

	t.Run("a check needs an account", func(t *testing.T) {
		if resp := postJSON(t, f.baseURL+"/api/attestation-checks", "", map[string]any{}); resp.StatusCode != http.StatusUnauthorized {
			t.Fatalf("anonymous: %d", resp.StatusCode)
		}
	})

	t.Run("malformed asks are refused whole", func(t *testing.T) {
		for _, body := range []map[string]any{
			{"type": "two words"},
			{"issuers": []string{"not a domain"}},
			{"claims": []string{"9starts_with_a_digit"}},
		} {
			resp := postJSON(t, f.baseURL+"/api/attestation-checks", f.issuerToken, body)
			if resp.StatusCode != http.StatusBadRequest {
				t.Fatalf("%v: %d", body, resp.StatusCode)
			}
			if code := decode(t, resp)["code"]; code != util.Errors.AttestationCheckInvalid.ErrorCode {
				t.Fatalf("%v: code %v", body, code)
			}
		}
	})

	t.Run("a check past its time cannot be answered", func(t *testing.T) {
		id, present := f.ask(t, map[string]any{})
		_, app := testutils.SetupTestApp(t)
		past := time.Now().UTC().Add(-time.Minute).Format("2006-01-02 15:04:05.000Z")
		if _, err := app.DB().NewQuery(`UPDATE {{attestationChecks}} SET expiresAt = {:t} WHERE id = {:id}`).
			Bind(dbx.Params{"t": past, "id": id}).Execute(); err != nil {
			t.Fatal(err)
		}
		if resp := f.answer(t, present, f.presentFor(t, present, nil)); resp.StatusCode != http.StatusGone {
			t.Fatalf("expired answer: %d", resp.StatusCode)
		}
	})

	t.Run("an unknown check is not found", func(t *testing.T) {
		f.api.E.GET("/api/public/attestation-checks/nosuchcheck0000").Expect().Status(http.StatusNotFound)
	})
}
