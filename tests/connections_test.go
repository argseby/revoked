package tests

import (
	"net/http"
	"strings"
	"testing"
	"time"

	"revoked/tests/testutils"
	"revoked/util"

	"github.com/gavv/httpexpect/v2"
	"github.com/google/uuid"
	"github.com/pocketbase/dbx"
)

const toolOrigin = "https://mietunterlagen.example.com"

// pkcePair returns a verifier and its S256 challenge.
func pkcePair() (verifier, challenge string) {
	verifier = strings.Repeat("v", 20) + strings.ReplaceAll(uuid.New().String(), "-", "")
	return verifier, util.PKCEChallenge(verifier)
}

func authorizeTool(api *testutils.PBClient, token string, body map[string]any) *httpexpect.Response {
	return api.E.POST("/api/connections/authorize").
		WithHeader("Authorization", token).
		WithJSON(body).Expect()
}

// connectTool runs the whole handshake and returns the connection id and the
// tool's token.
func connectTool(t *testing.T, api *testutils.PBClient, userToken string) (connID, toolToken string) {
	t.Helper()
	verifier, challenge := pkcePair()
	redirect := toolOrigin + "/"
	grant := authorizeTool(api, userToken, map[string]any{
		"clientId": toolOrigin, "clientName": "Mietunterlagen",
		"redirectUri": redirect, "challenge": challenge,
	}).Status(http.StatusOK).JSON().Object()
	resp := api.E.POST("/api/connect/token").WithJSON(map[string]any{
		"code": grant.Value("code").String().Raw(), "verifier": verifier, "redirectUri": redirect,
	}).Expect().Status(http.StatusOK).JSON().Object()
	return resp.Value("connection").Object().Value("id").String().Raw(), resp.Value("token").String().Raw()
}

func setPermissions(api *testutils.PBClient, connID, token string, body map[string]any) *httpexpect.Response {
	return api.E.POST("/api/connections/"+connID+"/permissions").
		WithHeader("Authorization", token).WithJSON(body).Expect()
}

func toolGet(api *testutils.PBClient, toolToken string) *httpexpect.Response {
	return api.E.GET("/api/connection").WithHeader(util.ConnectionHeader, toolToken).Expect()
}

func TestConnectingATool(t *testing.T) {
	f := newWatermarkFixture(t)

	t.Run("a tool is an origin with its return address on that origin", func(t *testing.T) {
		api := f.api.T(t)
		_, challenge := pkcePair()
		for name, body := range map[string]map[string]any{
			"a path is not an origin":  {"clientId": toolOrigin + "/app", "redirectUri": toolOrigin + "/", "challenge": challenge},
			"plain http off localhost": {"clientId": "http://evil.example", "redirectUri": "http://evil.example/", "challenge": challenge},
			"return address elsewhere": {"clientId": toolOrigin, "redirectUri": "https://evil.example/", "challenge": challenge},
			"no PKCE challenge":        {"clientId": toolOrigin, "redirectUri": toolOrigin + "/", "challenge": "short"},
		} {
			authorizeTool(api, f.token, body).Status(http.StatusBadRequest).
				JSON().Object().Value("code").String().NotEmpty().Raw()
			_ = name
		}
		authorizeTool(api, "", map[string]any{
			"clientId": toolOrigin, "redirectUri": toolOrigin + "/", "challenge": challenge,
		}).Status(http.StatusUnauthorized)
	})

	t.Run("a code works once, and only with its verifier", func(t *testing.T) {
		api := f.api.T(t)
		verifier, challenge := pkcePair()
		redirect := toolOrigin + "/done"
		code := authorizeTool(api, f.token, map[string]any{
			"clientId": toolOrigin, "redirectUri": redirect, "challenge": challenge,
		}).Status(http.StatusOK).JSON().Object().Value("code").String().Raw()

		wrong, _ := pkcePair()
		api.E.POST("/api/connect/token").WithJSON(map[string]any{
			"code": code, "verifier": wrong, "redirectUri": redirect,
		}).Expect().Status(http.StatusBadRequest).
			JSON().Object().Value("code").String().IsEqual(util.Errors.ConnectionGrantInvalid.ErrorCode)
		// Spent by the wrong attempt: the right verifier no longer helps.
		api.E.POST("/api/connect/token").WithJSON(map[string]any{
			"code": code, "verifier": verifier, "redirectUri": redirect,
		}).Expect().Status(http.StatusBadRequest)
	})

	t.Run("connecting again reuses the connection", func(t *testing.T) {
		api := f.api.T(t)
		first, tokenA := connectTool(t, api, f.token)
		second, tokenB := connectTool(t, api, f.token)
		if first != second {
			t.Fatalf("a second browser made a second connection: %s vs %s", first, second)
		}
		// Both browsers stay signed in.
		toolGet(api, tokenA).Status(http.StatusOK)
		toolGet(api, tokenB).Status(http.StatusOK)
	})
}

