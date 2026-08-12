#!/bin/bash
# verify-unsigned-client-refusal.sh — prove that the live Agent refuses non-team clients.
#
# The refusal probe is meaningful only when a known authorized client can call the same Agent
# generation immediately before and after it. This script compiles a temporary control, signs it
# with the local bundled klock identity, and reads ServiceDescriptor.agentInstanceID on both sides
# of the ad-hoc probe. An unavailable or replaced Agent is INDETERMINATE, never PASS.
#
# Precondition: a locally team-signed Debug App has been built and its Agent is running. Override
# the bundled klock discovery with KEYBOARDLOCKER_AUTHORIZED_CLIENT=/absolute/path/to/klock. If
# the bundled certificate's exact SHA-1 identity is unavailable to the local keychain, set
# KEYBOARDLOCKER_SIGNING_IDENTITY to a usable identity name or SHA-1 hash for the same Team ID.
#
# This is a manual/runbook verification, not wired into CI. It creates only temporary binaries.
#
# Exit codes: 0 = PASS (client refused), 1 = FAIL (Agent answered), 2 = INDETERMINATE.

set -euo pipefail

readonly AGENT_PROCESS="KeyboardLockerAgent"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly REPO_ROOT
readonly PROJECT_PATH="$REPO_ROOT/KeyboardLocker.xcodeproj"
readonly COMMON_SOURCES_DIR="$REPO_ROOT/Core/Sources/Common"
readonly CONTROL_SOURCE="$REPO_ROOT/scripts/signed-client-control/main.swift"
readonly PROBE_SOURCE="$REPO_ROOT/scripts/unsigned-client-probe/main.swift"
readonly EXPECTED_CLIENT_IDENTIFIER="io.lzhlovesjyq.keyboardlocker.klock"

WORK_DIR="$(mktemp -d)"
readonly WORK_DIR
cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

indeterminate() {
  printf 'INDETERMINATE: %s\n' "$*" >&2
  exit 2
}

signing_field() {
  local binary="$1"
  local field="$2"
  codesign -dvvv "$binary" 2>&1 \
    | awk -F= -v field="$field" '$1 == field && !found { print $2; found = 1 }'
}

resolve_bundled_klock() {
  local build_settings
  local target_build_dir
  local full_product_name

  build_settings="$(
    xcodebuild \
      -project "$PROJECT_PATH" \
      -scheme KeyboardLocker \
      -configuration Debug \
      -showBuildSettings 2>/dev/null
  )"
  target_build_dir="$(
    printf '%s\n' "$build_settings" \
      | awk -F ' = ' \
        '/^[[:space:]]*TARGET_BUILD_DIR = / && !found { print $2; found = 1 }'
  )"
  full_product_name="$(
    printf '%s\n' "$build_settings" \
      | awk -F ' = ' \
        '/^[[:space:]]*FULL_PRODUCT_NAME = / && !found { print $2; found = 1 }'
  )"
  [[ -n "$target_build_dir" && -n "$full_product_name" ]] || return 1
  printf '%s/%s/Contents/MacOS/klock\n' "$target_build_dir" "$full_product_name"
}

run_control() {
  local output
  local control_exit

  set +e
  output="$("$WORK_DIR/signed-client-control" 2>&1)"
  control_exit=$?
  set -e
  printf '%s\n' "$output" | sed 's/^/    /' >&2
  [[ "$control_exit" -eq 0 ]] || return 1
  printf '%s\n' "$output" | awk '/^RESULT:LIVE / && !found { print $2; found = 1 }'
}

printf "==> Checking precondition: agent process '%s' is running\n" "$AGENT_PROCESS"
agent_pid="$(pgrep -x "$AGENT_PROCESS" | head -1 || true)"
[[ -n "$agent_pid" ]] || indeterminate \
  "$AGENT_PROCESS is not running; an unavailable service cannot prove refusal."
printf '    agent process exists (pid %s); the signed control will prove XPC liveness\n' "$agent_pid"

authorized_client="${KEYBOARDLOCKER_AUTHORIZED_CLIENT:-}"
if [[ -z "$authorized_client" ]]; then
  authorized_client="$(resolve_bundled_klock)" || indeterminate \
    "Could not resolve the Debug App's bundled klock executable."
