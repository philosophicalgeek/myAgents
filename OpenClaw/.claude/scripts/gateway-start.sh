#!/usr/bin/env bash
# Start the OpenClaw gateway daemon and verify it's healthy.
set -euo pipefail

# Resolve main repo root (works from worktrees too).
REPO_ROOT="$(cd "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --git-common-dir)/.." && pwd)"
GATEWAY_LOG="${HOME}/.openclaw/logs/gateway.log"
SCRIPT_LOG="/tmp/openclaw-gateway-start.log"
PORT=18789
MAX_WAIT=8

log()  { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*" | tee -a "$SCRIPT_LOG"; }
fail() { log "ERROR: $*"; exit 1; }

rm -f "$SCRIPT_LOG"
log "--- gateway-start ---"

# Pre-flight: already running?
if lsof -iTCP:${PORT} -sTCP:LISTEN >/dev/null 2>&1; then
  PID=$(lsof -iTCP:${PORT} -sTCP:LISTEN -t 2>/dev/null | head -1)
  log "Gateway already listening on :${PORT} (pid ${PID})"
  log "Use gateway-stop.sh first or restart.sh to cycle."
  # Still open the log tail for convenience
  osascript -e "tell application \"Terminal\" to do script \"tail -f '${GATEWAY_LOG}'\"" >/dev/null 2>&1 || true
  exit 0
fi

# Ensure daemon is installed
log "Installing daemon (idempotent)..."
(cd "$REPO_ROOT" && node openclaw.mjs daemon install --force --runtime node 2>&1) | tee -a "$SCRIPT_LOG"

# Start
log "Starting gateway daemon..."
(cd "$REPO_ROOT" && node openclaw.mjs daemon start 2>&1) | tee -a "$SCRIPT_LOG"

# Wait for port
log "Waiting for port ${PORT}..."
elapsed=0
while ! lsof -iTCP:${PORT} -sTCP:LISTEN >/dev/null 2>&1; do
  sleep 1
  elapsed=$((elapsed + 1))
  if [ "$elapsed" -ge "$MAX_WAIT" ]; then
    fail "Gateway did not start within ${MAX_WAIT}s. Check: tail -f ${GATEWAY_LOG}"
  fi
done

# Post-start checks
PID=$(lsof -iTCP:${PORT} -sTCP:LISTEN -t 2>/dev/null | head -1)
log "Gateway listening on :${PORT} (pid ${PID})"

# Daemon status
log "--- daemon status ---"
(cd "$REPO_ROOT" && node openclaw.mjs daemon status 2>&1) | tee -a "$SCRIPT_LOG"

# RPC probe via curl (quick WebSocket upgrade check)
HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${PORT}/" 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "000" ]; then
  log "WARNING: HTTP probe failed (connection refused)"
else
  log "HTTP probe: ${HTTP_CODE} (200 = dashboard OK)"
fi

log "Logs: ${GATEWAY_LOG}"
log "Script log: ${SCRIPT_LOG}"
log "--- gateway started ---"

# Open a new Terminal window tailing gateway logs
osascript -e "tell application \"Terminal\" to do script \"echo '=== OpenClaw Gateway Logs ===' && tail -f '${GATEWAY_LOG}'\"" >/dev/null 2>&1 || {
  log "Could not open Terminal for log tail. Run manually: tail -f ${GATEWAY_LOG}"
}
