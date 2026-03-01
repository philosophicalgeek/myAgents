#!/usr/bin/env bash
# Restart the OpenClaw gateway: stop, start, verify, tail logs.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Resolve main repo root (works from worktrees too).
REPO_ROOT="$(cd "$(git -C "${SCRIPT_DIR}" rev-parse --git-common-dir)/.." && pwd)"
GATEWAY_LOG="${HOME}/.openclaw/logs/gateway.log"
SCRIPT_LOG="/tmp/openclaw-gateway-restart.log"
PORT=18789

log()  { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*" | tee -a "$SCRIPT_LOG"; }

rm -f "$SCRIPT_LOG"
log "--- gateway restart ---"

# Snapshot pre-restart state
log "==> Pre-restart state"
if lsof -iTCP:${PORT} -sTCP:LISTEN >/dev/null 2>&1; then
  PID_BEFORE=$(lsof -iTCP:${PORT} -sTCP:LISTEN -t 2>/dev/null | head -1)
  log "Gateway running on :${PORT} (pid ${PID_BEFORE})"
else
  log "Gateway not running."
fi

# Stop phase
log "==> Stopping..."
"${SCRIPT_DIR}/gateway-stop.sh" 2>&1 | tee -a "$SCRIPT_LOG"
STOP_RC=${PIPESTATUS[0]}
if [ "$STOP_RC" -ne 0 ]; then
  log "WARNING: Stop exited with code ${STOP_RC}, continuing start anyway..."
fi

# Brief pause between stop and start
sleep 1

# Start phase
log "==> Starting..."
"${SCRIPT_DIR}/gateway-start.sh" 2>&1 | tee -a "$SCRIPT_LOG"
START_RC=${PIPESTATUS[0]}
if [ "$START_RC" -ne 0 ]; then
  log "ERROR: Start failed (exit ${START_RC}). Check: tail -f ${GATEWAY_LOG}"
  exit 1
fi

# Final verification
log "==> Post-restart verification"
if lsof -iTCP:${PORT} -sTCP:LISTEN >/dev/null 2>&1; then
  PID_AFTER=$(lsof -iTCP:${PORT} -sTCP:LISTEN -t 2>/dev/null | head -1)
  log "Gateway healthy on :${PORT} (pid ${PID_AFTER})"
else
  log "ERROR: Gateway not listening after restart!"
  exit 1
fi

# Dashboard check
HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${PORT}/" 2>/dev/null || echo "000")
log "Dashboard probe: HTTP ${HTTP_CODE}"

log "Script log: ${SCRIPT_LOG}"
log "--- gateway restart complete ---"
