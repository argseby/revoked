package tests

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"net/http"
	"testing"

	"revoked/cmd/revoked/services"
	"revoked/tests/testutils"
	"revoked/util"
)

const gameOrigin = "https://game.example"

// A subject issued before versions existed has to stay what it was, or every
// existing person becomes a stranger at every service they use.
func TestSubjectVersionZeroIsTheSubjectAlreadyIssued(t *testing.T) {
	secret := []byte("secret")
	mac := hmac.New(sha256.New, secret)
	mac.Write([]byte(gameOrigin + "\x00user1"))
	issued := base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
	if got := util.PairwiseSubject(secret, "user1", gameOrigin, 0); got != issued {
		t.Fatalf("version 0 = %s, want %s", got, issued)
	}
	if util.PairwiseSubject(secret, "user1", gameOrigin, 1) == issued {
		t.Fatal("a new version kept the subject")
	}
}

// signedInService is a person signed in to a service, sharing one entry.
type signedInService struct {
	baseURL  string
	api      *testutils.PBClient
	person   *oidcPerson
	recordID string
	rowID    string
	sub      string
	access   string
	grant    map[string]any
}

func signInAndShare(t *testing.T, baseURL string) *signedInService {
	t.Helper()
	api := testutils.NewPBClient(t, baseURL)
	person := newOIDCPerson(t, baseURL)
	recordID := extractID(t, baseURL, util.Coll.Records, person.token, map[string]any{
		util.Fields.Record.Key:       "shipping_address",
		util.Fields.Record.Value:     "1 Infinite Loop",
		util.Fields.Record.Label:     "Shipping address",
		util.Fields.Record.Type:      util.TypeText,
		util.Fields.Record.Format:    util.FormatDefault,
		util.Fields.Record.User:      person.userID,
		util.Fields.Record.Workspace: activeWorkspaceOf(t, api, person.userID, person.token),
	})
	s := &signedInService{baseURL: baseURL, api: api, person: person, recordID: recordID}
	s.sub, s.access, s.grant = s.signIn(t, true)
	items := api.List(util.Coll.SignIns, person.token).Expect().Status(http.StatusOK).
		JSON().Object().Value("items").Array().Raw()
	s.rowID = items[0].(map[string]any)["id"].(string)
	return s
}

// signIn approves and redeems a sign-in. It returns the subject, the access
// token and the grant the service was given, if any.
func (s *signedInService) signIn(t *testing.T, share bool) (sub, access string, grant map[string]any) {
	t.Helper()
	game := newOIDCService(t, s.baseURL, gameOrigin)
	decision := map[string]any{
		"approve": true,
		"scopes":  []string{util.OIDCScopeProfile},
		"name":    map[string]string{"kind": services.NameFromIdentity, "id": s.person.identityID},
	}
	if share {
		decision["links"] = map[string]string{"shipping_address": s.recordID}
	}
	_, location := s.person.approve(t, game.params(map[string]string{
		"claims": `{"userinfo":{"revoked_links":{"values":["shipping_address"]}}}`,
	}), decision)
	resp, tokens := game.redeem(redirectParams(t, location).Get("code"))
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("token: %d %v", resp.StatusCode, tokens)
	}
	access = tokens["access_token"].(string)
	status, info := userinfo(t, s.baseURL, access)
	if status != http.StatusOK {
		t.Fatalf("userinfo: %d %v", status, info)
	}
	if links, ok := info[util.OIDCClaimLinks].(map[string]any); ok {
		grant = links["grants"].([]any)[0].(map[string]any)
	}
	return info["sub"].(string), access, grant
}

func (s *signedInService) control(t *testing.T, action string, body any) (int, map[string]any) {
	t.Helper()
	if body == nil {
		body = map[string]any{}
	}
	return s.person.post(t, "/api/sign-ins/"+s.rowID+"/"+action, body)
}

func (s *signedInService) mustControl(t *testing.T, action string, body any) {
	t.Helper()
	if status, out := s.control(t, action, body); status != http.StatusOK {
		t.Fatalf("%s: %d %v", action, status, out)
	}
}