func TestAnotherBrowserJoinsWithoutChangingTheConnection(t *testing.T) {
	f := newWatermarkFixture(t)
	_, app := testutils.SetupTestApp(t)
	api := f.api.T(t)
	redirect := toolOrigin + "/"
	reuse := func(extra map[string]any) *httpexpect.Response {
		_, challenge := pkcePair()
		body := map[string]any{
			"clientId": toolOrigin, "clientName": "Renamed",
			"redirectUri": redirect, "challenge": challenge, "reuse": true,
		}
		for k, v := range extra {
			body[k] = v
		}
		return authorizeTool(api, f.token, body)
	}

	// Nothing to reuse: the owner has to be asked.
	reuse(nil).Status(http.StatusConflict).
		JSON().Object().Value("code").String().IsEqual(util.Errors.ConnectionNotConnected.ErrorCode)

	connID, first := connectTool(t, api, f.token)
	setPermissions(api, connID, f.token, map[string]any{"allowRevoke": false, "allowHandOver": false}).
		Status(http.StatusOK)
	conn, err := app.FindRecordById(util.Coll.Connections, connID)
	if err != nil {
		t.Fatalf("find connection: %v", err)
	}
	soon := time.Now().Add(time.Hour)
	conn.Set(util.Fields.Connection.ExpiresAt, soon)
	if err := app.Save(conn); err != nil {
		t.Fatalf("shorten connection: %v", err)
	}

	// A second browser gets in, and the connection is what it was: not
	// renewed, not renamed, and allowed nothing more, whatever was asked.
	verifier, challenge := pkcePair()
	grant := authorizeTool(api, f.token, map[string]any{
		"clientId": toolOrigin, "clientName": "Renamed", "redirectUri": redirect,
		"challenge": challenge, "reuse": true, "allowRevoke": true, "allowHandOver": true,
	}).Status(http.StatusOK).JSON().Object()
	grant.Value("connectionId").String().IsEqual(connID)
	second := api.E.POST("/api/connect/token").WithJSON(map[string]any{
		"code": grant.Value("code").String().Raw(), "verifier": verifier, "redirectUri": redirect,
	}).Expect().Status(http.StatusOK).JSON().Object().Value("token").String().Raw()
	toolGet(api, first).Status(http.StatusOK)
	seen := toolGet(api, second).Status(http.StatusOK).JSON().Object()
	seen.Value("clientName").String().IsEqual("Mietunterlagen")
	seen.Value("allowRevoke").Boolean().IsFalse()
	seen.Value("allowHandOver").Boolean().IsFalse()
	at, err := time.Parse("2006-01-02 15:04:05.000Z", seen.Value("expiresAt").String().Raw())
	if err != nil {
		t.Fatalf("expiresAt: %v", err)
	}
	if at.After(soon.Add(time.Minute)) {
		t.Fatalf("joining renewed the connection until %s", at)
	}
	rows, err := app.FindAllRecords(util.Coll.AuditLogs, dbx.HashExp{
		util.Fields.AuditLog.RecordId: connID,
		util.Fields.AuditLog.Action:   "tool_browser_added",
	})
	if err != nil || len(rows) != 1 {
		t.Fatalf("tool_browser_added: %d audit rows, want 1 (%v)", len(rows), err)
	}

	// A lapsed connection is not reused either.
	conn, err = app.FindRecordById(util.Coll.Connections, connID)
	if err != nil {
		t.Fatalf("find connection: %v", err)
	}
	conn.Set(util.Fields.Connection.ExpiresAt, time.Now().Add(-time.Minute))
	if err := app.Save(conn); err != nil {
		t.Fatalf("expire connection: %v", err)
	}
	reuse(nil).Status(http.StatusConflict)
}

