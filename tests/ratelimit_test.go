package tests

import (
	"revoked/util"
	"sync"
	"testing"
	"time"
)

func TestRateLimiterAllowsUpToLimit(t *testing.T) {
	r := util.NewRateLimiter(3, time.Minute)

	for i := 1; i <= 3; i++ {
		if !r.Allow("ip") {
			t.Fatalf("attempt %d should be allowed within a limit of 3", i)
		}
	}
	if r.Allow("ip") {
		t.Fatal("the 4th attempt should be refused")
	}
}

func TestRateLimiterIsPerKey(t *testing.T) {
	r := util.NewRateLimiter(1, time.Minute)

	if !r.Allow("a") || !r.Allow("b") {
		t.Fatal("distinct keys must not share a budget")
	}
	if r.Allow("a") {
		t.Fatal("key a should be exhausted")
	}
}

func TestRateLimiterDoesNotExtendItsOwnPenalty(t *testing.T) {
	r := util.NewRateLimiter(1, 50*time.Millisecond)

	if !r.Allow("ip") {
		t.Fatal("first attempt should be allowed")
	}
	for i := 0; i < 5; i++ {
		if r.Allow("ip") {
			t.Fatal("attempts within the window should be refused")
		}
	}

	time.Sleep(60 * time.Millisecond)
	if !r.Allow("ip") {
		t.Fatal("the budget should recover once the window has passed")
	}
}

func TestRateLimiterResetClearsKey(t *testing.T) {
	r := util.NewRateLimiter(1, time.Minute)

	r.Allow("ip")
	if r.Allow("ip") {
		t.Fatal("key should be exhausted before reset")
	}
	r.Reset("ip")
	if !r.Allow("ip") {
		t.Fatal("Reset should clear the key's history")
	}
}

// A zero limit is the documented opt-out for test harnesses and trusted
// deployments.
func TestRateLimiterZeroLimitAllowsEverything(t *testing.T) {
	r := util.NewRateLimiter(0, time.Minute)
	for i := 0; i < 100; i++ {
		if !r.Allow("ip") {
			t.Fatal("a zero limit must never refuse")
		}
	}
}

func TestRateLimiterIsConcurrencySafe(t *testing.T) {
	const goroutines = 50
	r := util.NewRateLimiter(10, time.Minute)

	var wg sync.WaitGroup
	var mu sync.Mutex
	allowed := 0

	for i := 0; i < goroutines; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if r.Allow("shared") {
				mu.Lock()
				allowed++
				mu.Unlock()
			}
		}()
	}
	wg.Wait()

	if allowed != 10 {
		t.Fatalf("expected exactly 10 of %d concurrent attempts to be allowed, got %d", goroutines, allowed)
	}
}
