#!/usr/bin/env bash
# Stop the OpenClaw gateway daemon and verify it's down.
set -euo pipefail

# Resolve main repo root (works from worktrees too).
REPO_ROOT="$(cd "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --git-common-dir)/.." && pwd)"
GATEWAY_LOG="${HOME}/.openclaw/logs/gateway.log"
SCRIPT_LOG="/tmp/openclaw-gateway-stop.log"
PORT=18789
MAX_WAIT=6

log()  { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*" | tee -a "$SCRIPT_LOG"; }
fail() { log "ERROR: $*"; exit 1; }

rm -f "$SCRIPT_LOG"
log "--- gateway-stop ---"

# Pre-check: is it even running?
if ! lsof -iTCP:${PORT} -sTCP:LISTEN >/dev/null 2>&1; then
  log "Gateway is not listening on :${PORT} — nothing to stop."

  # Also try daemon stop in case the service is registered but crashed
  (cd "$REPO_ROOT" && node openclaw.mjs daemon stop 2>&1) | tee -a "$SCRIPT_LOG" || true

  log "--- gateway already stopped ---"
  exit 0
fi

PID_BEFORE=$(lsof -iTCP:${PORT} -sTCP:LISTEN -t 2>/dev/null | head -1)
log "Gateway running on :${PORT} (pid ${PID_BEFORE})"

# Stop via daemon CLI
log "Stopping gateway daemon..."
(cd "$REPO_ROOT" && node openclaw.mjs daemon stop 2>&1) | tee -a "$SCRIPT_LOG"

# Wait for port to free up
log "Waiting for port ${PORT} to close..."
elapsed=0
while lsof -iTCP:${PORT} -sTCP:LISTEN >/dev/null 2>&1; do
  sleep 1
  elapsed=$((elapsed + 1))
  if [ "$elapsed" -ge "$MAX_WAIT" ]; then
    STALE_PID=$(lsof -iTCP:${PORT} -sTCP:LISTEN -t 2>/dev/null | head -1)
    log "WARNING: Port ${PORT} still held by pid ${STALE_PID} after ${MAX_WAIT}s"
    log "Sending SIGKILL to ${STALE_PID}..."
    kill -9 "$STALE_PID" 2>/dev/null || true
    sleep 1
    if lsof -iTCP:${PORT} -sTCP:LISTEN >/dev/null 2>&1; then
      fail "Could not free port ${PORT}. Manual intervention needed."
    fi
    break
  fi
done

# Verify process is gone
if kill -0 "$PID_BEFORE" 2>/dev/null; then
  log "WARNING: pid ${PID_BEFORE} still alive (may be a different process)"
else
  log "Process ${PID_BEFORE} terminated."
fi

# Verify port is free
if lsof -iTCP:${PORT} -sTCP:LISTEN >/dev/null 2>&1; then
  fail "Port ${PORT} still in use after stop!"
else
  log "Port ${PORT} is free."
fi

log "Last gateway log lines:"
tail -5 "$GATEWAY_LOG" 2>/dev/null | while IFS= read -r line; do log "  $line"; done || true

log "Script log: ${SCRIPT_LOG}"
log "--- gateway stopped ---"
