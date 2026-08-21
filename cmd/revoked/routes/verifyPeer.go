package routes

import (
	"crypto"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"regexp"
	"strings"
	"time"

	"revoked/cmd/revoked/server"
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
)

// Trust states mirrored from the Flutter TrustState enum, so a client renders the
// same badge whether it verified locally or via this proxy.
const (
	trustVerified   = "verified"
	trustDNSMissing = "dnsMissing"
	trustUnverified = "unverified"
	trustSpoofed    = "spoofed"

	// trustRevoked is its own state rather than a flavour of unverified: the
	// domain is real and the signature is genuine, and the issuer has withdrawn
	// the identity anyway. A viewer needs to be told that, not shown a vague
	// "could not verify".
	trustRevoked = "revoked"
)

// txtPinPattern matches the pinned root fingerprint in a `_revoked.<domain>` TXT record.
var txtPinPattern = regexp.MustCompile(`(?i)v=revoked1;\s*k=sha256/([0-9a-f]{64})`)

type verifyPeerRequest struct {
	Domain              string `json:"domain"`
	IdentityFingerprint string `json:"identityFingerprint"`
	ParentSignature     string `json:"parentSignature"`
}

type verifyPeerResponse struct {
	State               string `json:"state"`
	Domain              string `json:"domain"`
	Reason              string `json:"reason"`
	RootFingerprint     string `json:"rootFingerprint,omitempty"`
	IdentityFingerprint string `json:"identityFingerprint,omitempty"`

	// IdentityStatus is the issuer's own current word: active, revoked, or
	// unknown when it disclaims the fingerprint. Empty when no identity was
	// asked about, or when the issuer could not be reached — which is why it is
	// reported separately from State rather than folded into it.
	IdentityStatus string `json:"identityStatus,omitempty"`
}

