# Load testing

Find out how much traffic one instance takes, and what gives out first, on a
box whose size you chose.

The harness is two halves:

- `deploy/loadtest/docker-compose.yml` runs the API in a container with a hard
  CPU quota, a hard memory ceiling and no swap.
- `tools/loadtest` seeds that instance over the public API, then holds a fixed
  number of concurrent callers against it, raising the number stage by stage
  until the server breaks.

```bash
./tools/loadtest/run.sh
```

That starts a 1-core, 512 MB instance on `127.0.0.1:3100`, seeds 8 accounts
with shares and requests, walks 2 → 400 concurrent callers at 20 seconds a
stage, prints the report and removes the container.

## Choosing the box

```bash
CPUS=0.5 MEMORY=256m ./tools/loadtest/run.sh     # a small VPS
CPUS=2   MEMORY=1g   ./tools/loadtest/run.sh     # a modest server
```

`CPUS` is a quota in cores, so `0.5` is half a core and fractions are real.
`MEMORY` is the ceiling; swap is pinned to the same value, so running out of
memory ends as an OOM kill the report names rather than as swap thrash you
have to guess at. The run also sets `GOMEMLIMIT` to 85% of the ceiling, giving
the collector room to react before the kernel steps in.

## Choosing the traffic

```bash
./tools/loadtest/run.sh -list                    # what each scenario does
SCENARIO=view ./tools/loadtest/run.sh            # one path
SCENARIO=all DURATION=10s ./tools/loadtest/run.sh
```

| Scenario | What it costs the server |
|---|---|
| `health` | routing and nothing else — the ceiling the rest is measured against |
| `probe` | an unauthenticated slug lookup |
| `page` | the same, plus rendering the share page |
| `view` | resolving a share: the records, and the atomic view claim (a write) |
| `vault-list` | a JWT to verify, then a rule-filtered query |
| `vault-write` | a write with its hooks and its audit row |
| `respond` | answering somebody else's request — the heaviest write path |
| `signup` | a whole passkey registration per operation |
| `signin` | a whole passkey sign-in per operation |
| `mixed` | 40% probe, 25% view, 15% page, 13% list, 7% write |

Start with `mixed` for a capacity number, then run the scenario that broke
first on its own to see how far it is from the others.

## Reading the report

```
view — POST /api/public/links/{slug} — resolve a share and claim a view
 workers   ops/s    ok/s      p50     p95     p99     max   err%  4xx  5xx            cpu           mem
       2   412.0   412.0      4ms     7ms    11ms    24ms    0.0    0    0   48% of quota  38MiB/512MiB
      10   602.4   602.4     16ms    28ms    41ms    88ms    0.0    0    0   97% of quota  44MiB/512MiB
      50   611.9   611.9     81ms   140ms   190ms   410ms    0.0    0    0   99% of quota  61MiB/512MiB
     200   598.1   521.0    330ms   890ms   2.10s   6.40s   12.9    0  412   99% of quota 102MiB/512MiB
  verdict: best sustained 612 ops/s at 50 workers; broke at 200 workers — 12.9% of operations failed
```

- **ops/s** counts every answer, **ok/s** only the ones the scenario accepted.
  A server answering 500 quickly is not fast.
- Throughput stops growing at the knee; past it, added callers only add
  latency. That plateau is the instance's capacity.
- **4xx** means the scenario asked for something wrong — a seeding problem, or
  a rate limiter you left on. **5xx**, timeouts and connection errors mean the
  server ran out.
- **cpu** is the peak as a share of the quota you gave the container. Near
  100% means more cores would help. Well under it, with latency climbing
  anyway, means the bottleneck is elsewhere — usually a lock or the disk.
- The ramp stops at the first broken stage. `-keep-going` walks the rest.

What counts as broken is `-max-error-rate` (default 2%) and `-max-p99`
(default 2s), plus anything that takes the container down. Both are
thresholds, not truths: set them to what you would actually promise.

`REPORT=report.json ./tools/loadtest/run.sh` writes every stage as JSON, for
comparing two runs or two commits.

## What the numbers are and are not

The generator runs on the same machine as the server, so it competes for the
host's spare cores. Cap the server well below what the host has — one or two
cores out of eight — or you are measuring the two of them fighting.

Every public rate limiter is **off** in this instance. A real deployment
refuses the enumeration and brute-force traffic these scenarios generate long
before capacity matters, which is the point of the limiters; leaving them on
here would measure them instead of the server. For the same reason the compose
file binds to `127.0.0.1` and must never be used as a deployment template.

The instance stores its data on a Docker volume, wiped before every run. The
scenarios that write (`view`, `vault-write`, `respond`, `signup`) grow the
database as they go, so a long ramp measures a bigger database at the top than
at the bottom — that is realistic, but it is a second variable. Hold one
scenario at one worker count for several minutes if you want to separate
capacity from growth.

`signup` and `signin` count a whole multi-request ceremony as one operation,
so their ops/s is ceremonies per second, not requests per second. `signin`
also registers one account per worker before its clock starts, so a 400-worker
stage spends a while in setup that no number reflects.

One instance is also the only supported shape today: the nonce registry, the
download-token registry and the rate limiters are in-process, so these numbers
say nothing about two instances behind a proxy.
