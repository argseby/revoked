package routes

import (
	"net/http"
	"revoked/util"
	"sync"
	"time"

	"github.com/pocketbase/pocketbase/core"
)

// challengeTTL bounds the replay window for an issued nonce.
const challengeTTL = 2 * time.Minute

// challengeStore is deliberately in-process: nonces are single-use and short-lived,
// so re-minting them on a new instance is cheap. Horizontal scaling requires moving
// it to a shared store.
var challengeStore = &challengeRegistry{
	entries: make(map[string]challengeEntry),
}

type challengeEntry struct {
	Scope      string
	Slug       string
	IdentityId string
	ExpiresAt  time.Time
}

type challengeRegistry struct {
	mu      sync.Mutex
	entries map[string]challengeEntry
}

func (r *challengeRegistry) issue(scope, slug, identityId string) (string, time.Time, error) {
	nonce, err := util.GenerateToken(32)
	if err != nil {
		return "", time.Time{}, err
	}
	exp := time.Now().Add(challengeTTL)
	r.mu.Lock()
	defer r.mu.Unlock()
	r.gcLocked()
	r.entries[nonce] = challengeEntry{
		Scope:      scope,
		Slug:       slug,
		IdentityId: identityId,
		ExpiresAt:  exp,
	}
	return nonce, exp, nil
}

// consume removes the nonce as it checks it, so one is never accepted twice.
func (r *challengeRegistry) consume(nonce, scope, slug, identityId string) bool {
	r.mu.Lock()
	defer r.mu.Unlock()
	entry, ok := r.entries[nonce]
	if !ok {
		return false
	}
	delete(r.entries, nonce)
	if time.Now().After(entry.ExpiresAt) {
		return false
	}
	if entry.Scope != scope || entry.Slug != slug || entry.IdentityId != identityId {
		return false
	}
	return true
}

func (r *challengeRegistry) gcLocked() {
	now := time.Now()
	for n, e := range r.entries {
		if now.After(e.ExpiresAt) {
			delete(r.entries, n)
		}
	}
}

// IssueChallenge mints a single-use nonce bound to a scope, slug and identity.
func IssueChallenge(scope, slug, identityId string) (string, time.Time, error) {
	return challengeStore.issue(scope, slug, identityId)
}

// ConsumeChallenge reports whether the nonce matches and is unexpired, removing it
// either way to enforce single use.
func ConsumeChallenge(nonce, scope, slug, identityId string) bool {
	return challengeStore.consume(nonce, scope, slug, identityId)
}

// ChallengeRoute exposes GET /api/challenges/{scope}/{slug}?identityId=..., which
// mints a one-shot nonce the client signs to prove key possession on submission.
//
// It deliberately does not check that the slug exists: responding uniformly avoids
// leaking existence, and invalid identities are rejected at submission.
func ChallengeRoute(app core.App) {
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		e.Router.GET("/api/challenges/{scope}/{slug}", func(re *core.RequestEvent) error {
			// Each nonce holds registry memory until it expires, so unthrottled
			// issuance is a memory-growth vector as well as an enumeration aid.
			if !allowRequest(re, challengeLimiter, "") {
				return rateLimitedResponse(re)
			}
			scope := re.Request.PathValue("scope")
			slug := re.Request.PathValue("slug")
			identityId := re.Request.URL.Query().Get("identityId")
			guestFp := re.Request.URL.Query().Get("guestFingerprint")

			switch scope {
			case "link", "request":
				if identityId == "" {
					return re.BadRequestError("identityId is required for this scope", nil)
				}
			case "request_guest":
				if guestFp == "" {
					return re.BadRequestError("guestFingerprint is required for this scope", nil)
				}
			default:
				return re.BadRequestError("unknown scope", nil)
			}
			if slug == "" {
				return re.BadRequestError("slug is required", nil)
			}

			subject := identityId
			if subject == "" {
				subject = guestFp
			}
			nonce, exp, err := IssueChallenge(scope, slug, subject)
			if err != nil {
				return re.InternalServerError("Failed to issue challenge", nil)
			}

			return re.JSON(http.StatusOK, map[string]any{
				"nonce":     nonce,
				"expiresAt": exp.UTC().Format(time.RFC3339),
				"algorithm": "RSA-SHA256",
			})
		})

		return e.Next()
	})
}