// VerifyPeerRoute proxies the trust chain server-side for clients that cannot do raw
// DNS, walking the same chain as the Flutter DomainVerificationService:
//
//	DNS-TXT(_revoked.<domain>) -> GET https://<domain>/api/server assertion
//	-> fingerprint-pin match -> (optional) identity parentSignature under the root key
//	-> (optional) the issuer's signed, current status for that identity
//
//	POST /api/verify-peer -> state: verified | dnsMissing | unverified | spoofed | revoked
//
// Unauthenticated by design: any peer must be able to ask it about a third party.
func VerifyPeerRoute(app core.App) {
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		e.Router.POST("/api/verify-peer", func(re *core.RequestEvent) error {
			var req verifyPeerRequest
			if err := re.BindBody(&req); err != nil {
				return re.BadRequestError("invalid body", err)
			}
			domain := strings.ToLower(strings.TrimSpace(req.Domain))
			if domain == "" {
				return re.JSON(http.StatusOK, verifyPeerResponse{
					State:  trustUnverified,
					Domain: domain,
					Reason: "No domain was supplied, so there is nothing to verify.",
				})
			}

			now := time.Now()

			pin, err := lookupRevokedTXTPin(domain)
			if err != nil {
				return re.JSON(http.StatusOK, verifyPeerResponse{
					State:  trustDNSMissing,
					Domain: domain,
					Reason: "DNS lookup for _revoked." + domain + " failed: " + err.Error(),
				})
			}
			if pin == "" {
				return re.JSON(http.StatusOK, verifyPeerResponse{
					State:  trustDNSMissing,
					Domain: domain,
					Reason: "No _revoked." + domain + " TXT record found. The operator " +
						"has not published one, or DNS has not propagated.",
				})
			}

			assertion, err := fetchServerAssertion(domain)
			if err != nil {
				return re.JSON(http.StatusOK, verifyPeerResponse{
					State:  trustUnverified,
					Domain: domain,
					Reason: "Could not fetch https://" + domain + "/api/server: " + err.Error(),
				})
			}
			if err := server.VerifyAssertion(assertion, now); err != nil {
				return re.JSON(http.StatusOK, verifyPeerResponse{
					State:  trustSpoofed,
					Domain: domain,
					Reason: "The server's signed assertion failed verification: " + err.Error(),
				})
			}
			if !strings.EqualFold(assertion.Body.Domain, domain) {
				return re.JSON(http.StatusOK, verifyPeerResponse{
					State:  trustSpoofed,
					Domain: domain,
					Reason: "The server's assertion is for " + assertion.Body.Domain +
						", not " + domain + ".",
				})
			}

			// DNS must pin exactly the served root key.
			rootFp := strings.ToLower(assertion.Body.Fingerprint)
			if rootFp != pin {
				return re.JSON(http.StatusOK, verifyPeerResponse{
					State:  trustSpoofed,
					Domain: domain,
					Reason: "DNS pins root key " + pin + " but " + domain + " serves " +
						rootFp + ". This is consistent with a spoofed or hijacked server.",
				})
			}

			if req.IdentityFingerprint != "" && req.ParentSignature != "" {
				ok, verr := verifyParentSignature(
					assertion.Body.PublicKey, req.IdentityFingerprint, req.ParentSignature,
				)
				if verr != nil || !ok {
					return re.JSON(http.StatusOK, verifyPeerResponse{
						State:  trustSpoofed,
						Domain: domain,
						Reason: "The identity claims to be from " + domain + " but its " +
							"signature does not verify under that server's root key.",
					})
				}
				// The signature proves the identity was issued by this domain.
				// It cannot prove the domain still stands behind it — a leaf is
				// good for ten years and parentSignature never expires — so the
				// issuer is asked for its current word before we call it verified.
				statusState, statusWord, statusReason := checkPeerIdentityStatus(
					domain, assertion.Body.PublicKey, req.IdentityFingerprint, now,
				)
				return re.JSON(http.StatusOK, verifyPeerResponse{
					State:               statusState,
					Domain:              domain,
					Reason:              statusReason,
					RootFingerprint:     rootFp,
					IdentityFingerprint: req.IdentityFingerprint,
					IdentityStatus:      statusWord,
				})
			}

			return re.JSON(http.StatusOK, verifyPeerResponse{
				State:           trustVerified,
				Domain:          domain,
				Reason:          "DNS-verified — the root key on " + domain + " matches the published TXT record.",
				RootFingerprint: rootFp,
			})
		})
		return e.Next()
	})
}

// checkPeerIdentityStatus asks the issuing domain whether it still vouches for
// a fingerprint, returning the trust state to report, the issuer's own word, and
// the human-readable reason.
//
// An unreachable issuer downgrades to unverified rather than either extreme: a
// server being down is not evidence of revocation, and it is not evidence of
// good standing either. The caller's gate already treats non-verified as
// "warn and require confirmation", which is the honest answer to "we could not
// find out".
func checkPeerIdentityStatus(domain, rootPubPEM, fingerprint string, now time.Time) (state, word, reason string) {
	if !server.ValidIdentityFingerprint(fingerprint) {
		return trustVerified, "",
			"DNS-verified — the root key on " + domain + " matches the published TXT record and signed this identity."
	}

	assertion, err := fetchPeerIdentityStatus(domain, fingerprint)
	if err != nil {
		return trustUnverified, "",
			"The identity is signed by " + domain + ", but that server could not be " +
				"asked whether it still stands behind it: " + err.Error()
	}

	body, err := server.VerifyIdentityStatus(assertion, rootPubPEM, domain, fingerprint, now)
	if err != nil {
		return trustUnverified, "",
			"The status answer from " + domain + " did not verify under its own root key: " + err.Error()
	}

	switch body.Status {
	case server.IdentityStatusActive:
		return trustVerified, server.IdentityStatusActive,
			"DNS-verified — the root key on " + domain + " matches the published TXT " +
				"record, signed this identity, and still vouches for it."
	case server.IdentityStatusRevoked:
		return trustRevoked, server.IdentityStatusRevoked,
			"The signature is genuine, but " + domain + " has revoked this identity. " +
				"Whoever holds the key no longer speaks for that domain."
	default:
		return trustUnverified, server.IdentityStatusUnknown,
			domain + " has no record of this identity. The signature verifies, so it " +
				"was issued there once, but the server does not currently claim it."
	}
}

