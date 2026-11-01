package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os/exec"
	"strconv"
	"strings"
	"sync"
	"time"
)

// Monitor watches the container under test from the outside. Without it a
// report says the server got slow but not whether it ran out of CPU, out of
// memory, or was killed.
type Monitor struct {
	name string

	quotaCores float64
	memCeiling float64
	noSwap     bool

	mu       sync.Mutex
	cpu      []float64
	mem      []float64
	memLimit float64
}

// ContainerSample is what the container did during one stage. The CPU figures
// are docker's, where 100% is one core; QuotaPercentMax restates the peak as a
// share of the quota the container was given, which is the number that says
// whether it ran out of CPU.
type ContainerSample struct {
	CPUPercentAvg   float64 `json:"cpuPercentAvg"`
	CPUPercentMax   float64 `json:"cpuPercentMax"`
	QuotaPercentMax float64 `json:"quotaPercentMax"`
	MemBytesAvg     float64 `json:"memBytesAvg"`
	MemBytesMax     float64 `json:"memBytesMax"`
	MemLimit        float64 `json:"memLimitBytes"`
	Samples         int     `json:"samples"`
}

func NewMonitor(name string) *Monitor { return &Monitor{name: name} }

// Prime reads the caps the container was created with, so a stage can be
// reported against the box it was given rather than against the host.
func (m *Monitor) Prime(ctx context.Context) {
	if m.name == "" {
		return
	}
	out, err := exec.CommandContext(ctx, "docker", "inspect",
		"--format", "{{.HostConfig.NanoCpus}}|{{.HostConfig.Memory}}|{{.HostConfig.MemorySwap}}", m.name).Output()
	if err != nil {
		return
	}
	parts := strings.Split(strings.TrimSpace(string(out)), "|")
	if len(parts) != 3 {
		return
	}
	if n, convErr := strconv.ParseFloat(parts[0], 64); convErr == nil && n > 0 {
		m.quotaCores = n / 1e9
	}
	if n, convErr := strconv.ParseFloat(parts[1], 64); convErr == nil && n > 0 {
		m.memCeiling = n
	}
	if n, convErr := strconv.ParseFloat(parts[2], 64); convErr == nil {
		m.noSwap = m.memCeiling > 0 && n == m.memCeiling
	}
}

// Watch samples until ctx ends. A disabled monitor (no container name) still
// satisfies the interface the ramp calls, so a run against an uncapped server
// elsewhere needs no special case.
func (m *Monitor) Watch(ctx context.Context, interval time.Duration) {
	if m.name == "" {
		return
	}
	for {
		select {
		case <-ctx.Done():
			return
		default:
		}
		m.sample(ctx)
		select {
		case <-ctx.Done():
			return
		case <-time.After(interval):
		}
	}
}

func (m *Monitor) sample(ctx context.Context) {
	// --no-stream takes two readings internally, so this call blocks about a
	// second; that is the sampling floor, not a bug.
	out, err := exec.CommandContext(ctx, "docker", "stats", "--no-stream", "--format", "{{json .}}", m.name).Output()
	if err != nil {
		return
	}
	var row struct {
		CPUPerc  string `json:"CPUPerc"`
		MemUsage string `json:"MemUsage"`
	}
	if err := json.Unmarshal(out, &row); err != nil {
		return
	}
	cpu, cpuOK := parsePercent(row.CPUPerc)
	used, limit, memOK := parseMemUsage(row.MemUsage)

	m.mu.Lock()
	defer m.mu.Unlock()
	if cpuOK {
		m.cpu = append(m.cpu, cpu)
	}
	if memOK {
		m.mem = append(m.mem, used)
		m.memLimit = limit
	}
}

func (m *Monitor) Reset() {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.cpu = nil
	m.mem = nil
}

func (m *Monitor) Snapshot() ContainerSample {
	m.mu.Lock()
	defer m.mu.Unlock()
	sample := ContainerSample{
		CPUPercentAvg: mean(m.cpu),
		CPUPercentMax: peak(m.cpu),
		MemBytesAvg:   mean(m.mem),
		MemBytesMax:   peak(m.mem),
		MemLimit:      m.memLimit,
		Samples:       len(m.cpu),
	}
	if m.quotaCores > 0 {
		sample.QuotaPercentMax = sample.CPUPercentMax / m.quotaCores
	}
	return sample
}

