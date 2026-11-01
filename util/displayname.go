package util

import (
	"strings"
	"unicode"

	"golang.org/x/text/unicode/norm"
)

// MaxDisplayNameRunes bounds a name shown to a stranger. Long enough for a
// person or an organisation, short enough that it cannot carry a sentence.
const MaxDisplayNameRunes = 60

// SafeDisplayName reports whether name can be shown to a stranger as the
// sender of an email, and returns it normalised.
//
// The name comes from `identities.name` or a workspace's name, both free text
// typed by whoever holds the account. In an email it sits directly above the
// server's own domain, so a name reading "security@bank.example" would borrow
// the authority of the one row the sender cannot choose. Escaping and a length
// cap do not touch that: such a string is short and perfectly well-formed.
//
// So this is an allowlist of shapes rather than a denylist of words, and it
// fails closed — a name it cannot vouch for is not shown at all, and the
// caller falls back to saying the grant is unsigned, which is both true and
// more use to the reader than a blanked-out row.
func SafeDisplayName(name string) (string, bool) {
	clean := strings.Join(strings.Fields(norm.NFKC.String(name)), " ")
	if clean == "" || len([]rune(clean)) > MaxDisplayNameRunes {
		return "", false
	}
	// An address is the shape being impersonated, so no part of one passes.
	if strings.ContainsRune(clean, '@') {
		return "", false
	}
	for _, r := range clean {
		if isDisguisingRune(r) {
			return "", false
		}
	}
	if mixesScripts(clean) {
		return "", false
	}
	tokens := strings.Fields(clean)
	for i, token := range tokens {
		if looksLikeHost(token) {
			return "", false
		}
		// "bank .example" is the same shape with a space hiding in the dot.
		// A leading dot is what separates it from "Acme Co. Ltd", where the
		// dot ends the token before the space rather than starting the one
		// after it.
		if i > 0 && leadsWithDomainDot(token) && endsWithLetter(tokens[i-1]) {
			return "", false
		}
	}
	return clean, true
}

func leadsWithDomainDot(token string) bool {
	runes := []rune(token)
	return len(runes) > 1 && runes[0] == '.' && unicode.IsLetter(runes[1])
}

func endsWithLetter(token string) bool {
	runes := []rune(token)
	return len(runes) > 0 && unicode.IsLetter(runes[len(runes)-1])
}

// looksLikeHost reports whether a token reads as a hostname: a dot with a
// letter either side, so "bank.example" and "mail.bank.example" both match.
func looksLikeHost(token string) bool {
	runes := []rune(token)
	for i, r := range runes {
		if r != '.' || i == 0 || i == len(runes)-1 {
			continue
		}
		if unicode.IsLetter(runes[i-1]) && unicode.IsLetter(runes[i+1]) {
			return true
		}
	}
	return false
}

// isDisguisingRune reports whether a rune can hide or reorder what is around
// it — how a reversed or invisible label is smuggled into a name.
func isDisguisingRune(r rune) bool {
	switch {
	case r >= 0x200B && r <= 0x200F, // zero-width and LTR/RTL marks
		r >= 0x202A && r <= 0x202E, // bidi embedding and override
		r >= 0x2066 && r <= 0x2069: // bidi isolates
		return true
	}
	return unicode.IsControl(r)
}

// mixesScripts reports whether a name draws on Latin and on Greek or Cyrillic
// at once. That is the practical bound on homoglyphs without shipping a
// confusables table: "Аda" with a Cyrillic А is refused, while a name written
// wholly in one script is not penalised for it.
func mixesScripts(name string) bool {
	var latin, confusable bool
	for _, r := range name {
		switch {
		case unicode.Is(unicode.Latin, r):
			latin = true
		case unicode.Is(unicode.Cyrillic, r), unicode.Is(unicode.Greek, r):
			confusable = true
		}
	}
	return latin && confusable
}