// fetchPeerIdentityStatus retrieves a peer's signed status answer.
//
// Through the SSRF-safe client: the domain arrives in the request body, so this
// is a server-side fetch of a caller-chosen URL. Validating the hostname alone
// loses to DNS rebinding, and the answer is signed anyway — the transport only
// has to be prevented from reaching somewhere it shouldn't.
func fetchPeerIdentityStatus(domain, fingerprint string) (server.IdentityStatusAssertion, error) {
	client := util.NewSafeCallbackClient(8 * time.Second)
	resp, err := client.Get("https://" + domain + "/api/identities/" + url.PathEscape(fingerprint) + "/status")
	if err != nil {
		return server.IdentityStatusAssertion{}, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return server.IdentityStatusAssertion{}, fmt.Errorf("HTTP %d", resp.StatusCode)
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return server.IdentityStatusAssertion{}, err
	}
	var assertion server.IdentityStatusAssertion
	if err := json.Unmarshal(body, &assertion); err != nil {
		return server.IdentityStatusAssertion{}, err
	}
	return assertion, nil
}

// lookupRevokedTXTPin resolves the pinned root fingerprint from the domain's _revoked
// TXT record. A genuinely absent record yields ("", nil); an error means the lookup
// itself failed.
func lookupRevokedTXTPin(domain string) (string, error) {
	host := server.TXTPrefix + "." + domain
	records, err := net.LookupTXT(host)
	if err != nil {
		var dnsErr *net.DNSError
		if errors.As(err, &dnsErr) && dnsErr.IsNotFound {
			return "", nil
		}
		return "", err
	}
	for _, rec := range records {
		if m := txtPinPattern.FindStringSubmatch(rec); m != nil {
			return strings.ToLower(m[1]), nil
		}
	}
	return "", nil
}

// fetchServerAssertion fetches and decodes the peer's /api/server assertion.
func fetchServerAssertion(domain string) (server.Assertion, error) {
	client := &http.Client{Timeout: 8 * time.Second}
	resp, err := client.Get("https://" + domain + "/api/server")
	if err != nil {
		return server.Assertion{}, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return server.Assertion{}, fmt.Errorf("HTTP %d", resp.StatusCode)
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return server.Assertion{}, err
	}
	var payload struct {
		Assertion server.Assertion `json:"assertion"`
	}
	if err := json.Unmarshal(body, &payload); err != nil {
		return server.Assertion{}, err
	}
	return payload.Assertion, nil
}

// verifyParentSignature checks parentSigHex as an RSA-SHA256 signature over
// identityFingerprint under the root key in rootPubPEM, mirroring the client-side
// check in DomainVerificationService.verify.
func verifyParentSignature(rootPubPEM, identityFingerprint, parentSigHex string) (bool, error) {
	block, _ := pem.Decode([]byte(rootPubPEM))
	if block == nil {
		return false, errors.New("root public key is not PEM")
	}
	pubAny, err := x509.ParsePKIXPublicKey(block.Bytes)
	if err != nil {
		return false, err
	}
	pub, ok := pubAny.(*rsa.PublicKey)
	if !ok {
		return false, errors.New("root public key is not RSA")
	}
	sig, err := hex.DecodeString(parentSigHex)
	if err != nil {
		return false, err
	}
	digest := sha256.Sum256([]byte(identityFingerprint))
	if err := rsa.VerifyPKCS1v15(pub, crypto.SHA256, digest[:], sig); err != nil {
		return false, err
	}
	return true, nil
}
