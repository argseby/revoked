package services

import (
	"crypto/ecdsa"
	"crypto/rand"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math/big"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"

	"revoked/cmd/revoked/server"
	"revoked/util"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/types"
)

// Verdicts on a presented credential. They share the vocabulary of the
// identity trust chain, with two additions a credential needs: it can run
// out, and it can be unreadable.
const (
	AttestationVerified   = "verified"
	AttestationUnverified = "unverified"
	AttestationDNSMissing = "dnsMissing"
	AttestationSpoofed    = "spoofed"
	AttestationRevoked    = "revoked"
	AttestationExpired    = "expired"
	AttestationInvalid    = "invalid"

	// What a status list says about one credential.
	CredentialStatusValid   = "valid"
	CredentialStatusRevoked = "revoked"
	CredentialStatusUnknown = "unknown"
)

// minStatusListSize is the smallest status list published. A list is at
// least twice as long as the number of credentials in it, so a position says
// little about when its credential was issued or how many there are.
const minStatusListSize = 1024

// credentialKeyCacheTTL caps how long a peer's verified credential key is
// reused, like the root key it hangs from.
const credentialKeyCacheTTL = time.Hour

// Both caches below are filled by whoever asks for a credential to be
// verified, with keys and lists from domains the caller chose. They are
// bounded so that a stream of presentations from throwaway domains cannot
// grow them without limit: a full cache drops what has lapsed, and failing
// that everything, which costs one refetch each.
const (
	maxCachedCredentialKeys = 2048
	maxCachedStatusLists    = 128
	maxStatusURILength      = 2048
)

// CredentialIssuer is the issuer identifier a server's credentials carry:
// its domain as an https origin. It is the same identifier the server uses
// as an OpenID Connect issuer.
func CredentialIssuer(domain string) string {
	return util.OIDCIssuer(domain)
}

// CredentialIssuerDomain reads the domain back out of an issuer identifier,
// refusing anything that is not exactly the identifier of a domain.
func CredentialIssuerDomain(issuer string) (string, bool) {
	u, err := url.Parse(issuer)
	if err != nil || u.Host == "" {
		return "", false
	}
	domain, ok := util.NormalizePeerDomain(u.Host)
	if !ok || CredentialIssuer(domain) != issuer {
		return "", false
	}
	return domain, true
}

// CredentialStatusURI is where a server publishes its status list.
func CredentialStatusURI(domain string) string {
	return CredentialIssuer(domain) + util.CredentialStatusListPath
}

// statusListSize is the published length for count credentials.
func statusListSize(count, highest int) int {
	size := minStatusListSize
	for size < 2*count || size <= highest {
		size *= 2
	}
	return size
}

// AllocateAttestationStatus gives an attestation its position in the status
// list: a free one picked at random, so that positions follow no order.
// Called inside the transaction that issues the credential.
func AllocateAttestationStatus(app core.App, attestationID string) (int, error) {
	f := util.Fields.AttestationStatus
	if existing, err := app.FindFirstRecordByFilter(util.Coll.AttestationStatus,
		f.Attestation+" = {:a}", dbx.Params{"a": attestationID}); err == nil && existing != nil {
		return existing.GetInt(f.Idx), nil
	}
	col, err := app.FindCollectionByNameOrId(util.Coll.AttestationStatus)
	if err != nil {
		return 0, err
	}
	rows, err := app.FindAllRecords(util.Coll.AttestationStatus)
	if err != nil {
		return 0, err
	}
	taken := make(map[int]bool, len(rows))
	highest := 0
	for _, row := range rows {
		idx := row.GetInt(f.Idx)
		taken[idx] = true
		highest = max(highest, idx)
	}
	size := statusListSize(len(rows)+1, highest)
	for attempt := 0; attempt < 64; attempt++ {
		n, err := rand.Int(rand.Reader, big.NewInt(int64(size)))
		if err != nil {
			return 0, err
		}
		idx := int(n.Int64())
		if taken[idx] {
			continue
		}
		row := core.NewRecord(col)
		row.Set(f.Idx, idx)
		row.Set(f.Attestation, attestationID)
		row.Set(f.Revoked, false)
		if err := app.Save(row); err != nil {
			// Another issue took the position between the read and the save.
			taken[idx] = true
			continue
		}
		return idx, nil
	}
	return 0, errors.New("no free position in the status list")
}

