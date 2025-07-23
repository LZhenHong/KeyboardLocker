# Changelog

All notable changes to the Keyboard Locker project will be documented in this file.

## [1.0.0]

### Added
- MenuBarExtra-based status bar application for macOS 13.0+
- Global keyboard locking functionality with CGEvent tap
- Dual hotkey support: `⌘ + ⌥ + L` (unlock) and `⌘ + ⌥ + ⇧ + L` (global lock)
- SwiftUI-based user interface with ContentView, SettingsView, and AboutView
- Multi-language support (English and Simplified Chinese) using .xcstrings format
- Accessibility permission management and user guidance
- UserNotifications-based status notifications
- Settings persistence using @AppStorage
- Exception handling and error recovery mechanisms
- Consolidated localization utilities in LocalizationHelper
- Dynamic copyright and version information from Info.plist
