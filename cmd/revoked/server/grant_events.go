package server

import (
	"crypto"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"strings"
	"time"
)

// GrantEventsType is the domain separator for a batch of grant events, for the
// same reason [IdentityStatusType] leads a status body: the root key signs
// several kinds of statement, and none may be mistaken for another.
const GrantEventsType = "grant-events-v1"

// GrantEventsTTL bounds how long a signed batch is accepted. A batch is signed
// at each delivery attempt rather than once, so a retry never arrives stale;
// the short window only limits how long a captured batch can be replayed.
const GrantEventsTTL = 5 * time.Minute

// GrantEvent is one change to one grant: its id on the sending server, what
// happened, and the status it has now. It never carries a value.
type GrantEvent struct {
	Grant  string `json:"grant"`
	Type   string `json:"type"`
	Status string `json:"status"`
	At     int64  `json:"at"`
}

// GrantEventsBody is what gets signed. Field order is load-bearing, as for
// every signed body in this package.
//
// Audience names the receiving domain, so a batch sent to one server cannot be
// replayed against another that holds grants from the same sender.
type GrantEventsBody struct {
	Type      string       `json:"type"`
	Domain    string       `json:"domain"`
	Audience  string       `json:"audience"`
	Events    []GrantEvent `json:"events"`
	IssuedAt  int64        `json:"issuedAt"`
	ExpiresAt int64        `json:"expiresAt"`
}

// SignedGrantEvents is the wire format POSTed to /api/grants/events. Like
// [IdentityStatusAssertion] it carries the exact signed bytes, so the two sides
// never have to agree on a JSON encoding.
type SignedGrantEvents struct {
	Payload   string `json:"payload"`
	Signature string `json:"signature"`
}

// Body decodes the payload WITHOUT checking the signature. Only for reading the
// claimed sender, so the right key can be fetched; anything that acts on the
// events must go through [VerifyGrantEvents].
func (s SignedGrantEvents) Body() (GrantEventsBody, error) {
	raw, err := base64.RawURLEncoding.DecodeString(s.Payload)
	if err != nil {
		return GrantEventsBody{}, fmt.Errorf("grant events: decode payload: %w", err)
	}
	var body GrantEventsBody
	if err := json.Unmarshal(raw, &body); err != nil {
		return GrantEventsBody{}, fmt.Errorf("grant events: parse payload: %w", err)
	}
	return body, nil
}

// SignGrantEvents signs a batch of events for one receiving domain; now is a
// parameter so tests can pin time.
func (r *RootKey) SignGrantEvents(audience string, events []GrantEvent, now time.Time) (SignedGrantEvents, error) {
	if audience == "" {
		return SignedGrantEvents{}, errors.New("server: grant events: audience is required")
	}
	body := GrantEventsBody{
		Type:      GrantEventsType,
		Domain:    r.domain,
		Audience:  audience,
		Events:    events,
		IssuedAt:  now.Unix(),
		ExpiresAt: now.Add(GrantEventsTTL).Unix(),
	}
	payload, err := json.Marshal(body)
	if err != nil {
		return SignedGrantEvents{}, fmt.Errorf("server: marshal grant events: %w", err)
	}
	sig, err := r.Sign(payload)
	if err != nil {
		return SignedGrantEvents{}, fmt.Errorf("server: sign grant events: %w", err)
	}
	return SignedGrantEvents{
		Payload:   base64.RawURLEncoding.EncodeToString(payload),
		Signature: hex.EncodeToString(sig),
	}, nil
}

// VerifyGrantEvents is the receiver-side counterpart to SignGrantEvents.
//
// rootPubPEM must be the sender's root key, already tied to expectSender
// through the DNS pin (or an operator override). The signature is checked over
// the transmitted bytes before they are parsed, and the returned body is the
// one those bytes decode to.
func VerifyGrantEvents(s SignedGrantEvents, rootPubPEM, expectSender, expectAudience string, now time.Time) (GrantEventsBody, error) {
	payload, err := base64.RawURLEncoding.DecodeString(s.Payload)
	if err != nil {
		return GrantEventsBody{}, fmt.Errorf("grant events: decode payload: %w", err)
	}

	block, _ := pem.Decode([]byte(rootPubPEM))
	if block == nil {
		return GrantEventsBody{}, errors.New("grant events: root key is not PEM")
	}
	pubAny, err := x509.ParsePKIXPublicKey(block.Bytes)
	if err != nil {
		return GrantEventsBody{}, fmt.Errorf("grant events: parse root key: %w", err)
	}
	pub, ok := pubAny.(*rsa.PublicKey)
	if !ok {
		return GrantEventsBody{}, errors.New("grant events: root key is not RSA")
	}

	sig, err := hex.DecodeString(s.Signature)
	if err != nil {
		return GrantEventsBody{}, fmt.Errorf("grant events: decode signature: %w", err)
	}
	digest := sha256.Sum256(payload)
	if err := rsa.VerifyPKCS1v15(pub, crypto.SHA256, digest[:], sig); err != nil {
		return GrantEventsBody{}, fmt.Errorf("grant events: signature: %w", err)
	}

	var body GrantEventsBody
	if err := json.Unmarshal(payload, &body); err != nil {
		return GrantEventsBody{}, fmt.Errorf("grant events: parse payload: %w", err)
	}
	if body.Type != GrantEventsType {
		return GrantEventsBody{}, errors.New("grant events: wrong or missing type")
	}
	if !strings.EqualFold(body.Domain, expectSender) {
		return GrantEventsBody{}, errors.New("grant events: signed for a different sender")
	}
	if !strings.EqualFold(body.Audience, expectAudience) {
		return GrantEventsBody{}, errors.New("grant events: addressed to a different server")
	}
	if body.IssuedAt > now.Add(IdentityStatusClockSkew).Unix() {
		return GrantEventsBody{}, errors.New("grant events: issued in the future")
	}
	if body.ExpiresAt < now.Unix() {
		return GrantEventsBody{}, errors.New("grant events: expired")
	}
	return body, nil
}

// VerifyParentSignature checks parentSigHex as the root key's signature over an
// identity fingerprint — the parentSignature an identity carries.
func VerifyParentSignature(rootPubPEM, identityFingerprint, parentSigHex string) error {
	block, _ := pem.Decode([]byte(rootPubPEM))
	if block == nil {
		return errors.New("root public key is not PEM")
	}
	pubAny, err := x509.ParsePKIXPublicKey(block.Bytes)
	if err != nil {
		return err
	}
	pub, ok := pubAny.(*rsa.PublicKey)
	if !ok {
		return errors.New("root public key is not RSA")
	}
	sig, err := hex.DecodeString(parentSigHex)
	if err != nil {
		return err
	}
	digest := sha256.Sum256([]byte(identityFingerprint))
	return rsa.VerifyPKCS1v15(pub, crypto.SHA256, digest[:], sig)
}
