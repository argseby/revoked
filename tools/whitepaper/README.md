# White paper experiments

The focused tests exercise the built-in remote cache with a controlled HTTP origin and a real public link with 32 concurrent readers. Existing integration tests supply real grant-update, revocation, and token-binding coverage.

Run from the repository root on a disposable development checkout:

```bash
go test ./tests -run 'TestWhitepaper|TestRemoteAnswerLivesOnTheRespondersServer|TestGrantReadsAreTokenBound|TestMaxViewsIsEnforcedExactlyOnce' -count=1 -p 1 -timeout 3m -v
```

The harness requires loopback sockets, uses port 5559, resets `tests/pb_test_data`, creates synthetic users and records, and disables rate limiters. Do not run another test process sharing that directory or port. No production server or credentials are used.

`TestWhitepaperCacheLifecycle` seeds the production cache through `RememberRemoteGrant` and resolves through `ResolveRemoteGrants`. A mock origin changes values, reports revocation, or returns HTTP 503. Backdating the entry by 61 seconds exercises expiry without a real-time wait. Explicit invalidation isolates cache behavior from asynchronous events. The mock does not validate credentials; the separate real integration test covers token binding.

`TestWhitepaperConcurrentViewCap` creates a real record and one-view public link, releases 32 HTTP callers through a shared start barrier, and requires exactly one success with no transport or 5xx errors. Timings include response-body consumption. Sorted observations use nearest-rank p50 and p95. They include rejected reads and are not successful-read performance estimates.

The result file contains test outcomes and measurements only; verbose HTTP output is omitted. Environment and limitations are documented in WHITEPAPER.md §9.1. Repeat runs are needed before drawing performance conclusions. The initial cache and view-limit experiments do not force the authorization/revocation race, measure event latency, or validate the cryptographic design. The separate experiment below addresses one service-level interleaving.

## Controlled in-flight resolution

```bash
go test ./tests -run '^TestWhitepaperInFlightRevocation$' -count=3 -p 1 -timeout 3m -v
```

The fixture creates a real request-born grant. A test-only wrapper embeds `core.App` and pauses `FindRecordById` for the granted record, after production `ResolveGrant` checks lifecycle state. While paused, the test revokes through HTTP and independently reloads persisted state. Releasing the channel allows the original read to finish; a fresh service read provides the comparison. Waits have ten-second timeouts, and cleanup releases the barrier on failure.

The observed old-state read is a characterization of current behavior, not a requirement that future implementations preserve it. No production code is altered. This does not pause a complete HTTP read handler or prove a race in every endpoint. The three repetitions share one test process and test server. Results are in `results/2026-11-12-inflight.txt`; their baseline differs from the initial experiment and is recorded in WHITEPAPER.md §9.2.