// RevokeAttestationStatus sets an attestation's bit. An attestation that was
// never issued has no position and nothing to revoke. The bit is never
// cleared: a revocation has been published, and verifiers may have read it.
func RevokeAttestationStatus(app core.App, attestationID string) error {
	f := util.Fields.AttestationStatus
	row, err := app.FindFirstRecordByFilter(util.Coll.AttestationStatus,
		f.Attestation+" = {:a}", dbx.Params{"a": attestationID})
	if err != nil || row == nil {
		return nil
	}
	if row.GetBool(f.Revoked) {
		return nil
	}
	row.Set(f.Revoked, true)
	row.Set(f.RevokedAt, types.NowDateTime())
	return app.Save(row)
}

// AttestationStatusList builds the list this server publishes.
func AttestationStatusList(app core.App) (server.StatusList, error) {
	f := util.Fields.AttestationStatus
	rows, err := app.FindAllRecords(util.Coll.AttestationStatus)
	if err != nil {
		return server.StatusList{}, err
	}
	highest := 0
	for _, row := range rows {
		highest = max(highest, row.GetInt(f.Idx))
	}
	list := server.NewStatusList(statusListSize(len(rows), highest))
	for _, row := range rows {
		if row.GetBool(f.Revoked) {
			list.Revoke(row.GetInt(f.Idx))
		}
	}
	return list, nil
}

type cachedCredentialKey struct {
	key     *ecdsa.PublicKey
	expires time.Time
}

var credentialKeys = struct {
	sync.Mutex
	m map[string]cachedCredentialKey
}{m: map[string]cachedCredentialKey{}}

// ErrCredentialKeyUnknown is returned when an issuer does not publish the key
// a credential names: it was signed with a key the domain no longer, or never,
// stood behind.
var ErrCredentialKeyUnknown = errors.New("issuer does not publish this key")

// PeerCredentialKey returns the key another server signs credentials with,
// once it has been tied to that server's domain: the root key through the DNS
// pin, and this key through the root key's certification of it. Verified keys
// are cached; failures are not.
func PeerCredentialKey(domain, kid string) (*ecdsa.PublicKey, error) {
	now := time.Now()
	cacheKey := strings.ToLower(domain) + "|" + kid

	credentialKeys.Lock()
	if c, ok := credentialKeys.m[cacheKey]; ok && now.Before(c.expires) {
		credentialKeys.Unlock()
		return c.key, nil
	}
	credentialKeys.Unlock()

	rootPub, err := PeerRootKey(domain)
	if err != nil {
		return nil, err
	}
	base, _ := util.PeerBaseURL(domain)
	raw, err := peerGet(base + util.CredentialIssuerMetadataPath)
	if err != nil {
		return nil, err
	}
	var metadata struct {
		Issuer string `json:"issuer"`
		JWKS   struct {
			Keys []server.PublicJWK `json:"keys"`
		} `json:"jwks"`
	}
	if err := json.Unmarshal(raw, &metadata); err != nil {
		return nil, err
	}
	if metadata.Issuer != CredentialIssuer(domain) {
		return nil, fmt.Errorf("%w: issuer metadata is for %s", ErrPeerKeySpoofed, metadata.Issuer)
	}
	for _, jwk := range metadata.JWKS.Keys {
		if jwk.Kid != kid {
			continue
		}
		key, err := server.VerifyCredentialKey(jwk, rootPub, strings.ToLower(domain))
		if err != nil {
			return nil, fmt.Errorf("%w: %v", ErrPeerKeySpoofed, err)
		}
		credentialKeys.Lock()
		if len(credentialKeys.m) >= maxCachedCredentialKeys {
			for k, c := range credentialKeys.m {
				if !now.Before(c.expires) {
					delete(credentialKeys.m, k)
				}
			}
			if len(credentialKeys.m) >= maxCachedCredentialKeys {
				clear(credentialKeys.m)
			}
		}
		credentialKeys.m[cacheKey] = cachedCredentialKey{key: key, expires: now.Add(credentialKeyCacheTTL)}
		credentialKeys.Unlock()
		return key, nil
	}
	return nil, ErrCredentialKeyUnknown
}

