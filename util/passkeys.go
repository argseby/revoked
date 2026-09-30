package util

import (
	"net"
	"strings"
	"time"
)

const (
	// PasskeyCeremonyTTL is how long a registration or sign-in may take between
	// the server's challenge and the authenticator's answer.
	PasskeyCeremonyTTL = 5 * time.Minute

	// PasskeyCodeTTL is how long the one-time code the sign-in page hands the
	// app may wait to be exchanged: a redirect and one request.
	PasskeyCodeTTL = 2 * time.Minute

	// PasskeyTicketTTL is how long a link a signed-in person made to add a
	// passkey stays good: long enough to open it on another device.
	PasskeyTicketTTL = 15 * time.Minute

	// PasskeyOperatorTicketTTL is how long a link the operator issued stays
	// good: it has to reach the person it is for.
	PasskeyOperatorTicketTTL = 24 * time.Hour

	// PasskeyPagePath is where the server's own sign-in page lives. A passkey
	// is bound to the address it was made at, so this page — not the app — is
	// what talks to the authenticator.
	PasskeyPagePath = "/passkey"
)

// PasskeyRelyingParty names what a passkey made through a request to host is
// bound to: the relying-party id (a host name, never a port) and the one
// origin its ceremonies may come from. host is an authority the caller already
// trusts — the configured domain, or a loopback address.
//
// A passkey cannot be bound to an IP address, so a loopback IP reports !ok:
// the development address is localhost.
func PasskeyRelyingParty(host string) (rpID, origin string, ok bool) {
	name := host
	if h, _, err := net.SplitHostPort(host); err == nil {
		name = h
	}
	name = strings.ToLower(strings.TrimSpace(name))
	if name == "" || net.ParseIP(strings.Trim(name, "[]")) != nil {
		return "", "", false
	}
	if name == "localhost" {
		return name, "http://" + strings.ToLower(host), true
	}
	return name, "https://" + strings.ToLower(host), true
}