// Alive reports whether the container is still serving, and says why not when
// it is not. An OOM kill is the answer the run was looking for, so it is named
// rather than reported as a wall of connection errors.
func (m *Monitor) Alive(ctx context.Context) (bool, string) {
	if m.name == "" {
		return true, ""
	}
	out, err := exec.CommandContext(ctx, "docker", "inspect",
		"--format", "{{.State.Status}}|{{.State.OOMKilled}}|{{.State.ExitCode}}|{{.RestartCount}}", m.name).Output()
	if err != nil {
		return false, "container is gone (docker inspect failed)"
	}
	parts := strings.Split(strings.TrimSpace(string(out)), "|")
	if len(parts) != 4 {
		return true, ""
	}
	status, oom, exitCode, restarts := parts[0], parts[1] == "true", parts[2], parts[3]
	switch {
	case oom:
		return false, "the kernel OOM-killed the server (memory ceiling reached)"
	case status != "running":
		return false, fmt.Sprintf("the server is %s (exit code %s)", status, exitCode)
	case restarts != "0":
		return false, fmt.Sprintf("the server restarted %s time(s)", restarts)
	}
	return true, ""
}

// Report describes what the container was given, for the top of the report.
func (m *Monitor) Report() string {
	if m.name == "" {
		return "no container monitored"
	}
	cpus := "uncapped CPU"
	if m.quotaCores > 0 {
		cpus = fmt.Sprintf("%.2g cores", m.quotaCores)
	}
	memory := "uncapped memory"
	if m.memCeiling > 0 {
		memory = humanBytes(m.memCeiling)
	}
	swap := ""
	if m.noSwap {
		swap = ", no swap"
	}
	return fmt.Sprintf("%s — %s, %s%s", m.name, cpus, memory, swap)
}

func parsePercent(raw string) (float64, bool) {
	v, err := strconv.ParseFloat(strings.TrimSuffix(strings.TrimSpace(raw), "%"), 64)
	return v, err == nil
}

// parseMemUsage reads docker's "41.2MiB / 512MiB".
func parseMemUsage(raw string) (used, limit float64, ok bool) {
	parts := strings.Split(raw, "/")
	if len(parts) != 2 {
		return 0, 0, false
	}
	used, usedOK := parseSize(parts[0])
	limit, limitOK := parseSize(parts[1])
	return used, limit, usedOK && limitOK
}

var sizeUnits = []struct {
	suffix string
	factor float64
}{
	{"GiB", 1 << 30}, {"MiB", 1 << 20}, {"KiB", 1 << 10},
	{"GB", 1e9}, {"MB", 1e6}, {"kB", 1e3}, {"B", 1},
}

func parseSize(raw string) (float64, bool) {
	s := strings.TrimSpace(raw)
	for _, unit := range sizeUnits {
		if strings.HasSuffix(s, unit.suffix) {
			v, err := strconv.ParseFloat(strings.TrimSpace(strings.TrimSuffix(s, unit.suffix)), 64)
			return v * unit.factor, err == nil
		}
	}
	return 0, false
}

func humanBytes(n float64) string {
	switch {
	case n >= 1<<30:
		return fmt.Sprintf("%.2fGiB", n/(1<<30))
	case n >= 1<<20:
		return fmt.Sprintf("%.0fMiB", n/(1<<20))
	case n >= 1<<10:
		return fmt.Sprintf("%.0fKiB", n/(1<<10))
	default:
		return fmt.Sprintf("%.0fB", n)
	}
}

func mean(values []float64) float64 {
	if len(values) == 0 {
		return 0
	}
	sum := 0.0
	for _, v := range values {
		sum += v
	}
	return sum / float64(len(values))
}

func peak(values []float64) float64 {
	highest := 0.0
	for _, v := range values {
		if v > highest {
			highest = v
		}
	}
	return highest
}
