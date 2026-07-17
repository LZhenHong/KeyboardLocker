#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly REPO_ROOT
readonly PROJECT_PATH="$REPO_ROOT/KeyboardLocker.xcodeproj"
readonly SCHEME="KeyboardLocker"
readonly CONFIGURATION="Debug"

echo "Building KeyboardLocker ($CONFIGURATION)..."
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -quiet \
  build

build_settings="$(
  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -showBuildSettings 2>/dev/null
)"
target_build_dir="$(
  printf '%s\n' "$build_settings" \
    | awk -F ' = ' '/^[[:space:]]*TARGET_BUILD_DIR = / { print $2; exit }'
)"
full_product_name="$(
  printf '%s\n' "$build_settings" \
    | awk -F ' = ' '/^[[:space:]]*FULL_PRODUCT_NAME = / { print $2; exit }'
)"

if [[ -z "$target_build_dir" || -z "$full_product_name" ]]; then
  echo "Error: Could not resolve the Debug app path from Xcode build settings." >&2
  exit 1
fi

readonly APP_PATH="$target_build_dir/$full_product_name"
readonly APP_INFO_PLIST="$APP_PATH/Contents/Info.plist"
readonly AGENT_PLIST="$APP_PATH/Contents/Library/LaunchAgents/io.lzhlovesjyq.keyboardlocker.agent.plist"

if [[ ! -x "$APP_PATH/Contents/MacOS/KeyboardLocker" || ! -f "$AGENT_PLIST" ]]; then
  echo "Error: The built KeyboardLocker app is incomplete: $APP_PATH" >&2
  exit 1
fi

APP_BUNDLE_IDENTIFIER="$(
  /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_INFO_PLIST"
)"
readonly APP_BUNDLE_IDENTIFIER
APP_EXECUTABLE="$(
  /usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP_INFO_PLIST"
)"
readonly APP_EXECUTABLE
AGENT_LABEL="$(
  /usr/libexec/PlistBuddy -c 'Print :Label' "$AGENT_PLIST"
)"
readonly AGENT_LABEL
AGENT_PROGRAM="$(
  /usr/libexec/PlistBuddy -c 'Print :BundleProgram' "$AGENT_PLIST"
)"
readonly AGENT_PROGRAM
AGENT_EXECUTABLE="$(basename "$AGENT_PROGRAM")"
readonly AGENT_EXECUTABLE

if pgrep -x "$APP_EXECUTABLE" >/dev/null; then
  echo "Quitting KeyboardLocker..."
  osascript -e "tell application id \"$APP_BUNDLE_IDENTIFIER\" to quit" >/dev/null

  for ((attempt = 0; attempt < 50; attempt += 1)); do
    if ! pgrep -x "$APP_EXECUTABLE" >/dev/null; then
      break
    fi
    sleep 0.1
  done

  if pgrep -x "$APP_EXECUTABLE" >/dev/null; then
    echo "Error: KeyboardLocker did not quit; registration was not changed." >&2
    exit 1
  fi
fi

echo "Resetting KeyboardLocker agent registration..."
PROFILE_OUTPUT="$(mktemp "${TMPDIR:-/tmp}/keyboardlocker-reset.profraw.XXXXXX")"
readonly PROFILE_OUTPUT
trap 'rm -f "$PROFILE_OUTPUT"' EXIT

LLVM_PROFILE_FILE="$PROFILE_OUTPUT" \
  "$APP_PATH/Contents/MacOS/$APP_EXECUTABLE" --reset-agent-registration
rm -f "$PROFILE_OUTPUT"
trap - EXIT

SERVICE_TARGET="gui/$(id -u)/$AGENT_LABEL"
readonly SERVICE_TARGET
for ((attempt = 0; attempt < 50; attempt += 1)); do
  if ! launchctl print "$SERVICE_TARGET" >/dev/null 2>&1 \
    && ! pgrep -x "$AGENT_EXECUTABLE" >/dev/null; then
    echo "KeyboardLocker is reset to an unregistered, stopped state."
    exit 0
  fi
  sleep 0.1
done

echo "Error: The KeyboardLocker agent is still registered or running." >&2
exit 1
