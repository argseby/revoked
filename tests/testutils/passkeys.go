package testutils

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"

	"revoked/util"

	"github.com/descope/virtualwebauthn"
	"github.com/google/uuid"
)

// PasskeyDevice stands in for a person's device: an authenticator holding the
// passkeys it made, and the browser page and app around it. It talks to the
// server the way they do, at the address a passkey can be bound to.
type PasskeyDevice struct {
	baseURL       string
	rp            virtualwebauthn.RelyingParty
	Authenticator virtualwebauthn.Authenticator
	Credential    virtualwebauthn.Credential
}

// PasskeySession is what signing in ends with.
type PasskeySession struct {
	UserID string
	Token  string
}

// NewPasskeyDevice returns a device with no passkey yet.
func NewPasskeyDevice(baseURL string) *PasskeyDevice {
	// The suite reaches the server by loopback IP, which no passkey can be
	// bound to; the same listener answers as localhost.
	host := "localhost"
	if u, err := url.Parse(baseURL); err == nil && u.Port() != "" {
		host += ":" + u.Port()
	}
	return &PasskeyDevice{
		baseURL: baseURL,
		rp:      virtualwebauthn.RelyingParty{Name: "revoked", ID: "localhost", Origin: "http://" + host},
	}
}

// PasskeyError is a refusal from a passkey route.
type PasskeyError struct {
	Status int
	Code   string
}

func (e *PasskeyError) Error() string {
	return fmt.Sprintf("passkey route refused with %d %s", e.Status, e.Code)
}

// Post sends a JSON body to a passkey route as the page would.
func (d *PasskeyDevice) Post(path string, body any, out any) error {
	data, _ := json.Marshal(body)
	req, err := http.NewRequest("POST", d.baseURL+path, bytes.NewReader(data))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Host = strings.TrimPrefix(d.rp.Origin, "http://")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != http.StatusOK {
		var refusal struct {
			Code string `json:"code"`
		}
		_ = json.Unmarshal(raw, &refusal)
		return &PasskeyError{Status: resp.StatusCode, Code: refusal.Code}
	}
	if out == nil {
		return nil
	}
	return json.Unmarshal(raw, out)
}

type passkeyBegin struct {
	Session string          `json:"session"`
	Options json.RawMessage `json:"options"`
}

// pkcePair returns a verifier and its S256 challenge.
func pkcePair() (verifier, challenge string) {
	verifier = strings.Repeat("v", 20) + strings.ReplaceAll(uuid.New().String(), "-", "")
	return verifier, util.PKCEChallenge(verifier)
}

// Register makes a passkey on this device for what body names — an "email"
// for a new account, or a "ticket" — and signs in with the code it earns.
func (d *PasskeyDevice) Register(body map[string]any) (*PasskeySession, error) {
	verifier, challenge := pkcePair()
	request := map[string]any{"name": "Test device", "challenge": challenge}
	for k, v := range body {
		request[k] = v
	}
	var begin passkeyBegin
	if err := d.Post("/api/passkeys/register/begin", request, &begin); err != nil {
		return nil, err
	}
	options, err := virtualwebauthn.ParseAttestationOptions(string(begin.Options))
	if err != nil {
		return nil, fmt.Errorf("registration options: %w", err)
	}
	// A passkey carries the account it belongs to, so signing in needs no name.
	d.Authenticator = virtualwebauthn.NewAuthenticatorWithOptions(virtualwebauthn.AuthenticatorOptions{
		UserHandle: []byte(options.UserID),
	})
	d.Credential = virtualwebauthn.NewCredential(virtualwebauthn.KeyTypeEC2)
	response := virtualwebauthn.CreateAttestationResponse(d.rp, d.Authenticator, d.Credential, *options)
	d.Authenticator.AddCredential(d.Credential)

	var finish struct {
		Code string `json:"code"`
	}
	if err := d.Post("/api/passkeys/register/finish", map[string]any{
		"session": begin.Session, "credential": json.RawMessage(response),
	}, &finish); err != nil {
		return nil, err
	}
	return d.Exchange(finish.Code, verifier)
}

// SignIn signs in with the passkey this device holds.
func (d *PasskeyDevice) SignIn() (*PasskeySession, error) {
	verifier, challenge := pkcePair()
	code, err := d.SignInCode(challenge)
	if err != nil {
		return nil, err
	}
	return d.Exchange(code, verifier)
}

// SignInCode runs the sign-in ceremony and returns the one-time code bound to
// challenge, without redeeming it.
func (d *PasskeyDevice) SignInCode(challenge string) (string, error) {
	var begin passkeyBegin
	if err := d.Post("/api/passkeys/login/begin", map[string]any{"challenge": challenge}, &begin); err != nil {
		return "", err
	}
	options, err := virtualwebauthn.ParseAssertionOptions(string(begin.Options))
	if err != nil {
		return "", fmt.Errorf("sign-in options: %w", err)
	}
	response := virtualwebauthn.CreateAssertionResponse(d.rp, d.Authenticator, d.Credential, *options)
	var finish struct {
		Code string `json:"code"`
	}
	if err := d.Post("/api/passkeys/login/finish", map[string]any{
		"session": begin.Session, "credential": json.RawMessage(response),
	}, &finish); err != nil {
		return "", err
	}
	return finish.Code, nil
}

// Exchange redeems a one-time code the way the app does.
func (d *PasskeyDevice) Exchange(code, verifier string) (*PasskeySession, error) {
	var auth struct {
		Token  string `json:"token"`
		Record struct {
			Id string `json:"id"`
		} `json:"record"`
	}
	if err := d.Post("/api/passkeys/token", map[string]any{"code": code, "verifier": verifier}, &auth); err != nil {
		return nil, err
	}
	return &PasskeySession{UserID: auth.Record.Id, Token: auth.Token}, nil
}
