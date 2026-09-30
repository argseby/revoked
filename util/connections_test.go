package util

import "testing"

func TestPKCEChallengeMatchesRFC7636(t *testing.T) {
	// The worked example from RFC 7636, appendix B.
	if got := PKCEChallenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"); got != "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM" {
		t.Fatalf("PKCEChallenge = %q", got)
	}
}

func TestNormalizeOrigin(t *testing.T) {
	for raw, want := range map[string]string{
		"https://Tool.Example.com":  "https://tool.example.com",
		"https://tool.example.com/": "https://tool.example.com",
		"https://tool.example:8443": "https://tool.example:8443",
		"http://localhost:5173":     "http://localhost:5173",
	} {
		if got, ok := NormalizeOrigin(raw); !ok || got != want {
			t.Errorf("NormalizeOrigin(%q) = %q, %v; want %q", raw, got, ok, want)
		}
	}
	for _, raw := range []string{
		"", "tool.example.com", "http://tool.example.com", "https://tool.example.com/app",
		"https://tool.example.com?x=1", "https://user@tool.example.com", "javascript:alert(1)",
	} {
		if got, ok := NormalizeOrigin(raw); ok {
			t.Errorf("NormalizeOrigin(%q) accepted as %q", raw, got)
		}
	}
}

func TestRedirectWithinOrigin(t *testing.T) {
	origin := "https://tool.example.com"
	for redirect, want := range map[string]bool{
		"https://tool.example.com/":         true,
		"https://tool.example.com/back?x=1": true,
		"https://tool.example.com.evil/":    false,
		"https://evil.example/":             false,
		"https://user@tool.example.com/":    false,
		"https://tool.example.com/#frag":    false,
	} {
		if got := RedirectWithinOrigin(redirect, origin); got != want {
			t.Errorf("RedirectWithinOrigin(%q) = %v", redirect, got)
		}
	}
}
