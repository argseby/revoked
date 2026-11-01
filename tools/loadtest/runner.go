package main

import (
	"context"
	"fmt"
	"log"
	"math/rand"
	"sync"
	"time"
)

// StageResult is what one step of the ramp produced.
type StageResult struct {
	Stats     *Stats
	Container ContainerSample
	Broke     bool
	Reason    string
}

type limits struct {
	maxErrorRate float64
	maxP99       time.Duration
}

// runStage holds a fixed number of workers for the whole stage: a closed loop,
// which is how a client behaves and why latency — not throughput — is what
// moves once the server is saturated.
func runStage(ctx context.Context, sc *Scenario, fx *Fixtures, c *Caller,
	workers int, duration, reqTimeout time.Duration, seed int64) (*Stats, error) {

	states := make([]any, workers)
	if sc.Worker != nil {
		// Before the clock starts: per-worker setup is preparation, not load.
		var setupWG sync.WaitGroup
		errs := make([]error, workers)
		for i := 0; i < workers; i++ {
			setupWG.Add(1)
			go func(i int) {
				defer setupWG.Done()
				states[i], errs[i] = sc.Worker(ctx, c, fx, i)
			}(i)
		}
		setupWG.Wait()
		for i, err := range errs {
			if err != nil {
				return nil, fmt.Errorf("preparing worker %d: %w", i, err)
			}
		}
	}

	perWorker := make([]*Stats, workers)
	var wg sync.WaitGroup
	start := time.Now()
	deadline := start.Add(duration)

	for i := 0; i < workers; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			local := newStats(workers)
			r := rand.New(rand.NewSource(seed + int64(i)*7919))
			for time.Now().Before(deadline) && ctx.Err() == nil {
				// Derived from the run's context, not the stage deadline: a
				// request that started in time is allowed to finish, or the
				// last fraction of a second would score as timeouts.
				reqCtx, cancel := context.WithTimeout(ctx, reqTimeout)
				began := time.Now()
				status, n, err := sc.Do(reqCtx, c, fx, states[i], r)
				cancel()
				local.record(time.Since(began), status, err == nil && sc.accepts(status), n, err)
			}
			perWorker[i] = local
		}(i)
	}
	wg.Wait()

	total := newStats(workers)
	total.Duration = time.Since(start)
	for _, local := range perWorker {
		if local != nil {
			total.merge(local)
		}
	}
	total.seal()
	return total, nil
}

// Ramp walks the worker counts until the server breaks, and stops there: past
// the wall every further stage measures the same collapse.
func Ramp(ctx context.Context, sc *Scenario, fx *Fixtures, c *Caller, mon *Monitor,
	stages []int, duration, reqTimeout time.Duration, lim limits, keepGoing bool) ([]StageResult, error) {

	var results []StageResult
	for _, workers := range stages {
		if ctx.Err() != nil {
			break
		}
		if alive, reason := mon.Alive(ctx); !alive {
			results = append(results, StageResult{Stats: newStats(workers), Broke: true, Reason: reason})
			break
		}

		mon.Reset()
		stats, err := runStage(ctx, sc, fx, c, workers, duration, reqTimeout, int64(workers)*1_000_003)
		if err != nil {
			return results, err
		}
		result := StageResult{Stats: stats, Container: mon.Snapshot()}
		result.Broke, result.Reason = verdict(ctx, stats, mon, lim)
		results = append(results, result)
		log.Print(stageLine(sc, result))

		if result.Broke && !keepGoing {
			break
		}
	}
	return results, nil
}

// verdict decides whether this stage is past the wall. Error rate and the tail
// are the two symptoms a caller would notice; a container that is gone or was
// OOM-killed is the end of the run either way.
func verdict(ctx context.Context, s *Stats, mon *Monitor, lim limits) (bool, string) {
	if alive, reason := mon.Alive(ctx); !alive {
		return true, reason
	}
	if s.Ops == 0 {
		return true, "no operation completed"
	}
	if rate := s.ErrorRate(); rate > lim.maxErrorRate {
		return true, fmt.Sprintf("%.1f%% of operations failed (limit %.1f%%): %s",
			rate*100, lim.maxErrorRate*100, failureSummary(s))
	}
	if p99 := s.P99(); lim.maxP99 > 0 && p99 > lim.maxP99 {
		return true, fmt.Sprintf("p99 %s is over the %s budget", fmtDur(p99), fmtDur(lim.maxP99))
	}
	return false, ""
}

func failureSummary(s *Stats) string {
	parts := ""
	for kind, n := range s.ErrKinds {
		parts = appendPart(parts, fmt.Sprintf("%s ×%d", kind, n))
	}
	for code, n := range s.Statuses {
		if code < 200 || code > 299 {
			parts = appendPart(parts, fmt.Sprintf("HTTP %d ×%d", code, n))
		}
	}
	if parts == "" {
		return "no detail"
	}
	return parts
}

func appendPart(acc, part string) string {
	if acc == "" {
		return part
	}
	return acc + ", " + part
}