func (s *signedInService) readGrant(t *testing.T, grant map[string]any) map[string]any {
	t.Helper()
	return s.api.T(t).E.POST("/api/grants/resolve").
		WithJSON(map[string]any{"grants": []map[string]any{{"id": grant["id"], "token": grant["token"]}}}).
		Expect().Status(http.StatusOK).JSON().Object().Value("items").Array().Value(0).Object().Raw()
}

func (s *signedInService) refused(t *testing.T, access string) {
	t.Helper()
	if status, info := userinfo(t, s.baseURL, access); status != http.StatusUnauthorized {
		t.Fatalf("userinfo still answers: %d %v", status, info)
	}
}

func TestPausingAService(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)

	t.Run("stops sign-ins and reads until activated, then nothing has changed", func(t *testing.T) {
		s := signInAndShare(t, baseURL)
		s.mustControl(t, "pause", nil)

		s.refused(t, s.access)
		if r := s.readGrant(t, s.grant); r["status"] != util.StatusPaused || r["values"] != nil {
			t.Fatalf("grant while paused: %v", r)
		}
		game := newOIDCService(t, baseURL, gameOrigin)
		status, opened := s.person.open(t, game.params(nil))
		if status != http.StatusOK || opened["ticket"] != nil || opened["paused"] != s.rowID {
			t.Fatalf("open while paused: %d %v", status, opened)
		}
		answer := redirectParams(t, opened["redirect"].(string))
		if answer.Get("error") != "access_denied" || answer.Get("error_description") != "The person declined." {
			t.Fatalf("the service can tell a pause from a no: %v", answer)
		}

		s.mustControl(t, "resume", nil)
		status, info := userinfo(t, baseURL, s.access)
		if status != http.StatusOK || info["sub"] != s.sub {
			t.Fatalf("after activating: %d %v", status, info)
		}
		if r := s.readGrant(t, s.grant); r["status"] != util.StatusActive {
			t.Fatalf("grant after activating: %v", r)
		}
	})

	t.Run("a sign-in already under way can't finish", func(t *testing.T) {
		s := signInAndShare(t, baseURL)
		opening := newOIDCService(t, baseURL, gameOrigin)
		_, consent := s.person.open(t, opening.params(nil))
		redeeming := newOIDCService(t, baseURL, gameOrigin)
		_, location := s.person.approve(t, redeeming.params(nil), map[string]any{"approve": true})

		s.mustControl(t, "pause", nil)

		status, out := s.person.decide(t, consent["ticket"].(string), map[string]any{"approve": true})
		if status != http.StatusConflict || out["code"] != util.Errors.OIDCSignInPaused.ErrorCode {
			t.Fatalf("approval while paused: %d %v", status, out)
		}
		if resp, out := redeeming.redeem(redirectParams(t, location).Get("code")); resp.StatusCode != http.StatusBadRequest {
			t.Fatalf("code while paused: %d %v", resp.StatusCode, out)
		}
	})

	t.Run("activating leaves a link the owner paused themselves", func(t *testing.T) {
		s := signInAndShare(t, baseURL)
		id := s.grant["id"].(string)
		s.api.T(t).Update(util.Coll.Links, id, s.person.token, map[string]any{
			util.Fields.Link.Status: util.StatusPaused,
		}).Expect().Status(http.StatusOK)
		s.mustControl(t, "pause", nil)
		s.mustControl(t, "resume", nil)
		if r := s.readGrant(t, s.grant); r["status"] != util.StatusPaused {
			t.Fatalf("grant = %v", r)
		}
	})

	t.Run("the owner's own decision about the link wins over the hold", func(t *testing.T) {
		s := signInAndShare(t, baseURL)
		id := s.grant["id"].(string)
		api := s.api.T(t)
		s.mustControl(t, "pause", nil)
		// Activated, then paused again by hand: no longer the service's to release.
		for _, status := range []string{util.StatusActive, util.StatusPaused} {
			api.Update(util.Coll.Links, id, s.person.token, map[string]any{util.Fields.Link.Status: status}).
				Expect().Status(http.StatusOK)
		}
		s.mustControl(t, "resume", nil)
		if r := s.readGrant(t, s.grant); r["status"] != util.StatusPaused {
			t.Fatalf("grant = %v", r)
		}
		api.Update(util.Coll.Links, id, s.person.token, map[string]any{util.Fields.Link.HeldPaused: true}).
			Expect().Status(http.StatusBadRequest)
	})
}

