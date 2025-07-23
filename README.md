# Keyboard Locker

An elegant macOS menu bar application built with modern SwiftUI MenuBarExtra API for quickly locking and unlocking the keyboard to prevent accidental input.

## 📚 Table of Contents

- [🤖 AI Implementation Overview](#-ai-implementation-overview)
- [✨ Features](#features)
- [🛠 Technology Stack](#technology-stack)
- [📁 Project Structure](#project-structure)
- [💻 System Requirements](#system-requirements)
- [🚀 Installation and Usage](#installation-and-usage)
- [🔑 Permissions](#permissions)
- [⚙️ Main Features](#main-features)
- [🔧 Development Notes](#development-notes)
- [📖 Related Documentation](#related-documentation)
  - [BUILD.md](BUILD.md) - Build instructions and deployment guide
  - [DEVELOPMENT.md](DEVELOPMENT.md) - Developer guide and technical documentation
  - [CHANGELOG.md](CHANGELOG.md) - Version history and update records
  - [XCSTRINGS_GUIDE.md](XCSTRINGS_GUIDE.md) - Localization configuration guide
- [📜 Copyright & License](#copyright)

---

## 🤖 AI Implementation Overview

This project is a modern macOS application developed with **GitHub Copilot** assistance in VS Code environment.

### AI Collaboration Features
- **Fully AI-Assisted Development** - From project architecture design to code implementation, powered by GitHub Copilot intelligent programming
- **Modern Swift/SwiftUI Best Practices** - AI ensures the use of latest iOS/macOS development patterns and APIs
- **Intelligent Code Generation** - Complex event monitoring, permission management, localization features generated and optimized by AI
- **Automated Documentation** - Project documentation, comments, localization strings all generated and maintained through AI

### Technical Implementation Highlights
- **MenuBarExtra API** - Utilizes macOS 13.0+ latest status bar API, with AI selecting the most suitable modern implementation approach
- **ObservableObject State Management** - AI-designed SwiftUI reactive architecture ensuring real-time state change responses
- **Modern Localization Solution** - Adopts Xcode 15+ .xcstrings format with AI-configured multi-language support
- **Permission Management Best Practices** - AI implements user-friendly permission request and error handling workflows

### AI Development Workflow
1. **Requirements Analysis** - AI analyzes user requirements and designs technical solutions
2. **Architecture Design** - AI selects the most suitable technology stack and architectural patterns
3. **Code Implementation** - AI generates core functionality code and optimizes performance
4. **Testing & Debugging** - AI assists with problem diagnosis and code debugging
5. **Documentation Enhancement** - AI automatically generates and maintains project documentation

> 💡 This project demonstrates the powerful capabilities of AI-assisted development in modern software engineering, showcasing full-cycle AI collaborative development from concept to product.

## Features

- 🔒 **Quick Lock/Unlock** - One-click keyboard locking to prevent accidental input
- ⌨️ **Global Hotkeys** - Support for `⌘ + ⌥ + L` shortcut for quick toggle (works even when locked)
- 📱 **Menu Bar Resident** - No Dock space usage, lightweight operation
- 🔔 **System Notifications** - Optional lock status change notifications
- 🌐 **Multi-language Support** - English and Simplified Chinese interface
- 🎨 **Native Design** - Built with SwiftUI and MenuBarExtra, perfectly integrated with macOS
- 🛡️ **Secure & Reliable** - Local operation, no data collection, privacy-respecting
- 🔐 **Permission Management** - Intelligent permission checking with user-friendly guidance interface
- ✨ **Status-based UI** - Dynamic button colors (red for locked, green for unlocked)
- 🛠️ **Enhanced Error Handling** - Built-in exception handling and recovery mechanisms
- ⚡ **Improved Stability** - Advanced cleanup on app termination and crash recovery

## Technology Stack

- **Swift 5.7+** - Primary programming language
- **SwiftUI** - User interface framework
- **MenuBarExtra** - Modern menu bar management API (macOS 13.0+)
- **AppKit** - macOS system integration
- **NSEvent** - Global keyboard event monitoring and hotkey handling
- **CGEvent** - Low-level keyboard event interception
- **UserNotifications** - Modern notification system
- **Xcode 15+ .xcstrings** - Modern localization file format
- **Info.plist Integration** - Dynamic copyright and version information

## Project Structure

```
KeyboardLocker/
├── KeyboardLocker/
│   ├── KeyboardLockerApp.swift      # App entry point using MenuBarExtra
│   ├── ContentView.swift           # Main interface view with lock controls
│   ├── SettingsView.swift          # Settings interface
│   ├── AboutView.swift             # About page
│   ├── KeyboardLockManager.swift   # Core keyboard locking logic
│   ├── LocalizationHelper.swift    # Localization utilities
│   ├── Localizable.xcstrings       # Modern localization strings file
│   ├── InfoPlist.xcstrings         # App name localization
│   ├── Info.plist                  # App configuration
│   └── Assets.xcassets/            # App resources and icons
├── KeyboardLocker.xcodeproj/        # Xcode project files
├── README.md                        # Project documentation
├── DEVELOPMENT.md                   # Developer guide
├── CHANGELOG.md                     # Version history
├── DOCS.md                         # Documentation overview
└── XCSTRINGS_GUIDE.md              # Localization configuration guide
```

## System Requirements

### Runtime Requirements
- **macOS 13.0 or later** - Required for MenuBarExtra API support

### Development Requirements
- **macOS 13.0 or later** - For development and testing
- **Xcode 14.0 or later** - MenuBarExtra API support
- **Swift 5.7 or later** - Modern Swift features

### Installation and Usage

#### Build from Source
1. Open `KeyboardLocker.xcodeproj` in Xcode
2. Select target device as "My Mac"
3. Ensure deployment target is set to macOS 13.0 or later
4. Click Run button or press `⌘ + R` to build and run

#### First Launch and Permission Setup
1. After launching, a shield icon 🛡️ will appear in the menu bar
2. If permissions are not granted, the app will display a permission setup screen:
   - **Accessibility Permission Required** - Click "Open System Settings" to navigate to permissions
   - Grant accessibility permission: System Settings > Privacy & Security > Accessibility
   - Return to the app and click "Check Permission Status" to refresh
3. Once permissions are granted, the main interface will be available
4. Optionally choose whether to allow notification permissions when prompted

#### Basic Usage
1. **Menu Bar Control** - Click the menu bar icon to show the main interface
2. **Lock Status Indication** - Green button background indicates unlocked, red indicates locked
3. **One-Click Toggle** - Click the lock/unlock button to change keyboard state
4. **Hotkey Control** - Use `⌘ + ⌥ + L` to quickly lock/unlock (available even when locked)
5. **Settings Access** - Click "Settings" button in main interface for additional configuration

## Main Features

### Keyboard Locking System
- **Global Event Interception** - Intercepts all keyboard input when locked
- **Smart Hotkeys** - Only preserves `⌘ + ⌥ + L` unlock combination
- **Status Visualization** - Real-time lock status indicators
- **System Integration** - Perfect integration with macOS Accessibility system

### User Interface
- **Permission-Aware Design** - Automatically detects permission status and shows appropriate interface
- **Modern Design** - Native SwiftUI MenuBarExtra popover interface
- **Multi-language Support** - English and Simplified Chinese using modern .xcstrings format
- **Responsive Layout** - Adapts to different screen sizes and system themes
- **Intuitive Operation** - One-click lock/unlock with color-coded status indication
- **Clear Permission Guidance** - Step-by-step permission setup with direct system settings access

### Settings Options
- **Notification Control** - Optional lock status change notifications
- **Interface Language** - Support for English and Simplified Chinese switching
- **App Information** - View version numbers, copyright info, etc.

### Security Features
- **Local Operation** - All functionality runs locally, no network access
- **Permission Transparency** - Only requests necessary Accessibility permissions
- **Data Privacy** - No collection, storage, or transmission of user data
- **Open Source Transparency** - Code is public and auditable for security

## Permissions

The app requires the following permissions:

- **Accessibility Permission** (Required) - Enables global keyboard event monitoring and control
  - First launch will show a permission setup screen if not granted
  - Click "Open System Settings" to navigate directly to permission settings
  - Located at: System Settings > Privacy & Security > Accessibility
  - Add "KeyboardLocker" to the allowed applications list
- **Notification Permission** (Optional) - Enables lock status change notifications
  - Automatically requested after accessibility permission is granted
  - Can be granted or denied without affecting core functionality

### Permission Setup Process
1. Launch the app for the first time
2. If accessibility permission is not granted, you'll see a permission setup screen
3. Click "Open System Settings" to open the relevant settings page
4. Enable KeyboardLocker in the Accessibility section
5. Return to the app and click "Check Permission Status"
6. Main interface will become available once permission is confirmed

## Development Notes

### Modern SwiftUI Architecture

The app uses modern SwiftUI App protocol and MenuBarExtra API:

```swift
@main
struct KeyboardLockerApp: App {
    @StateObject private var keyboardLockManager = KeyboardLockManager()
    
    var body: some Scene {
        MenuBarExtra("Keyboard Locker", systemImage: "lock.shield") {
            ContentView()
                .environmentObject(keyboardLockManager)
        }
        .menuBarExtraStyle(.window)
    }
}
```

### State Management Pattern
- **@StateObject** - Manages KeyboardLockManager lifecycle at App level
- **@EnvironmentObject** - Passes state between views, supports reactive updates
- **ObservableObject** - KeyboardLockManager implements state publishing and subscription

### Localization System
Uses Xcode 15+ modern .xcstrings format:

```swift
// Modern localization approach
Text(LocalizationKey.appTitle.localized)

// Supports dynamic version numbers
Text(Bundle.main.localizedVersionString)
```

### Permission Management
```swift
// Check Accessibility permission
let trusted = AXIsProcessTrusted()

// Request notification permission
UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
```

## Related Documentation

- **[BUILD.md](BUILD.md)** - Complete build instructions and deployment guide
- **[DEVELOPMENT.md](DEVELOPMENT.md)** - Developer guide and technical documentation
- **[CHANGELOG.md](CHANGELOG.md)** - Version history and update records
- **[XCSTRINGS_GUIDE.md](XCSTRINGS_GUIDE.md)** - Localization configuration guide
- **[DOCS.md](DOCS.md)** - Documentation overview and project architecture

### Quick Build Guide

To build a release version of the app:

```bash
# Using Make (recommended)
make build

# Or using script directly
./scripts/build_release.sh
```

See [BUILD.md](BUILD.md) for complete build instructions, installation options, and troubleshooting.

## Copyright

Copyright © 2025 Eden. All rights reserved.

## License

This project is for learning and personal use only.