type cachedStatusList struct {
	list    server.StatusList
	expires time.Time
}

var statusLists = struct {
	sync.Mutex
	m map[string]cachedStatusList
}{m: map[string]cachedStatusList{}}

// PeerStatusList reads another server's status list, verified under the key
// that signed the credential asking for it. A list is kept for as long as it
// allows and no longer.
func PeerStatusList(domain string, key *ecdsa.PublicKey, uri string, now time.Time) (server.StatusList, error) {
	issuer := CredentialIssuer(domain)
	if !strings.HasPrefix(uri, issuer+"/") || len(uri) > maxStatusURILength {
		return server.StatusList{}, errors.New("status list is not published by the credential's issuer")
	}

	statusLists.Lock()
	if c, ok := statusLists.m[uri]; ok && now.Before(c.expires) {
		statusLists.Unlock()
		return c.list, nil
	}
	statusLists.Unlock()

	base, _ := util.PeerBaseURL(domain)
	req, err := http.NewRequest(http.MethodGet, base+strings.TrimPrefix(uri, issuer), nil)
	if err != nil {
		return server.StatusList{}, err
	}
	req.Header.Set("Accept", "application/statuslist+jwt")
	resp, err := util.NewSafeCallbackClient(PeerFetchTimeout).Do(req)
	if err != nil {
		return server.StatusList{}, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return server.StatusList{}, fmt.Errorf("HTTP %d", resp.StatusCode)
	}
	token, err := io.ReadAll(io.LimitReader(resp.Body, 2<<20))
	if err != nil {
		return server.StatusList{}, err
	}
	list, ttl, err := server.VerifyStatusList(strings.TrimSpace(string(token)), key, uri, now)
	if err != nil {
		return server.StatusList{}, err
	}
	if ttl > 0 {
		statusLists.Lock()
		if len(statusLists.m) >= maxCachedStatusLists {
			for k, c := range statusLists.m {
				if !now.Before(c.expires) {
					delete(statusLists.m, k)
				}
			}
			if len(statusLists.m) >= maxCachedStatusLists {
				clear(statusLists.m)
			}
		}
		statusLists.m[uri] = cachedStatusList{list: list, expires: now.Add(min(ttl, server.StatusListValidity))}
		statusLists.Unlock()
	}
	return list, nil
}

// ForgetPeerStatusList drops a kept status list, so the next check reads the
// issuer's current one.
func ForgetPeerStatusList(uri string) {
	statusLists.Lock()
	delete(statusLists.m, uri)
	statusLists.Unlock()
}

// HolderVerdict is what the server of an identity says about it now.
type HolderVerdict struct {
	Fingerprint string `json:"fingerprint"`
	Domain      string `json:"domain"`
	// State is the trust state of the identity: verified, revoked,
	// dnsMissing, spoofed, or unverified when its server could not be asked.
	State string `json:"state"`
	// Status is that server's own word: active, revoked, or unknown.
	Status string `json:"status,omitempty"`
}

// AttestationVerdict is the result of checking a presented credential.
//
// It says who attested and what, and whether every link held. It does not say
// whether the attester deserves to be believed: which domains a service
// accepts for which statement is the service's own policy.
type AttestationVerdict struct {
	State  string `json:"state"`
	Reason string `json:"reason"`

	// Issuer is the attesting domain; IssuerState how its key was tied to it.
	Issuer      string `json:"issuer,omitempty"`
	IssuerState string `json:"issuerState,omitempty"`

	Type      string         `json:"type,omitempty"`
	Claims    map[string]any `json:"claims,omitempty"`
	Withheld  int            `json:"withheld"`
	Status    string         `json:"status,omitempty"`
	IssuedAt  int64          `json:"issuedAt,omitempty"`
	ExpiresAt int64          `json:"expiresAt,omitempty"`

	Holder *HolderVerdict `json:"holder,omitempty"`
	// KeyBound is true when the presentation proved possession of the key the
	// credential names, for the audience and nonce given.
	KeyBound bool `json:"keyBound"`
}