func TestAConnectedToolSeesOnlyWhatItIsGiven(t *testing.T) {
	f := newWatermarkFixture(t)
	connID, toolToken := connectTool(t, f.api, f.token)

	t.Run("it sees where its links stand, and the URL only when handed over", func(t *testing.T) {
		api := f.api.T(t)
		kept, _ := f.share(t, map[string]any{
			util.Fields.Link.Connection: connID, util.Fields.Link.Ref: "flat-1",
		})
		// Handing a link over needs the owner's say-so for this tool.
		api.Create(util.Coll.Links, f.token, map[string]any{
			util.Fields.Link.Slug:       "x-" + uuid.New().String()[:8],
			util.Fields.Link.Status:     util.StatusActive,
			util.Fields.Link.User:       f.userID,
			util.Fields.Link.Workspace:  f.wsID,
			util.Fields.Link.Connection: connID,
			util.Fields.Link.HandedOver: true,
		}).Expect().Status(http.StatusBadRequest)
		setPermissions(api, connID, f.token, map[string]any{"allowHandOver": true}).Status(http.StatusOK)
		handed, _ := f.share(t, map[string]any{
			util.Fields.Link.Connection: connID, util.Fields.Link.Ref: "flat-2",
			util.Fields.Link.HandedOver: true,
		})
		f.share(t, nil) // not from this tool

		seen := toolGet(api, toolToken).Status(http.StatusOK).JSON().Object()
		// A tool keeps nothing here: there is no store to read or write.
		seen.NotContainsKey("storage")
		api.E.PUT("/api/connection/storage").WithHeader(util.ConnectionHeader, toolToken).
			WithJSON(map[string]any{"flats": []string{"Musterstr. 5"}}).
			Expect().Status(http.StatusNotFound)
		links := seen.Value("links").Array()
		links.Length().IsEqual(2)
		for _, l := range links.Iter() {
			o := l.Object()
			o.NotContainsKey("slug")
			o.NotContainsKey("records")
			switch o.Value("ref").String().Raw() {
			case "flat-1":
				o.NotContainsKey("url")
			case "flat-2":
				o.Value("url").String().HasSuffix("/s/" + handed)
			}
		}
		_ = kept

		// Taken away again, the tool no longer gets the URL it was given.
		setPermissions(api, connID, f.token, map[string]any{"allowHandOver": false}).Status(http.StatusOK)
		for _, l := range toolGet(api, toolToken).Status(http.StatusOK).JSON().Object().Value("links").Array().Iter() {
			l.Object().NotContainsKey("url")
		}
	})

	t.Run("its token opens nothing in the vault", func(t *testing.T) {
		api := f.api.T(t)
		for _, coll := range []string{util.Coll.Records, util.Coll.Links, util.Coll.Sections, util.Coll.Connections} {
			api.E.GET("/api/collections/"+coll+"/records").
				WithHeader(util.ConnectionHeader, toolToken).
				Expect().JSON().Object().Value("items").Array().IsEmpty()
		}
	})

	t.Run("a link cannot be attached to someone else's tool, or to a tool later", func(t *testing.T) {
		api := f.api.T(t)
		other := newWatermarkFixture(t)
		api.Create(util.Coll.Links, other.token, map[string]any{
			util.Fields.Link.Slug:       "x-" + uuid.New().String()[:8],
			util.Fields.Link.Status:     util.StatusActive,
			util.Fields.Link.User:       other.userID,
			util.Fields.Link.Workspace:  other.wsID,
			util.Fields.Link.Connection: connID,
		}).Expect().Status(http.StatusBadRequest)

		_, id := f.share(t, nil)
		api.Update(util.Coll.Links, id, f.token, map[string]any{
			util.Fields.Link.Connection: connID,
		}).Expect().Status(http.StatusBadRequest)
	})

	t.Run("the owner sees the connection; nobody else does", func(t *testing.T) {
		api := f.api.T(t)
		api.List(util.Coll.Connections, f.token).Expect().Status(http.StatusOK).
			JSON().Object().Value("items").Array().Length().IsEqual(1)
		stranger := newWatermarkFixture(t)
		api.Get(util.Coll.Connections, connID, stranger.token).Expect().Status(http.StatusNotFound)
	})

	t.Run("disconnecting ends the token and keeps the owner's links", func(t *testing.T) {
		api := f.api.T(t)
		_, id := f.share(t, map[string]any{util.Fields.Link.Connection: connID})
		api.E.DELETE("/api/connection").WithHeader(util.ConnectionHeader, toolToken).
			Expect().Status(http.StatusNoContent)
		toolGet(api, toolToken).Status(http.StatusUnauthorized)
		api.Get(util.Coll.Links, id, f.token).Expect().Status(http.StatusOK).
			JSON().Object().Value(util.Fields.Link.Connection).String().IsEmpty()
	})
}

