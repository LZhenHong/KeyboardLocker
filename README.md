# Keyboard Locker

A modern macOS menu bar application for quickly locking and unlocking your keyboard to prevent accidental input.

## Features

- 🔒 **Quick Lock/Unlock** – One-click keyboard control via the menu bar
- ⌨️ **Global Hotkey** – `⌘ + ⌥ + L` shortcut (works even when locked)
- 🔓 **Status Indicator** – Menu bar icon switches between `lock.open` and `lock`
- 🔔 **Notifications** – Optional lock/unlock alerts
- 🕒 **Auto-Lock** – Configurable idle timer powered by `UserActivityMonitor`
- 🌐 **Multi-language** – English and Simplified Chinese
- 🖥️ **Command-Line Tool** – Scriptable lock/unlock control
- 🔗 **URL Schemes** – External control via `keyboardlocker://` URLs
- 🍎 **AppleScript Support** – Automation via macOS scripting
- 🛡️ **Privacy First** – Local operation, no data collection

## Installation

### Quick Start
1. Download and run `KeyboardLocker.app`
2. Grant Accessibility permission when prompted
3. Look for the lock icon  in your menu bar to start

### Build from Source
```bash
git clone https://github.com/LZhenHong/KeyboardLocker
cd KeyboardLocker
make build
```

## Usage

- **Lock/Unlock**: Click the menu bar icon and toggle the button
- **Quick Toggle**: Press `⌘ + ⌥ + L` anytime
- **Settings**: Configure notifications, auto-lock, and hotkey
- **Status**: Icon shows 🔒 when locked, 🔓 when unlocked; status window mirrors details

## Command-Line Interface

The repository ships with a Swift-based CLI (`KeyboardLockerTool`) that mirrors the app’s lock/unlock/toggle behaviour for automation scenarios.

```bash
# Build the CLI once (Release configuration)
make cli

# Binary ends up here
./Build/CLI/KeyboardLockerTool --help
```

Available commands:

- `lock` – immediately lock the keyboard and wait until it is unlocked (either via hotkey or Ctrl+C)
- `unlock` – force an unlock and exit
- `toggle` – switch between lock/unlock depending on the current state
- `--help` – print usage text

The CLI uses the same Accessibility permission as the app. If you run it outside the packaged app bundle, macOS may prompt for access the first time.

## AppleScript Integration

KeyboardLocker supports AppleScript commands for automation and integration with other macOS tools.

```applescript
# Lock the keyboard
tell application "KeyboardLocker"
    lock
end tell

# Unlock the keyboard
tell application "KeyboardLocker"
    unlock
end tell

# Toggle lock state
tell application "KeyboardLocker"
    toggle
end tell
```

You can also run AppleScript commands from the terminal:

```bash
osascript -e 'tell application "KeyboardLocker" to lock'
osascript -e 'tell application "KeyboardLocker" to unlock'
osascript -e 'tell application "KeyboardLocker" to toggle'
```

The first time you use AppleScript with KeyboardLocker, macOS will request **Automation permission** for the controlling application.

## Requirements

- macOS 13.0 or later
- Accessibility permission (requested on first launch)
- Automation permission if you enable Apple Events integrations

## Documentation

- [docs/BUILD.md](docs/BUILD.md) - Build instructions and setup
- [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) - Developer guide and contribution  
- [docs/CHANGELOG.md](docs/CHANGELOG.md) - Version history and updates
- [docs/URL_SCHEMES_GUIDE.md](docs/URL_SCHEMES_GUIDE.md) - URL schemes for automation and integration

## License

Copyright © 2025 Eden. All rights reserved.
