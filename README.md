# Keyboard Locker

A modern macOS menu bar application for quickly locking and unlocking your keyboard to prevent accidental input.

## Features

- 🔒 **Quick Lock/Unlock** – One-click keyboard control via the menu bar
- ⌨️ **Global Hotkey** – `⌘ + ⌥ + L` shortcut (works even when locked)
- 🔓 **Status Indicator** – Menu bar icon switches between `lock.open` and `lock`
- 🔔 **Notifications** – Optional lock/unlock alerts
- 🕒 **Auto-Lock** – Configurable idle timer powered by `UserActivityMonitor`
- 🌐 **Multi-language** – English and Simplified Chinese
- 🔗 **URL Schemes** – External control via `keyboardlocker://` URLs
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