func TestAConnectionExpiresUntilTheOwnerRenewsIt(t *testing.T) {
	f := newWatermarkFixture(t)
	_, app := testutils.SetupTestApp(t)
	api := f.api.T(t)
	connID, toolToken := connectTool(t, api, f.token)

	expires := toolGet(api, toolToken).Status(http.StatusOK).JSON().Object().Value("expiresAt").String().Raw()
	at, err := time.Parse("2006-01-02 15:04:05.000Z", expires)
	if err != nil {
		t.Fatalf("expiresAt %q: %v", expires, err)
	}
	if left := time.Until(at); left < util.ConnectionTTL-time.Hour || left > util.ConnectionTTL {
		t.Fatalf("a fresh connection expires in %s, want about %s", left, util.ConnectionTTL)
	}

	conn, err := app.FindRecordById(util.Coll.Connections, connID)
	if err != nil {
		t.Fatalf("find connection: %v", err)
	}
	conn.Set(util.Fields.Connection.ExpiresAt, time.Now().Add(-time.Minute))
	if err := app.Save(conn); err != nil {
		t.Fatalf("expire connection: %v", err)
	}

	toolGet(api, toolToken).Status(http.StatusUnauthorized).
		JSON().Object().Value("code").String().IsEqual(util.Errors.ConnectionExpired.ErrorCode)
	api.E.DELETE("/api/connection").WithHeader(util.ConnectionHeader, toolToken).
		Expect().Status(http.StatusUnauthorized)

	// No new link joins a lapsed connection.
	api.Create(util.Coll.Links, f.token, map[string]any{
		util.Fields.Link.Slug:       "x-" + uuid.New().String()[:8],
		util.Fields.Link.Status:     util.StatusActive,
		util.Fields.Link.User:       f.userID,
		util.Fields.Link.Workspace:  f.wsID,
		util.Fields.Link.Connection: connID,
	}).Expect().Status(http.StatusBadRequest)

	// The owner connecting it again renews the same connection for the browser
	// that came back — not for the token that lapsed.
	renewed, fresh := connectTool(t, api, f.token)
	if renewed != connID {
		t.Fatalf("renewing made a second connection: %s vs %s", renewed, connID)
	}
	toolGet(api, fresh).Status(http.StatusOK)
	toolGet(api, toolToken).Status(http.StatusUnauthorized)
}

func TestWhatAToolDoesIsAudited(t *testing.T) {
	f := newWatermarkFixture(t)
	_, app := testutils.SetupTestApp(t)
	api := f.api.T(t)
	connID, toolToken := connectTool(t, api, f.token)

	// Polling is one entry per stretch of use, not one per request.
	toolGet(api, toolToken).Status(http.StatusOK)
	toolGet(api, toolToken).Status(http.StatusOK)
	api.E.DELETE("/api/connection").WithHeader(util.ConnectionHeader, toolToken).
		Expect().Status(http.StatusNoContent)

	rows, err := app.FindAllRecords(util.Coll.AuditLogs, dbx.HashExp{
		util.Fields.AuditLog.Collection: util.Coll.Connections,
		util.Fields.AuditLog.RecordId:   connID,
	})
	if err != nil {
		t.Fatalf("list audit rows: %v", err)
	}
	got := map[string]int{}
	for _, r := range rows {
		got[r.GetString(util.Fields.AuditLog.Action)]++
		if r.GetString(util.Fields.AuditLog.User) != f.userID ||
			r.GetString(util.Fields.AuditLog.Workspace) != f.wsID {
			t.Errorf("audit row %s is not filed under the owner", r.Id)
		}
		if !strings.Contains(r.GetString(util.Fields.AuditLog.NewData), toolOrigin) {
			t.Errorf("audit row %s does not name the tool", r.Id)
		}
	}
	for _, action := range []string{"tool_authorized", "tool_connected", "tool_read", "tool_disconnected"} {
		if got[action] != 1 {
			t.Errorf("%s: %d audit rows, want 1 (all: %v)", action, got[action], got)
		}
	}
}