fi
[[ "$authorized_client" == /* ]] || indeterminate \
  "KEYBOARDLOCKER_AUTHORIZED_CLIENT must be an absolute path."
[[ -x "$authorized_client" ]] || indeterminate \
  "The authorized client is not executable: $authorized_client"
codesign --verify --strict "$authorized_client" >/dev/null 2>&1 || indeterminate \
  "The authorized client has no valid code signature: $authorized_client"

client_identifier="$(signing_field "$authorized_client" Identifier)" || indeterminate \
  "Could not inspect the authorized client's signing identifier."
client_team="$(signing_field "$authorized_client" TeamIdentifier)" || indeterminate \
  "Could not inspect the authorized client's Team identifier."
[[ "$client_identifier" == "$EXPECTED_CLIENT_IDENTIFIER" ]] || indeterminate \
  "Expected signing identifier $EXPECTED_CLIENT_IDENTIFIER, found ${client_identifier:-missing}."
[[ -n "$client_team" && "$client_team" != "not set" ]] || indeterminate \
  "The authorized client does not carry a Team identifier."

signing_identity="${KEYBOARDLOCKER_SIGNING_IDENTITY:-}"
if [[ -z "$signing_identity" ]]; then
  certificate_prefix="$WORK_DIR/authorized-client-certificate"
  certificate_error=""
  if ! certificate_error="$(
    codesign -d --extract-certificates="$certificate_prefix" "$authorized_client" 2>&1
  )"; then
    indeterminate \
      "Could not extract the authorized client's signing certificate: ${certificate_error:-unknown error}"
  fi
  [[ -f "${certificate_prefix}0" ]] || indeterminate \
    "The authorized client did not expose a leaf signing certificate."
  if ! signing_identity="$(
    openssl x509 \
      -inform DER \
      -in "${certificate_prefix}0" \
      -noout \
      -fingerprint \
      -sha1 2>/dev/null \
      | awk -F= 'NF == 2 { gsub(":", "", $2); print $2 }'
  )"; then
    indeterminate "Could not inspect the authorized client's leaf certificate."
  fi
fi
[[ "$signing_identity" =~ ^[0-9A-Fa-f]{40}$ || -n "${KEYBOARDLOCKER_SIGNING_IDENTITY:-}" ]] \
  || indeterminate \
  "Could not determine the authorized client's exact signing identity."

printf '==> Compiling and team-signing the authorized liveness control\n'
xcrun swiftc \
  "$CONTROL_SOURCE" \
  "$COMMON_SOURCES_DIR"/*.swift \
  -o "$WORK_DIR/signed-client-control" || indeterminate \
  "Could not compile the authorized liveness control."
codesign \
  --force \
  --identifier "$EXPECTED_CLIENT_IDENTIFIER" \
  --sign "$signing_identity" \
  --timestamp=none \
  "$WORK_DIR/signed-client-control" >/dev/null 2>&1 || indeterminate \
  "Could not sign the liveness control with '$signing_identity'."
codesign --verify --strict "$WORK_DIR/signed-client-control" >/dev/null 2>&1 || indeterminate \
  "The signed liveness control failed signature verification."
control_identifier="$(signing_field "$WORK_DIR/signed-client-control" Identifier)" \
  || indeterminate "Could not inspect the liveness control's signing identifier."
control_team="$(signing_field "$WORK_DIR/signed-client-control" TeamIdentifier)" \
  || indeterminate "Could not inspect the liveness control's Team identifier."
[[ "$control_identifier" == "$EXPECTED_CLIENT_IDENTIFIER" && "$control_team" == "$client_team" ]] \
  || indeterminate "The liveness control does not match the authorized client's identity."
printf '    control identity: %s / Team %s\n' "$control_identifier" "$control_team"

printf '==> Positive control before refusal probe\n'
before_instance="$(run_control)" || indeterminate \
  "An authorized client could not prove that the Agent was live before the refusal probe."
[[ "$before_instance" =~ ^[0-9A-Fa-f-]{36}$ ]] || indeterminate \
  "The first positive control did not return a valid Agent instance ID."

printf '==> Compiling the ad-hoc refusal probe\n'
xcrun swiftc \
  "$PROBE_SOURCE" \
  "$COMMON_SOURCES_DIR"/*.swift \
  -o "$WORK_DIR/unsigned-client-probe" || indeterminate \
  "Could not compile the ad-hoc refusal probe."
probe_team="$(signing_field "$WORK_DIR/unsigned-client-probe" TeamIdentifier)" \
  || indeterminate "Could not inspect the refusal probe's Team identifier."
[[ "$probe_team" == "not set" ]] || indeterminate \
  "The refusal probe unexpectedly carries Team identifier ${probe_team:-missing}."

printf '==> Running the ad-hoc probe against Agent instance %s\n' "$before_instance"
set +e
probe_output="$("$WORK_DIR/unsigned-client-probe" 2>&1)"
probe_exit=$?
set -e
printf '%s\n' "$probe_output" | sed 's/^/    /'

printf '==> Positive control after refusal probe\n'
after_instance="$(run_control)" || indeterminate \
  "An authorized client could not prove that the Agent remained live after the refusal probe."
[[ "$after_instance" == "$before_instance" ]] || indeterminate \
  "The Agent changed during the probe ($before_instance -> ${after_instance:-unknown})."

case "$probe_exit" in
  0)
    printf 'PASS: Agent instance %s refused an ad-hoc non-team client; matching authorized controls succeeded immediately before and after.\n' \
      "$before_instance"
    ;;
  1)
    printf 'FAIL: Agent instance %s replied to an ad-hoc non-team client.\n' "$before_instance" >&2
    exit 1
    ;;
  *)
    indeterminate "The refusal probe produced no decisive result (exit $probe_exit)."
    ;;
esac
