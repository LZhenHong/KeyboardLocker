# Keyboard Locker

A modern macOS menu bar application for quickly locking and unlocking your keyboard to prevent accidental input.

## Features

- � **Quick Lock/Unlock** - One-click keyboard control
- ⌨️ **Global Hotkey** - `⌘ + ⌥ + L` shortcut (works when locked)
- 📱 **Menu Bar App** - Lightweight, no Dock space
- 🔔 **Notifications** - Optional lock status alerts
- 🌐 **Multi-language** - English and Simplified Chinese
- 🛡️ **Privacy First** - Local operation, no data collection

## Installation

### Quick Start
1. Download and run `KeyboardLocker.app`
2. Grant Accessibility permission when prompted
3. Click the shield icon 🛡️ in your menu bar to start

### Build from Source
```bash
git clone https://github.com/LZhenHong/KeyboardLocker
cd KeyboardLocker
make build
```

## Usage

- **Lock/Unlock**: Click menu bar icon and toggle the button
- **Quick Toggle**: Press `⌘ + ⌥ + L` anytime
- **Settings**: Configure notifications and auto-lock
- **Status**: Green = unlocked, Red = locked

## Requirements

- macOS 13.0 or later
- Accessibility permission (requested on first launch)

## Documentation

- [BUILD.md](BUILD.md) - Build instructions
- [DEVELOPMENT.md](DEVELOPMENT.md) - Developer guide  
- [CHANGELOG.md](CHANGELOG.md) - Version history

## License

Copyright © 2025 Eden. All rights reserved.