func TestAToolRevokesItsLinksOnlyWhenAllowed(t *testing.T) {
	f := newWatermarkFixture(t)
	_, app := testutils.SetupTestApp(t)
	api := f.api.T(t)
	connID, toolToken := connectTool(t, api, f.token)
	_, mine := f.share(t, map[string]any{util.Fields.Link.Connection: connID, util.Fields.Link.Ref: "flat-1"})
	_, foreign := f.share(t, nil)

	revoke := func(id string) *httpexpect.Response {
		return api.E.POST("/api/connection/links/"+id+"/revoke").
			WithHeader(util.ConnectionHeader, toolToken).Expect()
	}

	// Not unless the owner said so.
	toolGet(api, toolToken).Status(http.StatusOK).JSON().Object().Value("allowRevoke").Boolean().IsFalse()
	revoke(mine).Status(http.StatusForbidden).
		JSON().Object().Value("code").String().IsEqual(util.Errors.ConnectionRevokeNotAllowed.ErrorCode)

	// Only the owner changes that.
	stranger := newWatermarkFixture(t)
	allow := func(token string, on bool) *httpexpect.Response {
		return setPermissions(api, connID, token, map[string]any{"allowRevoke": on})
	}
	allow(stranger.token, true).Status(http.StatusNotFound)
	allow(f.token, true).Status(http.StatusOK)
	toolGet(api, toolToken).Status(http.StatusOK).JSON().Object().Value("allowRevoke").Boolean().IsTrue()

	// Its own link, and no other.
	revoke(foreign).Status(http.StatusNotFound)
	revoke(mine).Status(http.StatusOK).JSON().Object().Value("status").String().IsEqual(util.StatusRevoked)
	revoke(mine).Status(http.StatusOK)
	api.Get(util.Coll.Links, mine, f.token).Expect().Status(http.StatusOK).
		JSON().Object().Value(util.Fields.Link.Status).String().IsEqual(util.StatusRevoked)
	api.Get(util.Coll.Links, foreign, f.token).Expect().Status(http.StatusOK).
		JSON().Object().Value(util.Fields.Link.Status).String().IsEqual(util.StatusActive)

	rows, err := app.FindAllRecords(util.Coll.AuditLogs, dbx.HashExp{
		util.Fields.AuditLog.Collection: util.Coll.Connections,
		util.Fields.AuditLog.RecordId:   connID,
		util.Fields.AuditLog.Action:     "tool_revoked_link",
	})
	if err != nil || len(rows) != 1 || !strings.Contains(rows[0].GetString(util.Fields.AuditLog.NewData), mine) {
		t.Fatalf("want one audit row naming the revoked link, got %d (%v)", len(rows), err)
	}

	// Taken away again, it stops at once.
	allow(f.token, false).Status(http.StatusOK)
	_, next := f.share(t, map[string]any{util.Fields.Link.Connection: connID})
	revoke(next).Status(http.StatusForbidden)

	// Connecting again with the permission ticked grants it.
	verifier, challenge := pkcePair()
	grant := authorizeTool(api, f.token, map[string]any{
		"clientId": toolOrigin, "redirectUri": toolOrigin + "/", "challenge": challenge, "allowRevoke": true,
	}).Status(http.StatusOK).JSON().Object()
	_ = verifier
	_ = grant
	revoke(next).Status(http.StatusOK)
}

