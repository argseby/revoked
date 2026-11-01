package main

import (
	"fmt"
	"strings"
	"text/tabwriter"
	"time"
)

// Report collects every scenario's ramp and renders the summary a person
// reads: where throughput stopped growing, and where the server gave out.
type Report struct {
	Target    string
	Container string
	Stages    []int
	Hold      string
	Limits    string
	Started   time.Time
	Finished  time.Time

	runs []scenarioRun
}

type scenarioRun struct {
	scenario *Scenario
	results  []StageResult
}

func (r *Report) add(sc *Scenario, results []StageResult) {
	r.runs = append(r.runs, scenarioRun{scenario: sc, results: results})
}

func stageLine(sc *Scenario, result StageResult) string {
	s := result.Stats
	line := fmt.Sprintf("  %s  %4d workers  %8.1f ops/s  p50 %-7s p95 %-7s p99 %-7s err %5.1f%%",
		sc.Name, s.Workers, s.Rate(), fmtDur(s.P50()), fmtDur(s.P95()), fmtDur(s.P99()), s.ErrorRate()*100)
	if result.Container.Samples > 0 {
		line += fmt.Sprintf("  cpu %5s  mem %s", cpuCell(result.Container), humanBytes(result.Container.MemBytesMax))
	}
	if result.Broke {
		line += "   ← broke: " + result.Reason
	}
	return line
}

func (r *Report) Render() string {
	var b strings.Builder

	fmt.Fprintf(&b, "\n%s\n", strings.Repeat("=", 78))
	fmt.Fprintf(&b, "revoked load test\n")
	fmt.Fprintf(&b, "%s\n", strings.Repeat("=", 78))
	fmt.Fprintf(&b, "target      %s\n", r.Target)
	fmt.Fprintf(&b, "instance    %s\n", r.Container)
	fmt.Fprintf(&b, "ramp        %v, %s per stage\n", r.Stages, r.Hold)
	fmt.Fprintf(&b, "broken at   %s\n", r.Limits)
	fmt.Fprintf(&b, "took        %s\n\n", r.Finished.Sub(r.Started).Round(time.Second))

	for _, run := range r.runs {
		fmt.Fprintf(&b, "%s — %s\n", run.scenario.Name, run.scenario.Help)
		b.WriteString(renderTable(run.results))
		b.WriteString(verdictLine(run))
		b.WriteString("\n\n")
	}
	return b.String()
}

// cpuCell reports the peak as a share of the quota the container was given,
// which is what saturation looks like; without a quota there is nothing to
// take a share of, so it falls back to docker's per-core number.
func cpuCell(c ContainerSample) string {
	if c.QuotaPercentMax > 0 {
		return fmt.Sprintf("%.0f%% of quota", c.QuotaPercentMax)
	}
	return fmt.Sprintf("%.0f%% of a core", c.CPUPercentMax)
}

func renderTable(results []StageResult) string {
	var b strings.Builder
	w := tabwriter.NewWriter(&b, 0, 0, 2, ' ', tabwriter.AlignRight)
	fmt.Fprintln(w, "workers\tops/s\tok/s\tp50\tp95\tp99\tmax\terr%\t4xx\t5xx\tcpu\tmem\t")
	for _, result := range results {
		s := result.Stats
		cpu, mem := "-", "-"
		if result.Container.Samples > 0 {
			cpu = cpuCell(result.Container)
			mem = humanBytes(result.Container.MemBytesMax)
			if result.Container.MemLimit > 0 {
				mem += "/" + humanBytes(result.Container.MemLimit)
			}
		}
		fmt.Fprintf(w, "%d\t%.1f\t%.1f\t%s\t%s\t%s\t%s\t%.1f\t%d\t%d\t%s\t%s\t\n",
			s.Workers, s.Rate(), s.GoodRate(),
			fmtDur(s.P50()), fmtDur(s.P95()), fmtDur(s.P99()), fmtDur(s.Max()),
			s.ErrorRate()*100, s.StatusClass(4), s.StatusClass(5), cpu, mem)
	}
	w.Flush()
	return b.String()
}

// verdictLine names the two numbers worth remembering: the best sustained
// throughput, and the first stage that failed. The knee is read from the
// healthy stages only — throughput measured past the wall is noise.
func verdictLine(run scenarioRun) string {
	best, bestAt := 0.0, 0
	wall := -1
	for i, result := range run.results {
		if result.Broke {
			if wall < 0 {
				wall = i
			}
			continue
		}
		if rate := result.Stats.GoodRate(); rate > best {
			best, bestAt = rate, result.Stats.Workers
		}
	}

	if bestAt == 0 {
		return "  verdict: nothing completed — check the target and the fixtures\n"
	}
	line := fmt.Sprintf("  verdict: best sustained %.0f ops/s at %d workers", best, bestAt)
	if wall < 0 {
		line += fmt.Sprintf("; it never broke, so raise the ramp past %d workers to find the wall\n",
			run.results[len(run.results)-1].Stats.Workers)
		return line
	}
	broke := run.results[wall]
	line += fmt.Sprintf("; broke at %d workers — %s\n", broke.Stats.Workers, broke.Reason)
	if failures := failureSummary(broke.Stats); failures != "no detail" {
		line += "           failures: " + failures + "\n"
	}
	return line
}

type reportJSON struct {
	Target    string            `json:"target"`
	Container string            `json:"container"`
	Stages    []int             `json:"stages"`
	Hold      string            `json:"holdPerStage"`
	Limits    string            `json:"brokenWhen"`
	Started   time.Time         `json:"started"`
	Finished  time.Time         `json:"finished"`
	Scenarios []scenarioRunJSON `json:"scenarios"`
}

type scenarioRunJSON struct {
	Name   string            `json:"name"`
	Help   string            `json:"help"`
	Stages []stageResultJSON `json:"stages"`
}

type stageResultJSON struct {
	statsJSON
	Container ContainerSample `json:"container"`
	Broke     bool            `json:"broke"`
	Reason    string          `json:"reason,omitempty"`
}

func (r *Report) export() reportJSON {
	out := reportJSON{
		Target:    r.Target,
		Container: r.Container,
		Stages:    r.Stages,
		Hold:      r.Hold,
		Limits:    r.Limits,
		Started:   r.Started,
		Finished:  r.Finished,
	}
	for _, run := range r.runs {
		entry := scenarioRunJSON{Name: run.scenario.Name, Help: run.scenario.Help}
		for _, result := range run.results {
			entry.Stages = append(entry.Stages, stageResultJSON{
				statsJSON: result.Stats.export(),
				Container: result.Container,
				Broke:     result.Broke,
				Reason:    result.Reason,
			})
		}
		out.Scenarios = append(out.Scenarios, entry)
	}
	return out
}
