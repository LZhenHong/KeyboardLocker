# Development Guide

Task-specific workflows and component reference. For the non-negotiable design rules, read [architecture.md](architecture.md) first — it always wins over anything here.

## XPC Communication Flow

All surfaces talk to the Agent over `KeyboardLockerServiceProtocol` (Mach service `io.lzhlovesjyq.keyboardlocker.agent`).

1. A wrapper (App/CLI/…) sends a **stateless one-off call**: `lockKeyboard` / `unlockKeyboard` / `status` / `accessibilityStatus` / `requestAccessibilityPermission`.
2. The Agent's `ServiceDelegate` accepts the connection (after `XPCAccessControl` validates code signature + bundle ID) and routes to `AgentService`.
3. `AgentService` calls `LockEngine.shared.lock(settings:)` / `unlock()`.
4. `LockEngine` creates the CGEventTap and, on any state change, calls `LockStateBroadcaster.broadcast(isLocked:)`.
5. Wrappers observe state via `LockStateSubscriber.subscribe(_:)` (returns an `ObserverToken` that unsubscribes on deallocation) — never by inferring from "did my call succeed".

> The lock is a single global boolean owned by the Agent. Prefer the stateless `XPCClient.status/unlock` calls and the broadcast subscription. `LockSessionController` still exists in `XPCClient.swift` but implies client-owned "session" semantics that conflict with the architecture contract; treat it as legacy pending cleanup, don't build new features on it.

## Component Map

Only the non-obvious responsibilities are listed; read the source for signatures.

**Common** (`Core/Sources/Common/`) — shared by all targets
- `Shared.swift`: `KeyboardLockerServiceProtocol`, `SharedConstants` (Mach name, bundle-ID allowlist, CLI constants), `NotificationNames.stateChanged`.
- `KeyboardLockerSettings.swift`: `KeyboardLockerSettings` (`autoUnlockPolicy` = `.disabled`/`.timed(seconds:)`, `unlockHotkey`, `showsUnlockNotification`) + `.default`.
- `KeyCodeConverter.swift`: layout-aware `CGKeyCode` → shortcut string (⌃⌥⇧⌘ order) via `UCKeyTranslate`.
- `SystemSettings.swift`: opens the Accessibility pane.

**Client** (`Core/Sources/Client/`) — App/CLI, imports never `Service`
- `XPCClient.swift`: static `status` / `unlock` / `accessibilityStatus` / `requestAccessibilityPermission`.
- `LockStateSubscriber.swift`: distributed-notification subscription → `ObserverToken`.

**Service** (`Core/Sources/Service/`) — Agent only
- `LockEngine.swift`: CGEventTap singleton, auto-unlock timer, hotkey detection, `OSAllocatedUnfairLock` state.
- `LockStateBroadcaster.swift`: posts Darwin (payload-free) + Distributed (with payload) notifications.
- `AccessibilityManager.swift`, `XPCAccessControl.swift` (release = signature + Team ID + allowlist; debug = allowlist only), `XPCServerConnection.swift`.

## Common Tasks

### Add a setting
1. Add a `Codable`/`Sendable` property to `KeyboardLockerSettings` and update `.default`.
2. If the engine consumes it, read it in `LockEngine.lock(settings:)`.
3. SwiftUI binds to settings, but wrappers must **not** own a `KeyboardLockerSettingsStore` — the Agent is the source of truth (see architecture contract). Read/write through XPC.

### Add an XPC method
1. Add the signature to `KeyboardLockerServiceProtocol` in `Common/Shared.swift`.
2. Implement it in `KeyboardLockerAgent/AgentService.swift`.
3. Add a thin `XPCClient` wrapper in `Client/` if a surface needs it.

### Modify event filtering
In `LockEngine.handleEvent(proxy:type:event:)`: return `nil` to block, `Unmanaged.passUnretained(event)` to allow, and call `unlock()` when unlock conditions (hotkey or timeout) are met. `Hotkey.matches(keyCode:flags:)` filters CapsLock/NumLock via `relevantModifierMask`.

### CLI installation
`CLIInstaller` symlinks `/usr/local/bin/klock` → the CLI binary inside the app bundle (version consistency), prompting for admin via AppleScript. `install()`/`uninstall()` return `InstallResult` (`.success` / `.alreadyInstalled` / `.cancelled` / `.failed(Error)`); check `isInstalled` / `isCurrentVersionInstalled`.

## Testing Notes

- `LockEngine` throws `.eventTapCreationFailed` without Accessibility permission.
- The Agent must be running/registered (`SMAppService`) for XPC calls to succeed.
- Engine operations dispatch to the main thread for CFRunLoop access.
- The system may disable the event tap (timeout/user input); `LockEngine` attempts re-enable.
