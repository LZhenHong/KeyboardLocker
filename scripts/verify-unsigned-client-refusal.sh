#!/bin/bash
# verify-unsigned-client-refusal.sh — runbook proof that the Agent refuses non-team clients.
#
# Purpose: end-to-end verification of the documented fail-closed guarantee: a process without
#   the KeyboardLocker Apple Team signature must not be able to call the live Agent's Mach
#   service (io.lzhlovesjyq.keyboardlocker.agent). The probe compiled here is ad-hoc signed
#   (swiftc output on arm64 is always linker-signed ad-hoc), which is exactly the class of
#   client the listener's code-signing requirement must reject.
#
# Precondition: the KeyboardLocker Agent must be running. A refusal without a live Agent would
#   be vacuous — a connection to a dead Mach service fails regardless of any code-signing
#   requirement, proving nothing. When the Agent is absent this script prints SKIP and exits 2.
#
# This is a manual/runbook verification, not wired into CI: it requires a locally installed,
#   team-signed Agent and a GUI user session. It does not modify the Agent or the system.
#
# Exit codes: 0 = PASS (client refused), 1 = FAIL (Agent answered), 2 = SKIP/INDETERMINATE.

set -euo pipefail

AGENT_PROCESS="KeyboardLockerAgent"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROBE_SOURCE="$REPO_ROOT/scripts/unsigned-client-probe/main.swift"
COMMON_SOURCES_DIR="$REPO_ROOT/Core/Sources/Common"

WORK_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

echo "==> Checking precondition: agent process '$AGENT_PROCESS' is running"
if ! pgrep -x "$AGENT_PROCESS" >/dev/null 2>&1; then
  echo "SKIP: $AGENT_PROCESS is not running."
  echo "      A refusal without a live Agent would be vacuous: connections to a dead Mach"
  echo "      service fail regardless of the code-signing requirement."
  echo "      Launch KeyboardLocker (which registers io.lzhlovesjyq.keyboardlocker.agent)"
  echo "      and re-run this script."
  exit 2
fi
echo "    agent is running (pid $(pgrep -x "$AGENT_PROCESS" | head -1))"

echo "==> Compiling the probe (ad-hoc signed, real protocol from Core/Sources/Common)"
xcrun swiftc \
  "$PROBE_SOURCE" \
  "$COMMON_SOURCES_DIR"/*.swift \
  -o "$WORK_DIR/unsigned-client-probe"

echo "==> Confirming the probe is not team-signed"
if codesign -dv "$WORK_DIR/unsigned-client-probe" 2>&1 | grep -q "^TeamIdentifier=not set"; then
  codesign -dv "$WORK_DIR/unsigned-client-probe" 2>&1 \
    | grep -E "^(Signature|TeamIdentifier)" | sed 's/^/    /'
else
  echo "FAIL: probe unexpectedly carries a Team ID; it would not exercise the refusal path."
  exit 2
fi

echo "==> Running the probe against the live Agent"
set +e
PROBE_OUTPUT="$("$WORK_DIR/unsigned-client-probe" 2>&1)"
PROBE_EXIT=$?
set -e
echo "$PROBE_OUTPUT" | sed 's/^/    /'

case "$PROBE_EXIT" in
  0)
    echo "PASS: the Agent refused an ad-hoc (non-team) client."
    ;;
  1)
    echo "FAIL: the Agent replied to an ad-hoc (non-team) client — fail-closed is broken."
    exit 1
    ;;
  *)
    echo "INDETERMINATE: probe could not distinguish refusal from reply (exit $PROBE_EXIT)."
    exit 2
    ;;
esac
