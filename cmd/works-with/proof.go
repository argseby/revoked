package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"time"

	"revoked/util"
)

// ProofPath is where a service confirms its entry. The file proves control of
// the domain and nothing else: its only fields are the entry's slug and
// origin, and `listed: false` to opt out. It never supplies texts or
// permissions, so whoever controls the domain later cannot change what the
// listing says.
const ProofPath = "/.well-known/revoked-listing.json"

// Proof is the file's content.
type Proof struct {
	Listing string `json:"listing"`
	Origin  string `json:"origin"`
	Listed  *bool  `json:"listed,omitempty"`
}

// ProofState is what an online check found for one entry.
type ProofState int

const (
	// ProofMissing: no file, or not one that names this entry. The entry
	// can be listed, as Unverified.
	ProofMissing ProofState = iota
	// ProofMatches: the file names exactly this slug and origin.
	ProofMatches
	// ProofOptOut: the file names this entry and says listed: false.
	ProofOptOut
)

func (s ProofState) String() string {
	switch s {
	case ProofMatches:
		return "matches"
	case ProofOptOut:
		return "opted out"
	default:
		return "missing"
	}
}

// Finding is the result of checking one entry against its origin.
type Finding struct {
	Slug      string
	Reachable bool
	Proof     ProofState
	// Problem is what the owner has to act on, empty when the entry is as
	// it should be.
	Problem string
}

const maxProofBytes = 4 << 10

// Checker fetches origins and proof files. Requests go through the server's
// SSRF-hardened client: no redirects, no private addresses.
type Checker struct {
	Client *http.Client
}

func NewChecker() *Checker {
	return &Checker{Client: util.NewSafeCallbackClient(15 * time.Second)}
}

// Check compares what the origin shows with what the entry claims.
func (c *Checker) Check(ctx context.Context, e *Entry) Finding {
	f := Finding{Slug: e.Slug}
	f.Reachable = c.reachable(ctx, e.Origin)
	f.Proof = c.proof(ctx, e)

	switch {
	case f.Proof == ProofOptOut:
		f.Problem = "the service opted out (listed: false); remove the entry"
	case e.Verified && f.Proof != ProofMatches:
		f.Problem = "marked verified, but " + ProofPath + " is missing or no longer matches; set verified: false and review the entry: this is what a change of hands looks like"
	case !e.Verified && f.Proof == ProofMatches:
		f.Problem = "the proof file matches; the entry can be set to verified: true"
	case !f.Reachable && e.Status != "unavailable":
		f.Problem = "the origin does not answer; set status: unavailable, and remove the entry after 30 days"
	case f.Reachable && e.Status == "unavailable":
		f.Problem = "the origin answers again; the status can go back to listed"
	}
	return f
}

func (c *Checker) reachable(ctx context.Context, origin string) bool {
	resp, err := c.get(ctx, origin+"/")
	if err != nil {
		return false
	}
	defer resp.Body.Close()
	_, _ = io.Copy(io.Discard, io.LimitReader(resp.Body, 64<<10))
	// A redirect is an answer too: plenty of sites send / elsewhere.
	return resp.StatusCode < 500
}

func (c *Checker) proof(ctx context.Context, e *Entry) ProofState {
	resp, err := c.get(ctx, e.Origin+ProofPath)
	if err != nil {
		return ProofMissing
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return ProofMissing
	}
	p, err := ParseProof(io.LimitReader(resp.Body, maxProofBytes+1))
	if err != nil {
		return ProofMissing
	}
	return p.StateFor(e)
}

func (c *Checker) get(ctx context.Context, url string) (*http.Response, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", "works-with-revoked-check")
	req.Header.Set("Accept", "application/json, text/html;q=0.5")
	return c.Client.Do(req)
}

// ParseProof reads a proof file, refusing one that is too large.
func ParseProof(r io.Reader) (*Proof, error) {
	data, err := io.ReadAll(r)
	if err != nil {
		return nil, err
	}
	if len(data) > maxProofBytes {
		return nil, errors.New("proof file is larger than 4 KiB")
	}
	var p Proof
	if err := json.Unmarshal(data, &p); err != nil {
		return nil, fmt.Errorf("proof file is not JSON: %w", err)
	}
	return &p, nil
}

// StateFor tells whether the proof confirms [e]. Both values must match
// exactly; anything else in the file is ignored.
func (p *Proof) StateFor(e *Entry) ProofState {
	if p.Listing != e.Slug || p.Origin != e.Origin {
		return ProofMissing
	}
	if p.Listed != nil && !*p.Listed {
		return ProofOptOut
	}
	return ProofMatches
}
