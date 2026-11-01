package main

import (
	"fmt"
	"sort"
	"time"
)

// Stats is one stage's measurement. Latencies are kept in full rather than
// bucketed: a stage is seconds long, and an exact p99 is the number the run is
// for.
type Stats struct {
	Workers   int            `json:"workers"`
	Duration  time.Duration  `json:"durationNs"`
	Ops       int            `json:"ops"`
	OK        int            `json:"ok"`
	Bytes     int64          `json:"bytes"`
	Statuses  map[int]int    `json:"statuses"`
	ErrKinds  map[string]int `json:"errorKinds"`
	latencies []time.Duration
}

func newStats(workers int) *Stats {
	return &Stats{Workers: workers, Statuses: map[int]int{}, ErrKinds: map[string]int{}}
}

func (s *Stats) merge(o *Stats) {
	s.Ops += o.Ops
	s.OK += o.OK
	s.Bytes += o.Bytes
	for k, v := range o.Statuses {
		s.Statuses[k] += v
	}
	for k, v := range o.ErrKinds {
		s.ErrKinds[k] += v
	}
	s.latencies = append(s.latencies, o.latencies...)
}

func (s *Stats) record(latency time.Duration, status int, ok bool, n int64, err error) {
	s.Ops++
	s.Bytes += n
	s.latencies = append(s.latencies, latency)
	if err != nil {
		s.ErrKinds[errKind(err)]++
		return
	}
	s.Statuses[status]++
	if ok {
		s.OK++
	}
}

func (s *Stats) seal() {
	sort.Slice(s.latencies, func(i, j int) bool { return s.latencies[i] < s.latencies[j] })
}

// Rate is completed operations per second, counting failures: a server that
// answers 500 fast is not fast.
func (s *Stats) Rate() float64 {
	if s.Duration <= 0 {
		return 0
	}
	return float64(s.Ops) / s.Duration.Seconds()
}

// GoodRate counts only the operations the scenario accepted.
func (s *Stats) GoodRate() float64 {
	if s.Duration <= 0 {
		return 0
	}
	return float64(s.OK) / s.Duration.Seconds()
}

func (s *Stats) ErrorRate() float64 {
	if s.Ops == 0 {
		return 0
	}
	return float64(s.Ops-s.OK) / float64(s.Ops)
}

func (s *Stats) Percentile(p float64) time.Duration {
	if len(s.latencies) == 0 {
		return 0
	}
	i := int(p / 100 * float64(len(s.latencies)))
	if i >= len(s.latencies) {
		i = len(s.latencies) - 1
	}
	return s.latencies[i]
}

func (s *Stats) P50() time.Duration { return s.Percentile(50) }
func (s *Stats) P95() time.Duration { return s.Percentile(95) }
func (s *Stats) P99() time.Duration { return s.Percentile(99) }
func (s *Stats) Max() time.Duration {
	if len(s.latencies) == 0 {
		return 0
	}
	return s.latencies[len(s.latencies)-1]
}

// StatusClass counts answers in the 400s and 500s separately: a flood of 4xx
// means the scenario is wrong, a flood of 5xx means the server gave up.
func (s *Stats) StatusClass(hundreds int) int {
	total := 0
	for code, n := range s.Statuses {
		if code/100 == hundreds {
			total += n
		}
	}
	return total
}

// MarshalJSON exports the percentiles rather than the raw samples, which are
// megabytes and of no use to a reader of the report.
type statsJSON struct {
	Workers   int            `json:"workers"`
	Seconds   float64        `json:"seconds"`
	Ops       int            `json:"ops"`
	OK        int            `json:"ok"`
	OpsPerSec float64        `json:"opsPerSec"`
	ErrorRate float64        `json:"errorRate"`
	P50ms     float64        `json:"p50Ms"`
	P95ms     float64        `json:"p95Ms"`
	P99ms     float64        `json:"p99Ms"`
	MaxMs     float64        `json:"maxMs"`
	Statuses  map[int]int    `json:"statuses"`
	ErrKinds  map[string]int `json:"errorKinds"`
}

func (s *Stats) export() statsJSON {
	return statsJSON{
		Workers:   s.Workers,
		Seconds:   s.Duration.Seconds(),
		Ops:       s.Ops,
		OK:        s.OK,
		OpsPerSec: s.Rate(),
		ErrorRate: s.ErrorRate(),
		P50ms:     ms(s.P50()),
		P95ms:     ms(s.P95()),
		P99ms:     ms(s.P99()),
		MaxMs:     ms(s.Max()),
		Statuses:  s.Statuses,
		ErrKinds:  s.ErrKinds,
	}
}

func ms(d time.Duration) float64 { return float64(d.Microseconds()) / 1000 }

func fmtDur(d time.Duration) string {
	switch {
	case d == 0:
		return "-"
	case d < time.Millisecond:
		return fmt.Sprintf("%dµs", d.Microseconds())
	case d < time.Second:
		return fmt.Sprintf("%.0fms", ms(d))
	default:
		return fmt.Sprintf("%.2fs", d.Seconds())
	}
}
