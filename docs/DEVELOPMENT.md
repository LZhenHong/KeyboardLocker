# Developer Guide

## Architecture Overview

KeyboardLocker is split into two primary layers:

- **Core (Swift Package)** – Lives under `Core/` and exposes `KeyboardLockCore`, `PermissionHelper`, and shared models. It is responsible for the CGEvent tap, unlock-hotkey detection, and low-level locking behaviour. The unlocking logic is stateless and reacts directly to each `CGEvent`.
- **App Target (`KeyboardLocker`)** – SwiftUI Menu Bar app that hosts the UI, notifications, settings, and URL handling. `AppDependencies` wires the Core package into ObservableObject managers that are injected into views via `EnvironmentObject`.

Key UI components:

- `KeyboardLockerApp` – Entry point using `MenuBarExtra` with a dynamic status icon
- `KeyboardLockManager` – UI-facing bridge on top of `KeyboardLockCore`
- `NotificationManager`, `PermissionManager`, `UserActivityMonitor` – Supporting managers for UX
- `ContentView`, `SettingsView`, `StatusView` – SwiftUI surfaces for control and telemetry

## Technology Stack

- Swift 5.9+, SwiftUI, Combine
- MenuBarExtra (macOS 13.0+)
- CGEvent taps for keyboard interception
- `.xcstrings` localization resources
- URL schemes for external automation (`keyboardlocker://`)

## Local Setup

1. Clone the repository
2. Run `make quick` for a fast build or open `KeyboardLocker.xcodeproj`
3. Select the `KeyboardLocker` scheme and build/run (`⌘R`)
4. Approve Accessibility access when prompted (required for CGEvent taps)
5. If scripting Apple Events, macOS will later prompt for Automation permission

## Dependency Injection Pattern

`AppDependencies` centralises the Core package instances and exposes long-lived singletons to the UI layer. The app attaches them inside the menu bar scene:

```swift
MenuBarExtra {
    ContentView()
        .environmentObject(dependencies.keyboardLockManager)
        .environmentObject(dependencies.permissionManager)
} label: {
    MenuBarLabelView(keyboardLockManager: dependencies.keyboardLockManager)
}
```

Views then consume the environment objects:

```swift
struct ContentView: View {
    @EnvironmentObject private var keyboardLockManager: KeyboardLockManager

    var body: some View {
        Toggle(isOn: Binding(
            get: { keyboardLockManager.isLocked },
            set: { $0 ? keyboardLockManager.lockKeyboard()
                                : keyboardLockManager.unlockKeyboard() }
        )) {
            Text(keyboardLockManager.isLocked ? LocalizationKey.statusLocked.localized
                                                                                : LocalizationKey.statusUnlocked.localized)
        }
    }
}
```

## Hotkey Handling Reference

`KeyboardLockCore` analyses both `.keyDown` and `.flagsChanged` events to support modifier-only unlocks. The helper compares normalised event flags with the configured hotkey:

```swift
private func matchesUnlockModifiers(_ flags: CGEventFlags) -> Bool {
    flags.intersection(Self.relevantModifierMask) == unlockHotkey.eventModifierFlags
}
```

This logic makes the Core layer stateless and keeps lead-edge unlock detection robust.

## Contribution Guidelines

- Follow Swift API design guidelines and keep the Core package UI-agnostic
- Maintain localisation entries in `KeyboardLocker/i18n/*.xcstrings`
- Update documentation (README + docs/) when altering build or runtime behaviour
- Refer to [BUILD.md](BUILD.md) and [BUILD_SCRIPTS.md](BUILD_SCRIPTS.md) for build workflows