// VerifyOptions say what a presentation is checked against.
type VerifyOptions struct {
	// Audience and Nonce are what the key binding must name. Both empty means
	// no key binding is checked, and the verdict cannot be "verified".
	Audience string
	Nonce    string
	// SkipKeyBinding is for the holder's own server looking at a credential it
	// keeps: there is no presentation to bind, and the rest of the verdict is
	// what is wanted.
	SkipKeyBinding bool
}

// credentialIssuerKey finds the key a credential was signed with: this
// server's own when it is the issuer, another server's through the trust
// chain otherwise.
func credentialIssuerKey(root *server.RootKey, domain, kid string) (*ecdsa.PublicKey, error) {
	if strings.EqualFold(domain, root.Domain()) {
		keys, err := root.Credentials()
		if err != nil {
			return nil, err
		}
		if keys.Kid() != kid {
			return nil, ErrCredentialKeyUnknown
		}
		return keys.PublicKey(), nil
	}
	return PeerCredentialKey(domain, kid)
}

func credentialStatus(app core.App, root *server.RootKey, domain string, key *ecdsa.PublicKey, ref *server.StatusRef, now time.Time) (string, error) {
	var list server.StatusList
	if strings.EqualFold(domain, root.Domain()) {
		if ref.URI != CredentialStatusURI(root.Domain()) {
			return CredentialStatusUnknown, errors.New("status list is not one this server publishes")
		}
		own, err := AttestationStatusList(app)
		if err != nil {
			return CredentialStatusUnknown, err
		}
		list = own
	} else {
		peer, err := PeerStatusList(domain, key, ref.URI, now)
		if err != nil {
			return CredentialStatusUnknown, err
		}
		list = peer
	}
	revoked, known := list.Revoked(ref.Idx)
	switch {
	case !known:
		return CredentialStatusUnknown, nil
	case revoked:
		return CredentialStatusRevoked, nil
	default:
		return CredentialStatusValid, nil
	}
}

// holderIdentityStatus asks the server of an identity whether it still
// stands behind it, as every other check of a foreign identity does.
func holderIdentityStatus(app core.App, root *server.RootKey, holder server.HolderRef, now time.Time) HolderVerdict {
	out := HolderVerdict{Fingerprint: holder.Fingerprint, Domain: holder.Domain, State: AttestationUnverified}
	domain, ok := util.NormalizePeerDomain(holder.Domain)
	if !ok || !server.ValidIdentityFingerprint(holder.Fingerprint) {
		return out
	}

	word := ""
	if strings.EqualFold(domain, root.Domain()) {
		status, err := LookupIdentityStatus(app, holder.Fingerprint)
		if err != nil {
			return out
		}
		switch {
		case status.Known && status.Status == util.StatusActive:
			word = server.IdentityStatusActive
		case status.Known:
			word = server.IdentityStatusRevoked
		default:
			word = server.IdentityStatusUnknown
		}
	} else {
		rootPub, err := PeerRootKey(domain)
		if err != nil {
			switch {
			case errors.Is(err, ErrPeerNotPinned):
				out.State = AttestationDNSMissing
			case errors.Is(err, ErrPeerKeySpoofed):
				out.State = AttestationSpoofed
			}
			return out
		}
		assertion, err := FetchPeerIdentityStatus(domain, holder.Fingerprint)
		if err != nil {
			return out
		}
		body, err := server.VerifyIdentityStatus(assertion, rootPub, domain, holder.Fingerprint, now)
		if err != nil {
			return out
		}
		word = body.Status
	}

	out.Status = word
	switch word {
	case server.IdentityStatusActive:
		out.State = AttestationVerified
	case server.IdentityStatusRevoked:
		out.State = AttestationRevoked
	}
	return out
}

