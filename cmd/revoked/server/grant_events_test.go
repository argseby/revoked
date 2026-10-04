package server

import (
	"encoding/base64"
	"strings"
	"testing"
	"time"
)

func sampleGrantEvents() []GrantEvent {
	return []GrantEvent{{Grant: "abc123", Type: "grant.revoked", Status: "revoked", At: 1_700_000_000_000}}
}

func TestGrantEventsRoundTrip(t *testing.T) {
	root := testRoot(t, "responder.example")
	now := time.Unix(1_700_000_000, 0)

	signed, err := root.SignGrantEvents("requester.example", sampleGrantEvents(), now)
	if err != nil {
		t.Fatalf("SignGrantEvents: %v", err)
	}
	body, err := VerifyGrantEvents(signed, root.PublicKeyPEM(), "responder.example", "requester.example", now)
	if err != nil {
		t.Fatalf("a freshly signed batch did not verify: %v", err)
	}
	if len(body.Events) != 1 || body.Events[0].Grant != "abc123" {
		t.Fatalf("verified body does not carry what was signed: %+v", body)
	}
}

// A batch names the server it is for, so one captured on its way to one
// requester cannot be replayed against another holding grants from the same
// responder.
func TestGrantEventsAreBoundToTheirAudience(t *testing.T) {
	root := testRoot(t, "responder.example")
	now := time.Unix(1_700_000_000, 0)
	signed, err := root.SignGrantEvents("requester.example", sampleGrantEvents(), now)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := VerifyGrantEvents(signed, root.PublicKeyPEM(), "responder.example", "other.example", now); err == nil {
		t.Fatal("a batch addressed to another server was accepted")
	}
	if _, err := VerifyGrantEvents(signed, root.PublicKeyPEM(), "someone.example", "requester.example", now); err == nil {
		t.Fatal("a batch was accepted for a sender other than the one that signed it")
	}
}

func TestGrantEventsExpire(t *testing.T) {
	root := testRoot(t, "responder.example")
	now := time.Unix(1_700_000_000, 0)
	signed, err := root.SignGrantEvents("requester.example", sampleGrantEvents(), now)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := VerifyGrantEvents(signed, root.PublicKeyPEM(), "responder.example", "requester.example",
		now.Add(GrantEventsTTL+time.Second)); err == nil {
		t.Fatal("a stale batch was accepted")
	}
	if _, err := VerifyGrantEvents(signed, root.PublicKeyPEM(), "responder.example", "requester.example",
		now.Add(-IdentityStatusClockSkew-time.Second)); err == nil {
		t.Fatal("a batch from the future was accepted")
	}
}

func TestGrantEventsRejectTampering(t *testing.T) {
	root := testRoot(t, "responder.example")
	other := testRoot(t, "responder.example")
	now := time.Unix(1_700_000_000, 0)
	signed, err := root.SignGrantEvents("requester.example", sampleGrantEvents(), now)
	if err != nil {
		t.Fatal(err)
	}

	if _, err := VerifyGrantEvents(signed, other.PublicKeyPEM(), "responder.example", "requester.example", now); err == nil {
		t.Fatal("a batch verified under a key that did not sign it")
	}

	raw, _ := base64.RawURLEncoding.DecodeString(signed.Payload)
	forged := strings.Replace(string(raw), `"revoked"`, `"active"`, 1)
	tampered := SignedGrantEvents{
		Payload:   base64.RawURLEncoding.EncodeToString([]byte(forged)),
		Signature: signed.Signature,
	}
	if _, err := VerifyGrantEvents(tampered, root.PublicKeyPEM(), "responder.example", "requester.example", now); err == nil {
		t.Fatal("an edited batch verified")
	}
}

// The root key also signs identity statuses; neither may pass for the other.
func TestGrantEventsAreNotIdentityStatuses(t *testing.T) {
	root := testRoot(t, "responder.example")
	now := time.Unix(1_700_000_000, 0)
	status, err := root.IssueIdentityStatus(sampleFingerprint, IdentityStatusActive, "", time.Time{}, now)
	if err != nil {
		t.Fatal(err)
	}
	asEvents := SignedGrantEvents{Payload: status.Payload, Signature: status.Signature}
	if _, err := VerifyGrantEvents(asEvents, root.PublicKeyPEM(), "responder.example", "", now); err == nil {
		t.Fatal("an identity status verified as a grant event batch")
	}
}
