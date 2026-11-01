package routes

import (
	"testing"
	"time"

	"revoked/cmd/revoked/server"
)

func assertion(signature string) server.IdentityStatusAssertion {
	return server.IdentityStatusAssertion{Payload: "payload", Signature: signature}
}

func TestStatusAssertionCacheReusesOneSignature(t *testing.T) {
	cache := &statusAssertionCache{entries: make(map[string]statusAssertionEntry)}
	window := time.Now().Add(statusAssertionTTL)

	cache.keep("key", assertion("first"), window)

	got, ok := cache.lookup("key")
	if !ok {
		t.Fatal("the answer was not kept")
	}
	if got.Signature != "first" {
		t.Fatalf("kept %q, got %q", "first", got.Signature)
	}
}

// A different answer about the same identity is a different key, which is what
// makes a revocation visible on the next request without invalidating anything.
func TestStatusAssertionCacheMissesOnADifferentAnswer(t *testing.T) {
	cache := &statusAssertionCache{entries: make(map[string]statusAssertionEntry)}
	window := time.Now().Add(statusAssertionTTL)

	cache.keep("fingerprint\x00active", assertion("active"), window)

	if _, ok := cache.lookup("fingerprint\x00revoked"); ok {
		t.Fatal("a revoked answer was served from the entry minted while active")
	}
}

func TestStatusAssertionCacheDropsEarlierWindows(t *testing.T) {
	cache := &statusAssertionCache{entries: make(map[string]statusAssertionEntry)}
	first := time.Now()

	cache.keep("old", assertion("old"), first.Add(statusAssertionTTL))
	cache.keep("new", assertion("new"), first.Add(2*statusAssertionTTL))

	if _, ok := cache.lookup("old"); ok {
		t.Fatal("an entry from an earlier window survived")
	}
	if _, ok := cache.lookup("new"); !ok {
		t.Fatal("the entry just written is gone")
	}
}

// The cap is what keeps an instance with a great many live identities from
// growing the map without end.
func TestStatusAssertionCacheStopsAtTheCap(t *testing.T) {
	cache := &statusAssertionCache{entries: make(map[string]statusAssertionEntry)}
	window := time.Now().Add(statusAssertionTTL)

	for i := 0; i < statusAssertionCap; i++ {
		cache.keep(string(rune(i))+"-key", assertion("kept"), window)
	}
	if len(cache.entries) != statusAssertionCap {
		t.Fatalf("expected %d entries, got %d", statusAssertionCap, len(cache.entries))
	}

	cache.keep("one-too-many", assertion("refused"), window)
	if _, ok := cache.lookup("one-too-many"); ok {
		t.Fatal("the cache grew past its cap")
	}
	if len(cache.entries) != statusAssertionCap {
		t.Fatalf("the cache holds %d entries, past its cap of %d", len(cache.entries), statusAssertionCap)
	}
}

// Replacing an answer must keep working at the cap, or an identity whose status
// changes on a full cache would never be re-signed within its window.
func TestStatusAssertionCacheReplacesAtTheCap(t *testing.T) {
	cache := &statusAssertionCache{entries: make(map[string]statusAssertionEntry)}
	window := time.Now().Add(statusAssertionTTL)

	for i := 0; i < statusAssertionCap; i++ {
		cache.keep(string(rune(i))+"-key", assertion("kept"), window)
	}

	existing := string(rune(0)) + "-key"
	cache.keep(existing, assertion("replaced"), window)

	got, ok := cache.lookup(existing)
	if !ok {
		t.Fatal("the replaced entry is gone")
	}
	if got.Signature != "replaced" {
		t.Fatalf("expected the replacement, got %q", got.Signature)
	}
}