// VerifyPresentation checks a presented credential along both chains: the
// attester's — DNS pin, root key, certified credential key, signature, status
// list — and the holder's — the key binding made with the key the credential
// names, and the current word of the server that issued that identity.
//
// Every failure lands on a verdict. A check that could not be completed is
// reported as unverified, never as verified and never as an error to ignore.
func VerifyPresentation(app core.App, root *server.RootKey, presentation string, opts VerifyOptions, now time.Time) AttestationVerdict {
	if len(presentation) > util.MaxCredentialLength {
		return AttestationVerdict{State: AttestationInvalid, Reason: "The presentation is too large to be a credential."}
	}
	p, err := server.ParseCredential(strings.TrimSpace(presentation))
	if err != nil {
		return AttestationVerdict{State: AttestationInvalid, Reason: "This is not a credential that can be read: " + err.Error() + "."}
	}
	issuer, _ := p.Payload["iss"].(string)
	domain, ok := CredentialIssuerDomain(issuer)
	if !ok {
		return AttestationVerdict{State: AttestationInvalid, Reason: "The credential does not name a domain as its issuer."}
	}
	verdict := AttestationVerdict{Issuer: domain}

	key, err := credentialIssuerKey(root, domain, p.Header.Kid)
	switch {
	case errors.Is(err, ErrPeerNotPinned):
		verdict.State, verdict.IssuerState = AttestationDNSMissing, AttestationDNSMissing
		verdict.Reason = "No _revoked." + domain + " TXT record was found, so no key can be tied to that domain."
		return verdict
	case errors.Is(err, ErrPeerKeySpoofed):
		verdict.State, verdict.IssuerState = AttestationSpoofed, AttestationSpoofed
		verdict.Reason = "What " + domain + " serves does not match its DNS pin or its own root key."
		return verdict
	case errors.Is(err, ErrCredentialKeyUnknown):
		verdict.State, verdict.IssuerState = AttestationUnverified, AttestationUnverified
		verdict.Reason = domain + " does not publish the key this credential was signed with."
		return verdict
	case err != nil:
		verdict.State, verdict.IssuerState = AttestationUnverified, AttestationUnverified
		verdict.Reason = domain + " could not be asked for its key: " + err.Error() + "."
		return verdict
	}

	stated, err := server.VerifyCredential(p, key, now)
	expired := errors.Is(err, server.ErrCredentialExpired)
	if err != nil && !expired {
		switch {
		case errors.Is(err, server.ErrCredentialSignature):
			verdict.State, verdict.IssuerState = AttestationSpoofed, AttestationSpoofed
			verdict.Reason = "The credential names " + domain + " as its issuer, but is not signed by that server's credential key."
		case errors.Is(err, server.ErrCredentialNotYetValid):
			verdict.State, verdict.IssuerState = AttestationInvalid, AttestationVerified
			verdict.Reason = "The credential is not valid yet."
		default:
			verdict.State = AttestationInvalid
			verdict.Reason = "This is not a credential that can be read: " + err.Error() + "."
		}
		return verdict
	}
	verdict.IssuerState = AttestationVerified
	verdict.Type = stated.Type
	verdict.Claims = stated.Claims
	verdict.Withheld = stated.Withheld
	if !stated.IssuedAt.IsZero() {
		verdict.IssuedAt = stated.IssuedAt.Unix()
	}
	if !stated.ExpiresAt.IsZero() {
		verdict.ExpiresAt = stated.ExpiresAt.Unix()
	}

	// From here on the credential is genuine. What follows decides whether it
	// still stands, and whether whoever presents it is its holder. The first
	// reason found to hold it back is the one reported.
	state, reason := AttestationVerified, ""
	hold := func(s, r string) {
		if state == AttestationVerified {
			state, reason = s, r
		}
	}

	if expired {
		hold(AttestationExpired, "The credential is genuine and has expired.")
	}

	if stated.Status != nil {
		word, err := credentialStatus(app, root, domain, key, stated.Status, now)
		verdict.Status = word
		switch {
		case err != nil:
			hold(AttestationUnverified, "The credential is signed by "+domain+
				", but its status list could not be read: "+err.Error()+".")
		case word == CredentialStatusRevoked:
			hold(AttestationRevoked, "The credential is genuine, and "+domain+" has revoked it.")
		case word == CredentialStatusUnknown:
			hold(AttestationUnverified, "The status list of "+domain+" does not reach this credential, so nothing can be said about whether it still stands.")
		}
	}

	if !opts.SkipKeyBinding {
		switch {
		case stated.HolderKey == nil:
			hold(AttestationUnverified, "The credential names no holder key, so anyone holding a copy could present it.")
		case opts.Audience == "" || opts.Nonce == "":
			hold(AttestationUnverified, "No key binding was checked: an audience and a nonce are needed to tell the holder from someone holding a copy.")
		default:
			if err := server.VerifyKeyBinding(p, *stated.HolderKey, opts.Audience, opts.Nonce, now); err != nil {
				verdict.State = AttestationInvalid
				verdict.Reason = "The presentation does not prove possession of the holder's key: " + err.Error() + "."
				if stated.Holder.Fingerprint != "" {
					verdict.Holder = &HolderVerdict{
						Fingerprint: stated.Holder.Fingerprint, Domain: stated.Holder.Domain, State: AttestationUnverified,
					}
				}
				return verdict
			}
			verdict.KeyBound = true
		}
	}

	if stated.Holder.Fingerprint != "" || stated.Holder.Domain != "" {
		holder := holderIdentityStatus(app, root, stated.Holder, now)
		verdict.Holder = &holder
		switch holder.State {
		case AttestationVerified:
		case AttestationRevoked:
			hold(AttestationRevoked, "The credential is genuine, but "+holder.Domain+
				" has revoked the identity it was issued to.")
		default:
			hold(AttestationUnverified, "The credential is genuine, but "+holder.Domain+
				" could not confirm that the identity it was issued to still stands.")
		}
	}

	if state == AttestationVerified {
		reason = domain + " attests this, its key is tied to the domain through DNS, and the credential still stands."
		if verdict.KeyBound {
			reason = domain + " attests this, its key is tied to the domain through DNS, the credential still stands, and its holder presented it."
		}
	}
	verdict.State, verdict.Reason = state, reason
	return verdict
}

