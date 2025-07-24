# Developer Guide

## Architecture

- **KeyboardLockerApp** - MenuBarExtra app entry point
- **KeyboardLockManager** - Core locking logic (ObservableObject)  
- **ContentView** - Main interface with permission handling
- **SettingsView** - Configuration panel
- **LocalizationHelper** - i18n utilities

## Technology Stack

- Swift 5.7+ & SwiftUI
- MenuBarExtra (macOS 13.0+)
- CGEvent for keyboard interception
- .xcstrings for localization

## Setup

1. Clone repository
2. Open `KeyboardLocker.xcodeproj`
3. Build and run (`⌘+R`)
4. Grant accessibility permission

## Key Implementation

### State Management
```swift
@StateObject private var keyboardLockManager = KeyboardLockManager()
```

### Event Handling
```swift
private func handleKeyEvent(_ event: CGEvent) -> CGEvent? {
    if isUnlockHotkey(event) { // ⌘ + ⌥ + L
        unlockKeyboard()
        return event
    }
    return isLocked ? nil : event
}
```

### Localization
```swift
Text(LocalizationKey.appTitle.localized)
```

## Contributing

- Follow Swift API design guidelines
- Maintain internationalization  
- See [BUILD.md](BUILD.md) for build instructions
