package server

import (
	"crypto/ecdsa"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"
)

// The app presents and the server verifies, so the two must agree on every
// byte a key binding commits to: which disclosures, in which order, hashed
// how, signed in which form. A disagreement presents as a holder whose key is
// fine and whose every presentation is refused.
//
// The presentation here was made by the app's own code
// (app/lib/core/utils/sd_jwt.dart) from a credential this package issued.
// Refresh both fixtures with app/tool/gen_sd_jwt_fixture.sh.
func TestPresentationMadeByTheAppVerifies(t *testing.T) {
	fixtures := filepath.Join("..", "..", "..", "app", "test", "fixtures")
	var issued struct {
		IssuerJWK PublicJWK `json:"issuerJwk"`
		HolderJWK PublicJWK `json:"holderJwk"`
		Disclose  []string  `json:"disclose"`
		Audience  string    `json:"audience"`
		Nonce     string    `json:"nonce"`
	}
	var presented struct {
		Presentation string `json:"presentation"`
		PresentedAt  int64  `json:"presentedAtUnix"`
	}
	readFixture(t, filepath.Join(fixtures, "sd_jwt.json"), &issued)
	readFixture(t, filepath.Join(fixtures, "app_presentation.json"), &presented)

	pub, err := issued.IssuerJWK.PublicKey()
	if err != nil {
		t.Fatal(err)
	}
	issuerKey, ok := pub.(*ecdsa.PublicKey)
	if !ok {
		t.Fatal("the fixture's issuer key is not an ECDSA key")
	}
	now := time.Unix(presented.PresentedAt, 0)

	p, err := ParseCredential(presented.Presentation)
	if err != nil {
		t.Fatalf("ParseCredential: %v", err)
	}
	stated, err := VerifyCredential(p, issuerKey, now)
	if err != nil {
		t.Fatalf("VerifyCredential: %v", err)
	}
	if len(stated.Claims) != len(issued.Disclose) || stated.Claims["age_over_18"] != true || stated.Withheld != 2 {
		t.Fatalf("claims = %v, withheld = %d", stated.Claims, stated.Withheld)
	}
	if stated.HolderKey == nil || !stated.HolderKey.SameKey(issued.HolderJWK) {
		t.Fatal("the credential does not name the fixture's holder key")
	}
	if err := VerifyKeyBinding(p, *stated.HolderKey, issued.Audience, issued.Nonce, now); err != nil {
		t.Fatalf("the app's key binding does not verify: %v", err)
	}
	if err := VerifyKeyBinding(p, *stated.HolderKey, issued.Audience, "another-nonce", now); err == nil {
		t.Fatal("the app's key binding verified for a nonce it was not made for")
	}
}

func readFixture(t *testing.T, path string, into any) {
	t.Helper()
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("%v — regenerate with app/tool/gen_sd_jwt_fixture.sh", err)
	}
	if err := json.Unmarshal(raw, into); err != nil {
		t.Fatalf("%s: %v", path, err)
	}
}
