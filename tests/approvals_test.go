package tests

import (
	"net/http"
	"net/url"
	"strings"
	"testing"

	"revoked/tests/testutils"
	"revoked/util"
)

// browserPerson is someone with no app: an account and the passkey on their
// device, nothing more.
type browserPerson struct {
	baseURL, userID, token string
	device                 *testutils.PasskeyDevice
}

func newBrowserPerson(t *testing.T, baseURL string) *browserPerson {
	t.Helper()
	userID, token, device, err := testutils.CreateRandomUserWithDevice(baseURL)
	if err != nil {
		t.Fatal(err)
	}
	return &browserPerson{baseURL: baseURL, userID: userID, token: token, device: device}
}

func (p *browserPerson) open(t *testing.T, q url.Values) map[string]any {
	t.Helper()
	params := map[string]string{}
	for k := range q {
		params[k] = q.Get(k)
	}
	resp := postJSON(t, p.baseURL+"/oidc/authorize/app", p.token, map[string]any{"params": params})
	out := decode(t, resp)
	if resp.StatusCode != http.StatusOK || out["ticket"] == nil {
		t.Fatalf("open: %d %v", resp.StatusCode, out)
	}
	return out
}

func (p *browserPerson) consent(t *testing.T, body map[string]any) (int, map[string]any) {
	t.Helper()
	resp := postJSON(t, p.baseURL+"/oidc/authorize/consent", p.token, body)
	return resp.StatusCode, decode(t, resp)
}

// The browser approves a sign-in with a passkey approval bound to the ticket
// (BROWSER.md §4.5, §4.7). The service gets the same code and token it gets
// from the app, without the identity claim, which stands for a device key.
func TestSignInApprovedInTheBrowser(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	svc := newOIDCService(t, baseURL, "https://game.example")
	person := newBrowserPerson(t, baseURL)

	consent := person.open(t, svc.params(nil))
	ticket := consent["ticket"].(string)
	approval, err := person.device.Approve(person.token, "signin", ticket)
	if err != nil {
		t.Fatalf("approve: %v", err)
	}
	status, out := person.consent(t, map[string]any{
		"ticket": ticket, "approve": true, "approval": approval,
		"scopes": []string{util.OIDCScopeEmail, util.OIDCScopeIdentity},
	})
	if status != http.StatusOK {
		t.Fatalf("consent: %d %v", status, out)
	}
	p := redirectParams(t, out["redirect"].(string))
	if p.Get("state") != "st-123" || p.Get("code") == "" {
		t.Fatalf("redirect = %v", out["redirect"])
	}
	resp, tokens := svc.redeem(p.Get("code"))
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("token: %d %v", resp.StatusCode, tokens)
	}
	if tokens["scope"] != "openid email" {
		t.Fatalf("a passkey approval granted %v", tokens["scope"])
	}
	claims := verifyIDToken(t, baseURL, tokens["id_token"].(string))
	if _, leaked := claims[util.OIDCScopeIdentity]; leaked {
		t.Fatal("the identity claim was granted without the device key")
	}
}

