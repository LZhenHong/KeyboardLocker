#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly REPO_ROOT
readonly PROJECT_PATH="$REPO_ROOT/KeyboardLocker.xcodeproj"
readonly SCHEME="KeyboardLocker"
readonly CONFIGURATION="Debug"
readonly EXPECTED_IDENTIFIER="io.lzhlovesjyq.keyboardlocker.klock"

usage() {
  cat <<'EOF'
Usage: ./scripts/install-klock-dev.sh [install|status|uninstall] [--bin-dir PATH]

Commands:
  install      Build the Debug App and link its bundled klock command (default).
  status       Report whether the expected command link is installed.
  uninstall    Remove only the command link owned by this Debug build.

Options:
  --bin-dir PATH  Command directory. Defaults to $KLOCK_BIN_DIR or ~/.local/bin.
  -h, --help      Show this help message.

This script never copies klock, edits shell profiles, or uses sudo.
EOF
}

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

action="install"
bin_dir="${KLOCK_BIN_DIR:-$HOME/.local/bin}"

if (($# > 0)) && [[ "$1" != -* ]]; then
  action="$1"
  shift
fi

while (($# > 0)); do
  case "$1" in
    --bin-dir)
      (($# >= 2)) || fail "--bin-dir requires a path."
      bin_dir="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

case "$action" in
  install|status|uninstall)
    ;;
  *)
    fail "Unknown command: $action"
    ;;
esac

if [[ "$bin_dir" != /* ]]; then
  bin_dir="$PWD/$bin_dir"
fi
readonly BIN_DIR="$bin_dir"
readonly DESTINATION="$BIN_DIR/klock"

resolve_source() {
  local build_settings
  local target_build_dir
  local full_product_name

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

  [[ -n "$target_build_dir" && -n "$full_product_name" ]] \
    || fail "Could not resolve the Debug App path from Xcode build settings."

  printf '%s/%s/Contents/MacOS/klock\n' "$target_build_dir" "$full_product_name"
}

SOURCE="$(resolve_source)"
readonly SOURCE
readonly APP_PATH="${SOURCE%/Contents/MacOS/klock}"
readonly AGENT_PATH="$APP_PATH/Contents/Library/LoginItems/KeyboardLockerAgent.app"

link_points_to_source() {
  [[ -L "$DESTINATION" ]] || return 1
  [[ "$(readlink "$DESTINATION")" == "$SOURCE" ]]
}

print_path_guidance() {
  case ":${PATH:-}:" in
    *":$BIN_DIR:"*)
      printf "Run \`hash -r\` or open a new Terminal, then use \`klock --help\`.\n"
      ;;
    *)
      printf 'The command directory is not currently in PATH. Add it in your shell configuration:\n'
      printf "  export PATH=\"%s:\$PATH\"\n" "$BIN_DIR"
      printf "Then open a new Terminal and run \`klock --help\`.\n"
      ;;
  esac
}

show_status() {
  if link_points_to_source; then
    printf 'Installed: %s -> %s\n' "$DESTINATION" "$SOURCE"
    return 0
  fi

  if [[ -L "$DESTINATION" ]]; then
    printf 'Conflict: %s points to %s\n' "$DESTINATION" "$(readlink "$DESTINATION")" >&2
    return 2
  fi

  if [[ -e "$DESTINATION" ]]; then
    printf 'Conflict: a non-symlink item exists at %s\n' "$DESTINATION" >&2
    return 2
  fi

  printf 'Not installed: %s\n' "$DESTINATION"
  return 1
}

case "$action" in
  status)
    show_status
    ;;

  uninstall)
    if link_points_to_source; then
      rm "$DESTINATION"
      printf 'Removed: %s\n' "$DESTINATION"
      exit 0
    fi

    if [[ -L "$DESTINATION" || -e "$DESTINATION" ]]; then
      fail "Refusing to remove an item not owned by this Debug build: $DESTINATION"
    fi

    printf 'Already not installed: %s\n' "$DESTINATION"
    ;;

  install)
    if ! link_points_to_source && [[ -L "$DESTINATION" || -e "$DESTINATION" ]]; then
      fail "Refusing to replace an existing item: $DESTINATION"
    fi

    printf 'Building KeyboardLocker (%s)...\n' "$CONFIGURATION"
    xcodebuild \
      -project "$PROJECT_PATH" \
      -scheme "$SCHEME" \
      -configuration "$CONFIGURATION" \
      -quiet \
      build

    [[ -x "$SOURCE" ]] || fail "The bundled klock executable is missing: $SOURCE"
    [[ -d "$AGENT_PATH" ]] || fail "The bundled KeyboardLocker Agent is missing: $AGENT_PATH"
    codesign --verify --strict "$SOURCE" \
      || fail "The bundled klock executable failed code-signature verification."

    signing_info="$(codesign -dvv "$SOURCE" 2>&1)"
    identifier="$(printf '%s\n' "$signing_info" | awk -F= '/^Identifier=/ { print $2; exit }')"
    team_identifier="$(printf '%s\n' "$signing_info" | awk -F= '/^TeamIdentifier=/ { print $2; exit }')"
    app_team_identifier="$(codesign -dvv "$APP_PATH" 2>&1 | awk -F= '/^TeamIdentifier=/ { print $2; exit }')"
    agent_team_identifier="$(codesign -dvv "$AGENT_PATH" 2>&1 | awk -F= '/^TeamIdentifier=/ { print $2; exit }')"
    [[ "$identifier" == "$EXPECTED_IDENTIFIER" ]] \
      || fail "Unexpected klock signing identifier: ${identifier:-missing}"
    [[ -n "$team_identifier" && "$team_identifier" != "not set" ]] \
      || fail "The bundled klock executable does not have a Team identifier."
    [[ "$team_identifier" == "$app_team_identifier" \
      && "$team_identifier" == "$agent_team_identifier" ]] \
      || fail "The App, Agent, and klock executable do not share one Team identifier."

    if link_points_to_source; then
      printf 'Already installed: %s -> %s\n' "$DESTINATION" "$SOURCE"
      print_path_guidance
      exit 0
    fi

    if [[ -L "$DESTINATION" || -e "$DESTINATION" ]]; then
      fail "Refusing to replace an existing item: $DESTINATION"
    fi

    mkdir -p "$BIN_DIR"
    [[ -d "$BIN_DIR" && -w "$BIN_DIR" ]] \
      || fail "The command directory is not writable: $BIN_DIR"
    ln -s "$SOURCE" "$DESTINATION"
    printf 'Installed: %s -> %s\n' "$DESTINATION" "$SOURCE"
    print_path_guidance
    ;;
esac