// CheckIssuedCredential is the holder's server looking at a credential before
// keeping it: the issuer it was asked from signed it, and it is bound to the
// identity that asked — its key, its fingerprint and its domain. A credential
// that fails here would be refused by every verifier later, so it is refused
// now, while the holder can still ask again.
func CheckIssuedCredential(root *server.RootKey, credential, issuerDomain string, holderKey server.PublicJWK, holder server.HolderRef, now time.Time) (server.CredentialVerification, error) {
	if len(credential) > util.MaxCredentialLength {
		return server.CredentialVerification{}, errors.New("credential is too large")
	}
	p, err := server.ParseCredential(credential)
	if err != nil {
		return server.CredentialVerification{}, err
	}
	if p.KeyBinding != "" {
		return server.CredentialVerification{}, errors.New("an issued credential carries no key binding")
	}
	issuer, _ := p.Payload["iss"].(string)
	domain, ok := CredentialIssuerDomain(issuer)
	if !ok || !strings.EqualFold(domain, issuerDomain) {
		return server.CredentialVerification{}, errors.New("credential names another issuer")
	}
	key, err := credentialIssuerKey(root, domain, p.Header.Kid)
	if err != nil {
		return server.CredentialVerification{}, err
	}
	stated, err := server.VerifyCredential(p, key, now)
	if err != nil {
		return server.CredentialVerification{}, err
	}
	if stated.HolderKey == nil || !stated.HolderKey.SameKey(holderKey) {
		return server.CredentialVerification{}, errors.New("credential is bound to another key")
	}
	if !strings.EqualFold(stated.Holder.Fingerprint, holder.Fingerprint) ||
		!strings.EqualFold(stated.Holder.Domain, holder.Domain) {
		return server.CredentialVerification{}, errors.New("credential is about another identity")
	}
	return stated, nil
}
