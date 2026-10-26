#!/usr/bin/env bash
#
# Local development runtime: the Go backend and the Flutter app, each in its
# own Terminal window, without Docker.
#
#   ./dev.sh          opens two Terminal windows (backend + app); inside VS Code
#                     use Cmd+Shift+B instead (task "dev" in .vscode/tasks.json),
#                     which runs both in split terminals in the editor
#   ./dev.sh api      runs only the backend in the current terminal
#   ./dev.sh app      runs only the Flutter app in the current terminal
#
# Settings (environment variables, all optional):
#
#   API_PORT=3000     port the backend listens on
#   API_HOST=0.0.0.0  interface the backend binds to (0.0.0.0 so phones on the
#                     LAN can reach it; 127.0.0.1 keeps it local)
#   DEVICE=macos      Flutter device id, see `flutter devices`
#   API_BASE_URL=     URL the app talks to; derived from DEVICE when empty:
#                       macos            -> http://127.0.0.1:$API_PORT
#                       emulator-*       -> adb reverse + http://127.0.0.1:$API_PORT
#                       anything else    -> http://<LAN IP of this Mac>:$API_PORT
#
# Example: DEVICE=00008150-00020D603404401C ./dev.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
API_PORT="${API_PORT:-3000}"
API_HOST="${API_HOST:-0.0.0.0}"
DEVICE="${DEVICE:-macos}"
API_BASE_URL="${API_BASE_URL:-}"

die() { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }
info() { printf '\033[36m==> %s\033[0m\n' "$*"; }

need() { command -v "$1" >/dev/null 2>&1 || die "'$1' not found in PATH."; }

lan_ip() {
  local ip
  for iface in en0 en1; do
    ip="$(ipconfig getifaddr "$iface" 2>/dev/null || true)"
    [[ -n "$ip" ]] && { echo "$ip"; return; }
  done
  die "No LAN IP found. Set API_BASE_URL explicitly."
}

run_api() {
  need go
  cd "$ROOT"
  [[ -f .env ]] || die ".env is missing. Create it with: cp .env.example .env (DOMAIN is required)."
  if lsof -nP -iTCP:"$API_PORT" -sTCP:LISTEN >/dev/null 2>&1; then
    die "Port $API_PORT is already in use:
$(lsof -nP -iTCP:"$API_PORT" -sTCP:LISTEN)"
  fi
  info "Backend on http://$API_HOST:$API_PORT (dashboard: http://127.0.0.1:$API_PORT/_/)"
  exec go run ./cmd/revoked serve --http="$API_HOST:$API_PORT"
}

run_app() {
  need flutter
  need curl
  cd "$ROOT/app"

  if [[ -z "$API_BASE_URL" ]]; then
    case "$DEVICE" in
      macos) API_BASE_URL="http://127.0.0.1:$API_PORT" ;;
      emulator-*)
        need adb
        adb -s "$DEVICE" reverse "tcp:$API_PORT" "tcp:$API_PORT" >/dev/null
        API_BASE_URL="http://127.0.0.1:$API_PORT"
        ;;
      *) API_BASE_URL="http://$(lan_ip):$API_PORT" ;;
    esac
  fi

  # The first `go run` compiles the whole server, so give it time.
  info "Waiting for the backend on 127.0.0.1:$API_PORT ..."
  local waited=0
  until curl -fsS "http://127.0.0.1:$API_PORT/healthz" >/dev/null 2>&1; do
    (( waited >= 180 )) && die "Backend did not come up within 180 s."
    sleep 1
    (( waited += 1 ))
  done
  info "Backend is up."

  flutter pub get
  info "App on device '$DEVICE' -> $API_BASE_URL"
  exec flutter run -d "$DEVICE" --dart-define=API_BASE_URL="$API_BASE_URL"
}

open_terminals() {
  if [[ "${TERM_PROGRAM:-}" == "vscode" ]]; then
    info "In VS Code: press Cmd+Shift+B (or run the task \"dev\") to start backend and app"
    info "in split terminals here. './dev.sh api' / './dev.sh app' run one side in this terminal."
    exit 0
  fi
  [[ "$(uname)" == "Darwin" ]] || die "Opening windows needs macOS Terminal; run './dev.sh api' and './dev.sh app' yourself."
  need osascript

  local env_prefix cmd_api cmd_app
  env_prefix="API_PORT=$API_PORT API_HOST=$API_HOST DEVICE=$DEVICE"
  [[ -n "$API_BASE_URL" ]] && env_prefix+=" API_BASE_URL=$API_BASE_URL"
  cmd_api="cd '$ROOT' && $env_prefix ./dev.sh api"
  cmd_app="cd '$ROOT' && $env_prefix ./dev.sh app"

  osascript - "$cmd_api" "$cmd_app" <<'APPLESCRIPT' >/dev/null
on run argv
  tell application "Terminal"
    activate
    set apiTab to do script (item 1 of argv)
    set custom title of apiTab to "revoked: backend"
    set appTab to do script (item 2 of argv)
    set custom title of appTab to "revoked: app"
  end tell
end run
APPLESCRIPT

  info "Opened two Terminal windows: backend (port $API_PORT) and app (device $DEVICE)."
  info "Stop with Ctrl+C in the backend window and 'q' in the app window."
}

case "${1:-}" in
  api | backend) run_api ;;
  app | frontend) run_app ;;
  "") open_terminals ;;
  -h | --help) sed -n '3,25p' "$0" | sed 's/^# \{0,1\}//' ;;
  *) die "Unknown command '$1'. Use: ./dev.sh [api|app]" ;;
esac
