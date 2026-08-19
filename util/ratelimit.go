package util

import (
	"sync"
	"time"
)

// RateLimiter is a fixed-capacity sliding-window counter keyed by an arbitrary
// string (typically client IP, or IP+slug for per-resource limits).
//
// State is per-process, so a horizontally scaled deployment multiplies the
// configured limits by the instance count.
type RateLimiter struct {
	mu     sync.Mutex
	hits   map[string][]time.Time
	limit  int
	window time.Duration
	lastGC time.Time
}

// NewRateLimiter returns a limiter permitting limit events per key per window.
func NewRateLimiter(limit int, window time.Duration) *RateLimiter {
	return &RateLimiter{
		hits:   make(map[string][]time.Time),
		limit:  limit,
		window: window,
		lastGC: time.Now(),
	}
}

// Allow records an attempt for key and reports whether it is within the limit.
// A rejected attempt is not recorded, so a caller hammering a blocked key cannot
// extend its own penalty window.
func (r *RateLimiter) Allow(key string) bool {
	if r == nil || r.limit <= 0 {
		return true
	}
	now := time.Now()
	cutoff := now.Add(-r.window)

	r.mu.Lock()
	defer r.mu.Unlock()
	r.gcLocked(now)

	kept := r.hits[key][:0]
	for _, t := range r.hits[key] {
		if t.After(cutoff) {
			kept = append(kept, t)
		}
	}
	if len(kept) >= r.limit {
		r.hits[key] = kept
		return false
	}
	r.hits[key] = append(kept, now)
	return true
}

// Reset clears the history for key, e.g. after a successful authentication.
func (r *RateLimiter) Reset(key string) {
	if r == nil {
		return
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	delete(r.hits, key)
}

// gcLocked drops entirely-expired keys so the map cannot grow without bound
// under slug enumeration. The caller must hold the mutex.
func (r *RateLimiter) gcLocked(now time.Time) {
	if now.Sub(r.lastGC) < r.window {
		return
	}
	r.lastGC = now
	cutoff := now.Add(-r.window)
	for key, times := range r.hits {
		newest := time.Time{}
		for _, t := range times {
			if t.After(newest) {
				newest = t
			}
		}
		if !newest.After(cutoff) {
			delete(r.hits, key)
		}
	}
}
