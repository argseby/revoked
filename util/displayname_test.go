package util

import "testing"

// The mail's "From" row sits directly above the server's own domain, so a name
// that reads as an address or a host would borrow authority it does not have.
// These are the shapes that may be shown, and the ones that may not.
func TestSafeDisplayName(t *testing.T) {
	sixty := ""
	for len([]rune(sixty)) < MaxDisplayNameRunes {
		sixty += "a"
	}

	shown := []struct{ name, want string }{
		{"Ada Lovelace", "Ada Lovelace"},
		{"Ada O'Neill-Smith", "Ada O'Neill-Smith"},
		{"  Ada   Lovelace  ", "Ada Lovelace"},
		{"慧", "慧"},
		{"Acme GmbH & Co. KG", "Acme GmbH & Co. KG"},
		{sixty, sixty},
	}
	for _, c := range shown {
		got, ok := SafeDisplayName(c.name)
		if !ok {
			t.Errorf("SafeDisplayName(%q) refused a name that reads as a name", c.name)
			continue
		}
		if got != c.want {
			t.Errorf("SafeDisplayName(%q) = %q, want %q", c.name, got, c.want)
		}
	}

	refused := map[string]string{
		"an address":               "security@bank.example",
		"a bare host":              "bank.example",
		"a deeper host":            "mail.bank.example",
		"a host split by space":    "bank .example",
		"a right-to-left override": "Ada‮elpmaxe.knab",
		"a zero-width joiner":      "Ada​Lovelace",
		"Latin wearing Cyrillic":   "Аda Lovelace",
		"Latin wearing Greek":      "Αda Lovelace",
		"one rune too many":        sixty + "a",
		"nothing at all":           "   ",
	}
	for why, name := range refused {
		if _, ok := SafeDisplayName(name); ok {
			t.Errorf("SafeDisplayName(%q) allowed %s", name, why)
		}
	}
}

// "Acme GmbH & Co. KG" has a dot, and must still pass: the host shape needs a
// letter on both sides of it, and ". K" does not have one.
func TestSafeDisplayNameAllowsAnAbbreviation(t *testing.T) {
	for _, name := range []string{"Acme Co. Ltd", "J. Random Hacker", "Ada L."} {
		if _, ok := SafeDisplayName(name); !ok {
			t.Errorf("SafeDisplayName(%q) refused an ordinary abbreviation", name)
		}
	}
}
