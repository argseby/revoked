// Command loadtest drives a revoked instance up a ramp of concurrency until it
// breaks, and says what broke: the error rate, the tail latency, or the
// container's CPU and memory ceiling.
//
// It is meant to run against deploy/loadtest/docker-compose.yml, whose CPU and
// memory caps are the point — a wall you chose is reproducible, the host's is
// not. tools/loadtest/run.sh wires the two together.
package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"syscall"
	"time"
)

func main() {
	var (
		baseURL   = flag.String("url", "http://127.0.0.1:3100", "base URL of the instance under test")
		hostName  = flag.String("host", "", "Host header to send (default: localhost with the URL's port, which is the only name a passkey binds to over http)")
		scenario  = flag.String("scenario", "mixed", "scenario to run, or 'all'")
		stageList = flag.String("stages", "2,5,10,25,50,100,200,400", "comma-separated worker counts to walk")
		duration  = flag.Duration("duration", 20*time.Second, "how long to hold each stage")
		timeout   = flag.Duration("timeout", 30*time.Second, "per-operation timeout")
		boot      = flag.Duration("wait", 90*time.Second, "how long to wait for the instance to answer /healthz")

		users    = flag.Int("users", 8, "accounts to seed")
		records  = flag.Int("records", 5, "vault records per account")
		links    = flag.Int("links", 3, "shares per account")
		requests = flag.Int("requests", 2, "requests per account")

		container    = flag.String("container", "revoked-loadtest-api", "container to sample CPU and memory from (empty to skip)")
		maxErrorRate = flag.Float64("max-error-rate", 0.02, "fraction of failed operations that counts as broken")
		maxP99       = flag.Duration("max-p99", 2*time.Second, "p99 that counts as broken (0 to ignore)")
		keepGoing    = flag.Bool("keep-going", false, "keep ramping after the server breaks")
		out          = flag.String("out", "", "write the full report as JSON to this path")
		list         = flag.Bool("list", false, "list the scenarios and exit")
	)
	flag.Parse()
	log.SetFlags(0)

	if *list {
		for _, name := range scenarioNames() {
			fmt.Printf("  %-12s %s\n", name, scenarios[name].Help)
		}
		return
	}

	chosen, err := chooseScenarios(*scenario)
	if err != nil {
		log.Fatal(err)
	}
	stages, err := parseStages(*stageList)
	if err != nil {
		log.Fatal(err)
	}

	host := *hostName
	if host == "" {
		host = passkeyHost(*baseURL)
	}

	// The registration ceremony in tests/testutils goes through
	// http.DefaultClient, so the signup and signin scenarios are capped by its
	// two idle connections per host unless this is raised.
	if transport, ok := http.DefaultTransport.(*http.Transport); ok {
		transport.MaxIdleConnsPerHost = stages[len(stages)-1] + 8
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	caller := NewCaller(*baseURL, host, stages[len(stages)-1], *timeout)

	log.Printf("waiting for %s", *baseURL)
	if err := waitHealthy(ctx, caller, *boot); err != nil {
		log.Fatalf("the instance never answered: %v", err)
	}

	monitor := NewMonitor(*container)
	monitor.Prime(ctx)
	monCtx, stopMonitor := context.WithCancel(ctx)
	go monitor.Watch(monCtx, time.Second)
	defer stopMonitor()

	fixtures, err := Seed(ctx, caller, seedConfig{
		users:           *users,
		recordsPerUser:  *records,
		linksPerUser:    *links,
		requestsPerUser: *requests,
	})
	if err != nil {
		log.Fatalf("seeding failed: %v", err)
	}

	report := &Report{
		Target:    *baseURL,
		Container: monitor.Report(),
		Stages:    stages,
		Hold:      duration.String(),
		Limits:    fmt.Sprintf("error rate > %.1f%% or p99 > %s", *maxErrorRate*100, fmtDur(*maxP99)),
		Started:   time.Now(),
	}

	for _, sc := range chosen {
		if missing := sc.missingFixtures(fixtures); missing != "" {
			log.Printf("skipping %s: it needs %s", sc.Name, missing)
			continue
		}
		log.Printf("\n%s — %s", sc.Name, sc.Help)
		results, err := Ramp(ctx, sc, fixtures, caller, monitor, stages, *duration, *timeout,
			limits{maxErrorRate: *maxErrorRate, maxP99: *maxP99}, *keepGoing)
		report.add(sc, results)
		if err != nil {
			log.Printf("%s stopped early: %v", sc.Name, err)
		}
		if ctx.Err() != nil {
			break
		}
	}

	report.Finished = time.Now()
	fmt.Print(report.Render())

	if *out != "" {
		payload, err := json.MarshalIndent(report.export(), "", "  ")
		if err != nil {
			log.Fatalf("could not build the JSON report: %v", err)
		}
		if err := os.WriteFile(*out, payload, 0o644); err != nil {
			log.Fatalf("could not write %s: %v", *out, err)
		}
		log.Printf("JSON report: %s", *out)
	}
}

func chooseScenarios(name string) ([]*Scenario, error) {
	if name == "all" {
		var all []*Scenario
		for _, n := range scenarioNames() {
			all = append(all, scenarios[n])
		}
		return all, nil
	}
	var chosen []*Scenario
	for _, n := range strings.Split(name, ",") {
		sc, ok := scenarios[strings.TrimSpace(n)]
		if !ok {
			return nil, fmt.Errorf("unknown scenario %q; -list shows them all", n)
		}
		chosen = append(chosen, sc)
	}
	return chosen, nil
}

func parseStages(raw string) ([]int, error) {
	var stages []int
	for _, field := range strings.Split(raw, ",") {
		n, err := strconv.Atoi(strings.TrimSpace(field))
		if err != nil || n < 1 {
			return nil, fmt.Errorf("%q is not a worker count", field)
		}
		stages = append(stages, n)
	}
	if len(stages) == 0 {
		return nil, fmt.Errorf("no stages given")
	}
	return stages, nil
}

// passkeyHost returns the name to send as Host. A passkey is bound to a
// hostname and only "localhost" is allowed over plain http, so dialing the
// loopback IP needs that name in the header — exactly what the browser does.
func passkeyHost(raw string) string {
	parsed, err := url.Parse(raw)
	if err != nil {
		return ""
	}
	name := parsed.Hostname()
	if net.ParseIP(name) == nil {
		return parsed.Host
	}
	if port := parsed.Port(); port != "" {
		return "localhost:" + port
	}
	return "localhost"
}

func waitHealthy(ctx context.Context, c *Caller, within time.Duration) error {
	deadline := time.Now().Add(within)
	for {
		probeCtx, cancel := context.WithTimeout(ctx, 2*time.Second)
		status, _, err := c.GET(probeCtx, "/healthz", "")
		cancel()
		if err == nil && status == http.StatusOK {
			return nil
		}
		if ctx.Err() != nil {
			return ctx.Err()
		}
		if time.Now().After(deadline) {
			if err != nil {
				return err
			}
			return fmt.Errorf("/healthz answered %d", status)
		}
		time.Sleep(500 * time.Millisecond)
	}
}