func TestAToolCollectsItsAnswerItself(t *testing.T) {
	f := newWatermarkFixture(t)
	_, app := testutils.SetupTestApp(t)
	api := f.api.T(t)
	redirect := toolOrigin + "/"
	poll := func(verifier, origin string) *httpexpect.Response {
		req := api.E.POST("/api/connect/token").WithJSON(map[string]any{
			"verifier": verifier, "redirectUri": redirect,
		})
		if origin != "" {
			req = req.WithHeader("Origin", origin)
		}
		return req.Expect()
	}
	authorize := func(challenge string, extra map[string]any) *httpexpect.Response {
		body := map[string]any{
			"clientId": toolOrigin, "clientName": "Mietunterlagen",
			"redirectUri": redirect, "challenge": challenge,
		}
		for k, v := range extra {
			body[k] = v
		}
		return authorizeTool(api, f.token, body)
	}

	// Until the owner answers there is nothing to collect, and asking again
	// costs nothing.
	verifier, challenge := pkcePair()
	poll(verifier, toolOrigin).Status(http.StatusAccepted).
		JSON().Object().Value("pending").Boolean().IsTrue()
	poll("short", toolOrigin).Status(http.StatusBadRequest)

	// An answer handed out as a code is not there for the taking: only the
	// browser the app opened holds the code.
	authorize(challenge, nil).Status(http.StatusOK)
	poll(verifier, toolOrigin).Status(http.StatusAccepted)

	// Left for the page that asked, it goes to that page's verifier, once.
	verifier, challenge = pkcePair()
	grant := authorize(challenge, map[string]any{"poll": true}).Status(http.StatusOK).JSON().Object()
	connID := grant.Value("connectionId").String().Raw()
	token := poll(verifier, toolOrigin).Status(http.StatusOK).
		JSON().Object().Value("token").String().NotEmpty().Raw()
	toolGet(api, token).Status(http.StatusOK).JSON().Object().Value("id").String().IsEqual(connID)
	poll(verifier, toolOrigin).Status(http.StatusAccepted)

	// Another browser joins the same way, the connection as it was.
	verifier, challenge = pkcePair()
	authorize(challenge, map[string]any{"poll": true, "reuse": true}).Status(http.StatusOK).
		JSON().Object().Value("connectionId").String().IsEqual(connID)
	second := poll(verifier, toolOrigin).Status(http.StatusOK).
		JSON().Object().Value("token").String().Raw()
	if second == token {
		t.Fatal("the second browser was given the first one's token")
	}
	toolGet(api, token).Status(http.StatusOK)
	toolGet(api, second).Status(http.StatusOK)

	// A page anywhere else does not collect it, and its attempt spends it.
	for name, origin := range map[string]string{
		"another origin": "https://evil.example",
		"no origin":      "",
	} {
		verifier, challenge = pkcePair()
		authorize(challenge, map[string]any{"poll": true}).Status(http.StatusOK)
		poll(verifier, origin).Status(http.StatusBadRequest).
			JSON().Object().Value("code").String().IsEqual(util.Errors.ConnectionGrantInvalid.ErrorCode)
		poll(verifier, toolOrigin).Status(http.StatusAccepted)
		_ = name
	}

	// Nor does an answer wait forever.
	verifier, challenge = pkcePair()
	authorize(challenge, map[string]any{"poll": true}).Status(http.StatusOK)
	row, err := app.FindFirstRecordByFilter(util.Coll.ConnectionTokens,
		"codeChallenge = {:challenge}", dbx.Params{"challenge": challenge})
	if err != nil {
		t.Fatalf("find the waiting answer: %v", err)
	}
	row.Set(util.Fields.ConnectionToken.CodeExpiresAt, time.Now().Add(-time.Minute))
	if err := app.Save(row); err != nil {
		t.Fatalf("expire the answer: %v", err)
	}
	poll(verifier, toolOrigin).Status(http.StatusBadRequest)

	rows, err := app.FindAllRecords(util.Coll.AuditLogs, dbx.HashExp{
		util.Fields.AuditLog.RecordId: connID,
		util.Fields.AuditLog.Action:   "tool_connected",
	})
	if err != nil || len(rows) != 2 {
		t.Fatalf("tool_connected: %d audit rows, want 2 (%v)", len(rows), err)
	}
}