func TestDisconnectingAService(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)

	t.Run("it is the person's alone", func(t *testing.T) {
		s := signInAndShare(t, baseURL)
		stranger := newOIDCPerson(t, baseURL)
		for _, action := range []string{"pause", "resume", "disconnect"} {
			if status, _ := stranger.post(t, "/api/sign-ins/"+s.rowID+"/"+action, map[string]any{}); status != http.StatusNotFound {
				t.Fatalf("%s by a stranger: %d", action, status)
			}
			resp := postJSON(t, baseURL+"/api/sign-ins/"+s.rowID+"/"+action, "", map[string]any{})
			resp.Body.Close()
			if resp.StatusCode != http.StatusUnauthorized {
				t.Fatalf("%s without a session: %d", action, resp.StatusCode)
			}
		}
	})

	t.Run("keeping the ID: cut off now, and known again on return", func(t *testing.T) {
		s := signInAndShare(t, baseURL)
		s.mustControl(t, "disconnect", map[string]any{"newId": false})

		s.refused(t, s.access)
		if r := s.readGrant(t, s.grant); r["status"] != util.StatusRevoked {
			t.Fatalf("grant = %v", r)
		}
		row := s.api.T(t).Get(util.Coll.SignIns, s.rowID, s.person.token).Expect().Status(http.StatusOK).JSON().Object()
		row.Value(util.Fields.SignIn.Status).String().IsEqual(util.StatusDisconnected)

		game := newOIDCService(t, baseURL, gameOrigin)
		_, opened := s.person.open(t, game.params(nil))
		back := opened["disconnected"].(map[string]any)
		if back["newId"] != false || back["at"] == "" {
			t.Fatalf("consent = %v", opened)
		}

		sub, _, _ := s.signIn(t, false)
		if sub != s.sub {
			t.Fatal("the subject changed without being asked to")
		}
		s.refused(t, s.access)
		row = s.api.T(t).Get(util.Coll.SignIns, s.rowID, s.person.token).Expect().Status(http.StatusOK).JSON().Object()
		row.Value(util.Fields.SignIn.Status).String().IsEqual(util.StatusActive)
	})

	t.Run("a code from before can't be redeemed afterwards", func(t *testing.T) {
		s := signInAndShare(t, baseURL)
		game := newOIDCService(t, baseURL, gameOrigin)
		_, location := s.person.approve(t, game.params(nil), map[string]any{"approve": true})
		s.mustControl(t, "disconnect", map[string]any{"newId": true})
		s.signIn(t, false)
		if resp, out := game.redeem(redirectParams(t, location).Get("code")); resp.StatusCode != http.StatusBadRequest {
			t.Fatalf("old code: %d %v", resp.StatusCode, out)
		}
	})

	t.Run("a new ID leaves nothing that ties the return to before", func(t *testing.T) {
		s := signInAndShare(t, baseURL)
		s.mustControl(t, "disconnect", map[string]any{"newId": true})

		game := newOIDCService(t, baseURL, gameOrigin)
		_, opened := s.person.open(t, game.params(nil))
		if back := opened["disconnected"].(map[string]any); back["newId"] != true {
			t.Fatalf("consent = %v", opened)
		}
		if opened["nameSelected"] != nil {
			t.Fatalf("the old name is offered again: %v", opened["nameSelected"])
		}

		sub, access, grant := s.signIn(t, true)
		if sub == s.sub {
			t.Fatal("the subject did not change")
		}
		if grant == nil || grant["id"] == s.grant["id"] {
			t.Fatalf("the grant keeps its id: %v then %v", s.grant, grant)
		}
		// The token from before must not read the subject the person came back
		// under: that would hand the service both IDs.
		s.refused(t, s.access)
		if status, info := userinfo(t, baseURL, access); status != http.StatusOK || info["sub"] != sub {
			t.Fatalf("new token: %d %v", status, info)
		}
		if r := s.readGrant(t, s.grant); r["status"] != util.StatusRevoked {
			t.Fatalf("old grant = %v", r)
		}
		if r := s.readGrant(t, grant); r["status"] != util.StatusActive {
			t.Fatalf("new grant = %v", r)
		}

		// From here it is the new ID that stays.
		if again, _, _ := s.signIn(t, false); again != sub {
			t.Fatal("the new subject did not stay")
		}
	})

	t.Run("a new ID can be chosen later and never taken back", func(t *testing.T) {
		s := signInAndShare(t, baseURL)
		s.mustControl(t, "disconnect", map[string]any{"newId": false})
		s.mustControl(t, "disconnect", map[string]any{"newId": true})
		s.mustControl(t, "disconnect", map[string]any{"newId": false})
		row := s.api.T(t).Get(util.Coll.SignIns, s.rowID, s.person.token).Expect().Status(http.StatusOK).JSON().Object()
		row.Value(util.Fields.SignIn.NewIdOnReturn).Boolean().IsTrue()
		row.Value(util.Fields.SignIn.SubjectVersion).Number().IsEqual(1)
		if sub, _, _ := s.signIn(t, false); sub == s.sub {
			t.Fatal("the new ID was taken back")
		}
	})

	t.Run("a paused service can be disconnected and can't be paused afterwards", func(t *testing.T) {
		s := signInAndShare(t, baseURL)
		s.mustControl(t, "pause", nil)
		s.mustControl(t, "disconnect", nil)
		if r := s.readGrant(t, s.grant); r["status"] != util.StatusRevoked {
			t.Fatalf("grant = %v", r)
		}
		s.mustControl(t, "pause", nil)
		s.mustControl(t, "resume", nil)
		s.api.T(t).Get(util.Coll.SignIns, s.rowID, s.person.token).Expect().Status(http.StatusOK).JSON().Object().
			Value(util.Fields.SignIn.Status).String().IsEqual(util.StatusDisconnected)
	})
}

