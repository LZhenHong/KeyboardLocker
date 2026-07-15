# Development Guide

Task-specific workflows and component reference. For the non-negotiable design rules, read [architecture.md](architecture.md) first — it always wins over anything here.

## XPC Communication Flow

All surfaces talk to the Agent over `KeyboardLockerServiceProtocol` (Mach service `io.lzhlovesjyq.keyboardlocker.agent`).

1. A wrapper (App/CLI/…) sends a **stateless one-off call** via the async `XPCClient`: `lock` / `unlock` / `status` / `applySettings` / `currentSettings` / `accessibilityStatus` / `requestAccessibilityPermission`. Failures throw (a dead Agent surfaces as a thrown error, never a hang).
2. The Agent's `ServiceDelegate` accepts the connection (after `XPCAccessControl` validates code signature + bundle ID) and routes to `AgentService`.
3. `AgentService` owns the settings source of truth (`KeyboardLockerSettingsStore`, in `Service`) and drives `LockEngine.shared.lock(settings:)` / `unlock()`.
4. `LockEngine` creates the CGEventTap and, on any state change, calls `LockStateBroadcaster.broadcast(isLocked:)`.
5. Wrappers observe state via `LockStateSubscriber.subscribe(_:)` (returns an `ObserverToken`) or `LockStateSubscriber.stateChanges` (`AsyncStream<Bool>`) — never by inferring from "did my call succeed".

> The lock is a single global boolean owned by the Agent, and `lock()` is **idempotent** (locking while locked re-applies settings and returns success). There is no client-owned "session"; every call is a one-off. The Agent must be `SMAppService`-registered so `launchd` starts it on demand — the App does this at launch via `AgentRegistrar` (see below).

## Component Map

Only the non-obvious responsibilities are listed; read the source for signatures.

**Common** (`Core/Sources/Common/`) — shared by all targets
- `Shared.swift`: `KeyboardLockerServiceProtocol` (locking + `applySettings(Data)`/`currentSettings` + accessibility), `SharedConstants` (Mach name, bundle-ID allowlist, CLI constants), `NotificationNames.stateChanged`.
- `KeyboardLockerSettings.swift`: `KeyboardLockerSettings` (`autoUnlockPolicy` = `.disabled`/`.timed(seconds:)`, `unlockHotkey`, `showsUnlockNotification`) + `.default` + `encodedForXPC()`/`decodedFromXPC(_:)` (JSON transport across the `@objc` boundary).
- `KeyCodeConverter.swift`: layout-aware `CGKeyCode` → shortcut string (⌃⌥⇧⌘ order) via `UCKeyTranslate`.

**Client** (`Core/Sources/Client/`) — App/CLI, never imports `Service`
- `XPCClient.swift`: async/throwing `XPCClient.shared` with one auto-reconnecting connection; `lock`/`unlock`/`status`/`applySettings`/`currentSettings`/`accessibilityStatus`/`requestAccessibilityPermission`. No "session" type.
- `LockStateSubscriber.swift`: subscribes to Darwin + Distributed broadcasts, treats each as a hint and fetches authoritative state via `XPCClient.status()` (retried, de-duplicated) → `ObserverToken`, plus `stateChanges` (`AsyncStream<Bool>`). Only long-lived UI needs this; one-shot surfaces read `status()` directly (see architecture "State Synchronization").

**Service** (`Core/Sources/Service/`) — Agent only
- `LockEngine.swift`: CGEventTap singleton, idempotent `lock(settings:)`, `updateSettings(_:)`, auto-unlock timer, hotkey detection, `OSAllocatedUnfairLock` state, `os.Logger`.
- `KeyboardLockerSettingsStore.swift`: `UserDefaults`-backed settings persistence — lives in `Service` so no wrapper can own its own store (contract source-of-truth rule).
- `LockStateBroadcaster.swift`: posts Darwin (payload-free) + Distributed (with payload) notifications.
- `AccessibilityManager.swift`, `XPCAccessControl.swift` (release = signature + Team ID + allowlist; debug = allowlist only), `XPCServerConnection.swift`.

**App** (`KeyboardLocker/`) — thin SwiftUI wrapper
- `AgentRegistrar.swift`: `SMAppService.agent(plistName:)` registration at launch (idempotent).
- `LockController.swift`: `@MainActor ObservableObject` view state — issues async `XPCClient` calls, reflects broadcast state, holds no lock/settings logic.
- `SystemSettings.swift`: opens the Accessibility pane (UI concern, App-local, not in `Common`).

## Common Tasks

### Add a setting
1. Add a `Codable`/`Sendable` property to `KeyboardLockerSettings` and update `.default`.
2. If the engine consumes it, read it in `LockEngine.lock(settings:)` / `updateSettings(_:)`.
3. Wrappers read/write settings only through `XPCClient.currentSettings()` / `applySettings(_:)`; the Agent persists via its `KeyboardLockerSettingsStore`. Wrappers must **not** own a store (see architecture contract).

### Add an XPC method
1. Add the signature to `KeyboardLockerServiceProtocol` in `Common/Shared.swift`. Values that aren't `@objc`-representable (like `KeyboardLockerSettings`) cross as JSON `Data` — reuse `encodedForXPC()`/`decodedFromXPC(_:)`.
2. Implement it in `KeyboardLockerAgent/AgentService.swift`.
3. Add a thin async wrapper on `XPCClient` in `Client/` if a surface needs it.

### Modify event filtering
In `LockEngine.handleEvent(proxy:type:event:)`: return `nil` to block, `Unmanaged.passUnretained(event)` to allow, and call `unlock()` when unlock conditions (hotkey or timeout) are met. `Hotkey.matches(keyCode:flags:)` filters CapsLock/NumLock via `relevantModifierMask`.

### CLI installation
`CLIInstaller` symlinks `/usr/local/bin/klock` → the CLI binary inside the app bundle (version consistency), prompting for admin via AppleScript. `install()`/`uninstall()` return `InstallResult` (`.success` / `.alreadyInstalled` / `.cancelled` / `.failed(Error)`); check `isInstalled` / `isCurrentVersionInstalled`.

## Testing Notes

- `LockEngine.lock` throws `.accessibilityPermissionDenied` when Accessibility permission is missing (checked before creating the event tap).
- The Agent must be running/registered (`SMAppService`) for XPC calls to succeed.
- Engine operations dispatch to the main thread for CFRunLoop access.
- The system may disable the event tap (timeout/user input); `LockEngine` attempts re-enable.