// An approval proof is bound to one ticket and one purpose under a
// domain-separated prefix (BROWSER.md §7), spent once, and given only by a
// user-verified passkey of the account that presents it.
func TestApprovalIsBoundToOneTicketAndPurpose(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	svc := newOIDCService(t, baseURL, "https://game.example")
	person := newBrowserPerson(t, baseURL)

	refusedWith := func(t *testing.T, ticket, approval string) {
		t.Helper()
		status, out := person.consent(t, map[string]any{"ticket": ticket, "approve": true, "approval": approval})
		if status != http.StatusUnauthorized || out["code"] != util.Errors.ApprovalInvalid.ErrorCode {
			t.Fatalf("consent: %d %v", status, out)
		}
	}

	t.Run("an approval for another purpose does not approve a sign-in", func(t *testing.T) {
		ticket := person.open(t, svc.params(nil))["ticket"].(string)
		approval, err := person.device.Approve(person.token, "connect", ticket)
		if err != nil {
			t.Fatal(err)
		}
		refusedWith(t, ticket, approval)
	})

	t.Run("an approval for another ticket does not approve this one", func(t *testing.T) {
		first := person.open(t, svc.params(nil))["ticket"].(string)
		second := person.open(t, svc.params(nil))["ticket"].(string)
		approval, err := person.device.Approve(person.token, "signin", first)
		if err != nil {
			t.Fatal(err)
		}
		refusedWith(t, second, approval)
	})

	t.Run("an approval is spent once", func(t *testing.T) {
		ticket := person.open(t, svc.params(nil))["ticket"].(string)
		approval, err := person.device.Approve(person.token, "signin", ticket)
		if err != nil {
			t.Fatal(err)
		}
		if status, out := person.consent(t, map[string]any{"ticket": ticket, "approve": true, "approval": approval}); status != http.StatusOK {
			t.Fatalf("consent: %d %v", status, out)
		}
		again := person.open(t, svc.params(nil))["ticket"].(string)
		refusedWith(t, again, approval)
	})

	t.Run("another account's approval does not approve", func(t *testing.T) {
		other := newBrowserPerson(t, baseURL)
		ticket := person.open(t, svc.params(nil))["ticket"].(string)
		approval, err := other.device.Approve(other.token, "signin", ticket)
		if err != nil {
			t.Fatal(err)
		}
		refusedWith(t, ticket, approval)
	})

	t.Run("another account's passkey cannot answer the ceremony", func(t *testing.T) {
		other := newBrowserPerson(t, baseURL)
		ticket := person.open(t, svc.params(nil))["ticket"].(string)
		// Begun with this person's session, answered by the other's device.
		mixed := *other.device
		_, err := mixed.Approve(person.token, "signin", ticket)
		passkeyRefusal(t, err, http.StatusUnauthorized, util.Errors.PasskeyVerificationFailed)
	})

	t.Run("an assertion without user verification is refused", func(t *testing.T) {
		ticket := person.open(t, svc.params(nil))["ticket"].(string)
		lax := *person.device
		lax.Authenticator.Options.UserNotVerified = true
		_, err := lax.Approve(person.token, "signin", ticket)
		passkeyRefusal(t, err, http.StatusUnauthorized, util.Errors.PasskeyVerificationFailed)
	})

	t.Run("an approval needs a session", func(t *testing.T) {
		_, err := person.device.Approve("", "signin", "anything")
		passkeyRefusal(t, err, http.StatusUnauthorized, util.Errors.NotAuthenticated)
	})

	t.Run("an unknown purpose is refused", func(t *testing.T) {
		_, err := person.device.Approve(person.token, "delete-everything", "t")
		passkeyRefusal(t, err, http.StatusBadRequest, util.Errors.PasskeyRequestInvalid)
	})
}

// The connect page reads the link by the app's rules and refuses one that
// does not check out, connecting nothing.
func TestConnectPage(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)
	_, challenge := testutils.PKCEPair()
	good := url.Values{
		"client": {"https://tool.example"}, "name": {"Guestbook"}, "redirect": {"https://tool.example/back"},
		"state": {"s-1"}, "challenge": {challenge}, "permissions": {"shares:manage"}, "vault": {"read"},
		"vault_reason": {"To fill in the form"},
	}
	body := api.E.GET("/connect").WithQueryString(good.Encode()).WithHeader("Accept", browserAccept).
		Expect().Status(http.StatusOK).Body().Raw()
	for _, want := range []string{`"Guestbook"`, `"https://tool.example/back"`, `"revoked://connect?`} {
		if !strings.Contains(body, want) {
			t.Fatalf("the page lacks %s", want)
		}
	}

	for name, change := range map[string][2]string{
		"redirect off the tool's origin": {"redirect", "https://evil.example/back"},
		"challenge that is not PKCE":     {"challenge", "short"},
		"unknown permission":             {"permissions", "workspace:delete"},
		"reason that is too long":        {"vault_reason", strings.Repeat("x", 121)},
		"vault other than read":          {"vault", "write"},
	} {
		bad := url.Values{}
		for k, v := range good {
			bad[k] = v
		}
		bad.Set(change[0], change[1])
		page := api.E.GET("/connect").WithQueryString(bad.Encode()).WithHeader("Accept", browserAccept).
			Expect().Status(http.StatusBadRequest).Body().Raw()
		if strings.Contains(page, "evil.example") {
			t.Fatalf("%s: the refused link was echoed", name)
		}
	}
}