func TestPausingATool(t *testing.T) {
	f := newWatermarkFixture(t)
	api := f.api.T(t)
	connID, toolToken := connectTool(t, api, f.token)
	control := func(action string, body any) {
		t.Helper()
		api.E.POST("/api/connections/"+connID+"/"+action).WithHeader("Authorization", f.token).
			WithJSON(body).Expect().Status(http.StatusOK)
	}
	_, held := f.share(t, map[string]any{util.Fields.Link.Connection: connID})
	_, ownPause := f.share(t, map[string]any{util.Fields.Link.Connection: connID, util.Fields.Link.Status: util.StatusPaused})
	status := func(id string) string {
		return api.Get(util.Coll.Links, id, f.token).Expect().Status(http.StatusOK).JSON().Object().
			Value(util.Fields.Link.Status).String().Raw()
	}

	verifier, challenge := pkcePair()
	pending := authorizeTool(api, f.token, map[string]any{
		"clientId": toolOrigin, "redirectUri": toolOrigin + "/", "challenge": challenge,
	}).Status(http.StatusOK).JSON().Object().Value("code").String().Raw()

	control("pause", map[string]any{})

	t.Run("its token is refused but not forgotten", func(t *testing.T) {
		toolGet(api, toolToken).Status(http.StatusForbidden).JSON().Object().
			Value("code").String().IsEqual(util.Errors.ConnectionPaused.ErrorCode)
	})
	t.Run("its links are paused", func(t *testing.T) {
		if got := status(held); got != util.StatusPaused {
			t.Fatalf("link = %s", got)
		}
	})
	t.Run("it can't get back in or add links", func(t *testing.T) {
		_, challenge := pkcePair()
		for _, reuse := range []bool{false, true} {
			authorizeTool(api, f.token, map[string]any{
				"clientId": toolOrigin, "redirectUri": toolOrigin + "/", "challenge": challenge, "reuse": reuse,
			}).Status(http.StatusConflict).JSON().Object().
				Value("code").String().IsEqual(util.Errors.ConnectionPaused.ErrorCode)
		}
		api.E.POST("/api/connect/token").WithJSON(map[string]any{
			"code": pending, "verifier": verifier, "redirectUri": toolOrigin + "/",
		}).Expect().Status(http.StatusBadRequest)
		api.Create(util.Coll.Links, f.token, map[string]any{
			util.Fields.Link.Slug:       "paused-tool-link",
			util.Fields.Link.User:       f.userID,
			util.Fields.Link.Workspace:  f.wsID,
			util.Fields.Link.Records:    []string{f.pngID},
			util.Fields.Link.Connection: connID,
		}).Expect().Status(http.StatusBadRequest)
	})

	control("resume", map[string]any{})

	t.Run("activating restores only what the pause held", func(t *testing.T) {
		toolGet(api, toolToken).Status(http.StatusOK)
		if got := status(held); got != util.StatusActive {
			t.Fatalf("held link = %s", got)
		}
		if got := status(ownPause); got != util.StatusPaused {
			t.Fatalf("the owner's paused link = %s", got)
		}
	})
}

