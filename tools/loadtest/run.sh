#!/usr/bin/env bash
#
# One command: bring up a starved copy of the API, seed it, ramp load until it
# breaks, print the report, tear it down.
#
#   ./tools/loadtest/run.sh                                  the default ramp, mixed traffic
#   CPUS=0.5 MEMORY=256m ./tools/loadtest/run.sh             a smaller box
#   SCENARIO=view STAGES=10,50,200 ./tools/loadtest/run.sh   one path, chosen steps
#   SCENARIO=all DURATION=10s ./tools/loadtest/run.sh        everything, briefly
#   KEEP=1 ./tools/loadtest/run.sh                           leave it running afterwards
#
# Settings (all optional):
#
#   CPUS=1.0        CPU quota for the server, in cores
#   MEMORY=512m     memory ceiling; no swap, so hitting it is an OOM kill
#   PORT=3100       host port (bound to 127.0.0.1)
#   SCENARIO=mixed  scenario, a comma-separated list, or 'all' — ./run.sh -list
#   STAGES=...      worker counts to walk
#   DURATION=20s    how long each stage is held
#   USERS=8         accounts to seed (each one is a passkey registration)
#   KEEP=1          keep the instance up after the run
#   REPORT=path     where to write the JSON report
#
# Any further arguments go to the generator unchanged, so flags not listed here
# still work: ./tools/loadtest/run.sh -max-p99 500ms

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPOSE_FILE="$ROOT/deploy/loadtest/docker-compose.yml"

CPUS="${CPUS:-1.0}"
MEMORY="${MEMORY:-512m}"
PORT="${PORT:-3100}"
SCENARIO="${SCENARIO:-mixed}"
STAGES="${STAGES:-2,5,10,25,50,100,200,400}"
DURATION="${DURATION:-20s}"
USERS="${USERS:-8}"
CONTAINER="${CONTAINER:-revoked-loadtest-api}"
REPORT="${REPORT:-}"

die() { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }
info() { printf '\033[36m==> %s\033[0m\n' "$*"; }

# -list needs no server, so it must not start one.
if [[ "${1:-}" == "-list" || "${1:-}" == "--list" ]]; then
  exec go run "$ROOT/tools/loadtest" -list
fi

command -v docker >/dev/null || die "docker not found."
command -v go >/dev/null || die "go not found. The toolchain may be at ~/sdk/go1.26.6/bin."

# Hand the ceiling to the collector a little early: at the cgroup limit the
# kernel kills the process, and a GC that already backed off tells you more
# than a corpse does.
if [[ -z "${GOMEMLIMIT_OVERRIDE:-}" ]]; then
  bytes="$(numfmt --from=iec "${MEMORY^^}" 2>/dev/null || echo 0)"
  if [[ "$bytes" -gt 0 ]]; then
    GOMEMLIMIT_OVERRIDE="$(( bytes * 85 / 100 ))B"
  fi
fi

export LOADTEST_CPUS="$CPUS"
export LOADTEST_MEMORY="$MEMORY"
export LOADTEST_PORT="$PORT"
export LOADTEST_CONTAINER="$CONTAINER"
export LOADTEST_GOMEMLIMIT="${GOMEMLIMIT_OVERRIDE:-}"

compose() { docker compose -f "$COMPOSE_FILE" "$@"; }

cleanup() {
  if [[ "${KEEP:-0}" == "1" ]]; then
    info "Instance left running on http://127.0.0.1:$PORT (stop it with: docker compose -f $COMPOSE_FILE down -v)"
    return
  fi
  info "Tearing down"
  compose down -v --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT

# A fresh volume every run: starting from the last run's rows is not repeating
# the last run.
info "Starting a $CPUS-core, $MEMORY instance on 127.0.0.1:$PORT"
compose down -v --remove-orphans >/dev/null 2>&1 || true
compose up -d --build

info "Driving it"
go run "$ROOT/tools/loadtest" \
  -url "http://127.0.0.1:$PORT" \
  -container "$CONTAINER" \
  -scenario "$SCENARIO" \
  -stages "$STAGES" \
  -duration "$DURATION" \
  -users "$USERS" \
  ${REPORT:+-out "$REPORT"} \
  "$@"