func TestDisconnectingATool(t *testing.T) {
	f := newWatermarkFixture(t)
	api := f.api.T(t)
	disconnect := func(connID string, body any) {
		t.Helper()
		api.E.POST("/api/connections/"+connID+"/disconnect").WithHeader("Authorization", f.token).
			WithJSON(body).Expect().Status(http.StatusNoContent)
	}
	status := func(id string) string {
		return api.Get(util.Coll.Links, id, f.token).Expect().Status(http.StatusOK).JSON().Object().
			Value(util.Fields.Link.Status).String().Raw()
	}

	t.Run("only by its owner", func(t *testing.T) {
		connID, toolToken := connectTool(t, api, f.token)
		baseURL, _ := testutils.SetupTestApp(t)
		_, stranger, err := testutils.CreateRandomUser(baseURL)
		if err != nil {
			t.Fatal(err)
		}
		api.E.POST("/api/connections/"+connID+"/disconnect").WithHeader("Authorization", stranger).
			WithJSON(map[string]any{}).Expect().Status(http.StatusNotFound)
		toolGet(api, toolToken).Status(http.StatusOK)
		disconnect(connID, map[string]any{})
	})

	t.Run("its links keep working unless the owner revokes them", func(t *testing.T) {
		connID, toolToken := connectTool(t, api, f.token)
		_, link := f.share(t, map[string]any{util.Fields.Link.Connection: connID})
		disconnect(connID, map[string]any{})
		toolGet(api, toolToken).Status(http.StatusUnauthorized)
		if got := status(link); got != util.StatusActive {
			t.Fatalf("link = %s", got)
		}
	})

	t.Run("revoking its links takes them all", func(t *testing.T) {
		connID, _ := connectTool(t, api, f.token)
		_, link := f.share(t, map[string]any{util.Fields.Link.Connection: connID})
		disconnect(connID, map[string]any{"revokeLinks": true})
		if got := status(link); got != util.StatusRevoked {
			t.Fatalf("link = %s", got)
		}
	})

	t.Run("a link held by a pause stays paused", func(t *testing.T) {
		connID, _ := connectTool(t, api, f.token)
		_, link := f.share(t, map[string]any{util.Fields.Link.Connection: connID})
		api.E.POST("/api/connections/"+connID+"/pause").WithHeader("Authorization", f.token).
			WithJSON(map[string]any{}).Expect().Status(http.StatusOK)
		disconnect(connID, map[string]any{})
		if got := status(link); got != util.StatusPaused {
			t.Fatalf("link = %s", got)
		}
	})
}
