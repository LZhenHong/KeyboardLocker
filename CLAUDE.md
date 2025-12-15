# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

KeyboardLocker is a macOS application that locks keyboard and mouse input using CGEventTap. The project uses a three-tier architecture with XPC communication:

1. **KeyboardLocker** (Main App) - SwiftUI-based GUI application
2. **KeyboardLockerAgent** - XPC service that runs the lock engine (requires Accessibility permissions)
3. **klock** - CLI tool for lock/unlock operations
4. **Core** - Swift Package with three targets:
   - **Common** - Shared protocols, constants, and settings
   - **Client** - XPC client for App/CLI (depends on Common)
   - **Service** - Lock engine and broadcasting for Agent (depends on Common)

All three targets communicate via XPC using the `KeyboardLockerServiceProtocol` with the Mach service name `io.lzhlovesjyq.keyboardlocker.agent`.

## Build Commands

```bash
# Build the entire project
xcodebuild -scheme KeyboardLocker -configuration Debug build

# Build specific targets
xcodebuild -scheme KeyboardLockerAgent -configuration Debug build
xcodebuild -scheme klock -configuration Debug build
xcodebuild -scheme Core -configuration Debug build

# Build for release
xcodebuild -scheme KeyboardLocker -configuration Release build
```

## Code Formatting

This project uses SwiftFormat with a custom configuration in `.swiftformat`:
- 2-space indentation
- Visual width for asset literals
- Alpha-sorted imports
- Always wrap enum cases
- Remove self where possible

Format code before committing:
```bash
swiftformat .
```

## Code Style Guidelines

### DRY Principle (Don't Repeat Yourself)
**Critical**: Code duplication is strictly prohibited as it leads to exponential maintenance complexity.
- Extract repeated code into reusable functions or abstractions
- Share common logic through proper abstraction layers
- Maintain single sources of truth for all business logic
- If you find yourself copying code, stop and refactor into a shared component

### Comments
- **Language**: Always use English for comments
- **Brevity**: Keep comments concise and to the point
- **Self-Documenting Code First**: Prioritize readable code that explains itself through clear naming and structure
- **Explain Why, Not What**: Comments should explain the reasoning behind decisions, not describe what the code does
  ```swift
  // Good: Explains reasoning
  // Use relevantModifierMask to filter CapsLock state which causes spurious mismatches
  let normalizedFlags = flags.intersection(Self.relevantModifierMask)

  // Bad: Describes what code does
  // Intersect flags with relevantModifierMask and assign to normalizedFlags
  let normalizedFlags = flags.intersection(Self.relevantModifierMask)
  ```
- **When to Comment**:
  - Non-obvious algorithmic choices
  - Workarounds for system limitations or bugs
  - Public API documentation
  - Complex business logic that can't be simplified

### Meaningful Names
- Variables, functions, and types should reveal their purpose
- Names should explain why something exists and how it's used
- Avoid abbreviations unless universally understood (e.g., XPC, CGEvent)
- Use Swift naming conventions: `lowerCamelCase` for properties/methods, `UpperCamelCase` for types

### Single Responsibility
- Each function should do exactly one thing
- Functions should be small and focused
- If a function needs extensive comments to explain what it does, consider splitting it
- Extract complex conditions into well-named computed properties or methods

### Constants Over Magic Values
- Replace hard-coded values with named constants
- Use descriptive constant names that explain the value's purpose
- Centralize constants in `SharedConstants` or at type level

### Swift Best Practices

**Critical**: Use modern Swift idioms. Avoid legacy Objective-C patterns unless required for interoperability.

#### Error Handling
- **Use Swift `Error` enum** instead of `NSError`:
  ```swift
  // Good: Swift Error enum
  public enum XPCClientError: Error {
    case serviceUnavailable
    case connectionFailed(underlying: Error)
  }

  // Bad: NSError
  NSError(domain: "XPCClient", code: -1, userInfo: [...])
  ```
- Implement `LocalizedError` for user-facing error messages
- Use `Result<T, Error>` or `throws` for synchronous operations

#### Avoid Singleton Abuse
- **Use caseless `enum`** for namespaces with only static methods:
  ```swift
  // Good: Caseless enum namespace
  public enum XPCClient {
    public static func status(reply: @escaping (Bool, Error?) -> Void) { }
  }

  // Bad: Singleton for stateless operations
  public class XPCClient {
    public static let shared = XPCClient()
    private init() {}
  }
  ```
- Reserve singletons for truly stateful shared resources (e.g., `LockEngine.shared`)
- Prefer static methods for stateless operations

#### Prefer Swift Types Over Foundation
- Use `String` over `NSString`
- Use `Array`/`Dictionary`/`Set` over `NSArray`/`NSDictionary`/`NSSet`
- Use `Data` over `NSData`
- Use `URL` over `NSURL`
- Use `Date` over `NSDate`

#### Type Safety
- Prefer `enum` with associated values over stringly-typed APIs
- Use `Codable` for serialization instead of manual dictionary parsing
- Leverage generics for type-safe abstractions
- Use `@frozen` for enums when ABI stability is needed

#### Modern Swift Features
- Use `if let`/`guard let` shorthand: `if let value { }` instead of `if let value = value { }`
- Use `async/await` for new asynchronous code where possible
- Prefer `some Protocol` (opaque types) over concrete return types for abstraction
- Use property wrappers (`@State`, `@Published`) appropriately in SwiftUI

#### Avoid Force Unwrapping
- Never use `!` except for `@IBOutlet` or truly impossible `nil` cases
- Use `guard let` for early returns
- Use `??` with sensible defaults
- Use `fatalError()` with descriptive message for programmer errors

### Access Control & Encapsulation

**Critical**: Proper access control is essential for maintainable code. Default to the most restrictive access level and only increase visibility when necessary.

#### Access Level Hierarchy (from most to least restrictive)

1. **`private`** - Only accessible within the declaring scope
   - Use for implementation details
   - Helper methods and properties
   - Internal state management

2. **`fileprivate`** - Accessible within the same file
   - Use for tightly coupled types in the same file
   - Required for C callback access (e.g., CGEventTap callbacks)
   - Extensions accessing private members

3. **`internal`** - Accessible within the same module (default)
   - Use for module-internal APIs
   - Types/methods used across files in the module
   - Testing helpers (when in same module)

4. **`public`** - Accessible from other modules
   - **Only use for intentional public APIs**
   - Core Package APIs consumed by App/Agent/CLI
   - Well-documented with parameter descriptions
   - Must be stable and backward-compatible

#### Interface Convergence Rules

**Minimize Public Surface Area**: Every public API is a commitment. The more you expose, the harder it is to refactor.

```swift
// Good: Minimal public interface
public class XPCClient {
  public static let shared = XPCClient()

  public func lock(reply: @escaping (Error?) -> Void) { }
  public func unlock(reply: @escaping (Error?) -> Void) { }
  public func status(reply: @escaping (Bool, Error?) -> Void) { }

  private init() { }  // Singleton pattern
  private func createConnection() -> NSXPCConnection { }  // Implementation detail
  private func executeRemoteCall(...) { }  // Helper method
}

// Bad: Over-exposed implementation
public class XPCClient {
  public init() { }  // Should be private for singleton
  public func createConnection() -> NSXPCConnection { }  // Should be private
  public var connectionCache: [String: NSXPCConnection] = [:]  // Should be private
}
```

#### Access Control Checklist

Before making something `public`, ask:
- ✅ Is this intentionally part of the module's public API?
- ✅ Is it documented with usage examples?
- ✅ Will other modules genuinely need to call this?
- ✅ Am I prepared to maintain backward compatibility?

If any answer is "no", use a more restrictive access level.

#### Common Patterns

**Singletons**: `private init()` to prevent instantiation
```swift
public class LockEngine {
  public static let shared = LockEngine()
  private init() { }
}
```

**Read-only public state**: `public private(set)`
```swift
public class LockEngine {
  public private(set) var isLocked = false  // Read publicly, write privately
}
```

**Internal helpers**: Keep `private` unless needed across files
```swift
private func validateSettings(_ settings: KeyboardLockerSettings) -> Bool {
  // Implementation detail, not part of public API
}
```

**Type-level access**: Mark entire types `private` or `fileprivate` when only used locally
```swift
// In main.swift - only used in this file
private final class ServiceDelegate: NSObject, NSXPCListenerDelegate {
  // ...
}
```

### Code Quality Maintenance
- Refactor continuously as you work
- Fix technical debt when you encounter it
- Leave code cleaner than you found it
- Prefer editing existing code over creating new files

### Resource and Code Cleanup

**Critical**: Unused code and resources create maintenance burden, confusion, and increase codebase complexity.

- **Remove Dead Code**: Delete functions, classes, properties, and variables that are never referenced
  - Use Xcode's warnings and static analysis to identify unused code
  - Don't keep code "just in case" — version control preserves history
  - Remove entire files that no longer serve a purpose
  - Trust git for historical reference instead of leaving unused code in the codebase

- **Delete Commented-Out Code**: Never commit commented-out code
  - If code is no longer needed, delete it completely
  - Version control (git) preserves history if you need to reference old implementations
  - Exception: Temporary debugging comments during active development (remove before committing)
  - Commented code creates ambiguity about what's actually in use

- **Clean Up Unused Resources**:
  - Remove unused assets from Asset Catalogs (images, colors, data)
  - Delete unreferenced files (images, JSON, plists) from project directories
  - Use Xcode's "Find Unused Resources" and build warnings to identify orphaned assets
  - Audit resource bundles periodically to ensure all files are actually used

- **Localization String Cleanup**:
  - Regularly audit `.xcstrings` files for unused localization keys
  - Remove strings that are no longer referenced in code
  - Keep localization files synchronized with actual usage
  - Use string catalog warnings to identify unreferenced keys
  - Don't accumulate "just in case" translations that bloat the app

- **Remove Deprecated Code**:
  - When deprecating APIs, set a clear timeline for removal
  - Don't accumulate deprecated code indefinitely
  - Provide migration paths and warnings before removing deprecated APIs
  - After the deprecation period, delete the old implementation completely
  - Use `@available` attributes with clear messages when deprecating

**Cleanup Workflow**:
1. Before each commit: Review your changes for any commented-out code or unused imports
2. During refactoring: Delete code/resources made obsolete by the refactor
3. Periodic audits: Use Xcode's analyzer and build warnings to identify cleanup opportunities
4. When removing features: Delete all associated code, resources, and localization strings

## Architecture Details

### XPC Communication Flow

1. **Main App → Agent**: `XPCClient.startLockSession()` creates an `NSXPCConnection` to the Mach service
2. **Agent receives request**: `ServiceDelegate` accepts connection and routes to `AgentService`
3. **Agent executes**: `AgentService.lockKeyboard()` calls `LockEngine.shared.lock(settings:)`
4. **Engine runs**: `LockEngine` creates a CGEventTap and optionally schedules auto-unlock timer

### Core Components

### Common Target (Core/Sources/Common/)

#### Shared.swift
- `KeyboardLockerServiceProtocol`: XPC protocol for lock/unlock operations
- `SharedConstants`: Mach service name, default unlock keycode, authorized bundle IDs
- `NotificationNames.stateChanged`: Shared notification identifier for cross-process state changes

#### Settings System
- `KeyboardLockerSettings`: Main settings struct with three components:
  - `autoUnlockPolicy`: Enum supporting `.disabled` or `.timed(seconds:)`
  - `unlockHotkey`: Stores `CGKeyCode` + `CGEventFlags` with validation
  - `showsUnlockNotification`: Boolean for UI notification preference
- `KeyboardLockerSettingsStore`: Persists settings to UserDefaults as JSON
- `AutoUnlockPolicy` is `Identifiable` for SwiftUI integration (ForEach, Picker)
- Settings are shared across App/Agent/CLI via UserDefaults

#### SystemSettings.swift
- `SystemSettings.openAccessibilitySettings()`: Opens System Settings to Accessibility pane

### Client Target (Core/Sources/Client/)

#### XPCClient.swift
- Static methods for one-off XPC queries: `status()`, `accessibilityStatus()`, `unlock()`
- `startLockSession()`: Creates persistent `LockSessionController` for lock/unlock operations
- Session-based lock with optional state change notifications

#### LockStateSubscriber.swift
- `LockStateSubscriber.subscribe(_:)`: Subscribes to DistributedNotification for state changes
- Returns `ObserverToken` for automatic cleanup on deallocation
- Used by App/CLI to receive state changes from Agent

### Service Target (Core/Sources/Service/)

#### LockEngine.swift
- Singleton that manages CGEventTap lifecycle
- Monitors keyboard/mouse events via `eventTapCallback` C function
- Supports auto-unlock via `DispatchSourceTimer` based on `AutoUnlockPolicy`
- Detects unlock hotkey combinations (default: ⌃⌘L)
- Thread safety: Uses `OSAllocatedUnfairLock` for state protection
- Calls `LockStateBroadcaster.broadcast()` on state changes

#### LockStateBroadcaster.swift
- `LockStateBroadcaster.broadcast(isLocked:)`: Posts state to Darwin and Distributed notifications
- Darwin: Lightweight, no payload (for CLI, scripts, Shortcuts)
- Distributed: With payload (for widgets, extensions, other apps)

#### AccessibilityManager.swift
- `hasPermission()`: Checks if Accessibility permission is granted
- `requestPermission()`: Triggers macOS system prompt

#### XPCAccessControl.swift
- Validates XPC connections via code signature and bundle identifier
- **Release**: Full verification (signature + Team ID + bundle ID allowlist)
- **Debug**: Relaxed verification (bundle ID allowlist only)

#### XPCServerConnection.swift
- `configure(_:exportedService:)`: Configures incoming Agent connections

### Settings Integration Pattern

- **SwiftUI App**: Use `@ObservableObject` ViewModel wrapping `KeyboardLockerSettingsStore`
- **Agent**: Load settings before calling `LockEngine.shared.lock(settings:)`
- **CLI**: Load settings once to display unlock hotkey hints

### XPCClient Usage

The `XPCClient` enum provides static methods for one-off queries and session-based lock management:

```swift
import Client

// One-off queries (stateless)
XPCClient.status { isLocked, error in
    // Check current lock state
}

XPCClient.accessibilityStatus { granted in
    // Check if Agent has accessibility permissions
}

// Force unlock (bypasses session ownership)
XPCClient.unlock { error in /* ... */ }

// Session-based lock without state notifications
let session = XPCClient.startLockSession()
session.lock { error in /* ... */ }
session.unlock { error in /* ... */ }
// Connection auto-invalidates when session is deallocated

// Session-based lock WITH state notifications via DistributedNotification
let session = XPCClient.startLockSession { isLocked in
    print("Lock state changed: \(isLocked)")
}
// Automatically subscribes to DistributedNotification for cross-process state updates
```

### Hotkey Matching

`Hotkey.matches(keyCode:flags:)` filters irrelevant modifiers (CapsLock, NumLock) using `relevantModifierMask` to ensure reliable matching in CGEventTap callbacks.

## Project Structure

```
KeyboardLocker/
├── Core/                           # Swift Package (three targets)
│   ├── Package.swift               # SPM manifest (macOS 13+)
│   └── Sources/
│       ├── Common/                 # Shared code (both targets depend on this)
│       │   ├── Shared.swift        # KeyboardLockerServiceProtocol, SharedConstants, NotificationNames
│       │   ├── KeyboardLockerSettings.swift
│       │   ├── KeyboardLockerSettingsStore.swift
│       │   └── SystemSettings.swift
│       ├── Client/                 # App/CLI only (depends on Common)
│       │   ├── Exports.swift       # @_exported import Common
│       │   ├── XPCClient.swift     # XPC client + LockSessionController
│       │   └── LockStateSubscriber.swift
│       └── Service/                # Agent only (depends on Common)
│           ├── Exports.swift       # @_exported import Common
│           ├── LockEngine.swift    # CGEventTap singleton
│           ├── LockStateBroadcaster.swift
│           ├── AccessibilityManager.swift
│           ├── XPCAccessControl.swift
│           └── XPCServerConnection.swift
├── KeyboardLocker/                 # Main SwiftUI app (imports Client)
│   ├── KeyboardLockerApp.swift
│   └── ContentView.swift
├── KeyboardLockerAgent/            # XPC service (imports Service)
│   ├── main.swift                  # NSXPCListener setup
│   ├── AgentService.swift          # Implements KeyboardLockerServiceProtocol
│   └── io.lzhlovesjyq.keyboardlocker.agent.plist
└── klock/                          # CLI tool (imports Client)
    └── main.swift                  # Argument parsing + XPCClient calls
```

### Target Dependencies

| Component | Imports | Purpose |
|-----------|---------|---------|
| KeyboardLocker (App) | `Client` | XPC calls, state subscription |
| KeyboardLockerAgent | `Service` | Lock engine, broadcasting |
| klock (CLI) | `Client` | XPC calls |

Note: `Client` and `Service` both re-export `Common` via `@_exported import Common`, so importing either gives access to shared types like `SharedConstants` and `KeyboardLockerSettings`.

## Common Patterns

### Adding New Settings

1. Add property to `KeyboardLockerSettings` struct in `Common/` (must be `Codable`, `Sendable`)
2. Update `KeyboardLockerSettings.default` static property
3. If needed by lock engine, modify `LockEngine.lock(settings:)` in `Service/` to consume it
4. SwiftUI views can bind directly to settings properties (use `Identifiable` for enum cases in pickers)

### Modifying Event Filtering

Event filtering logic is in `Service/LockEngine.handleEvent(proxy:type:event:)`:
- Returns `nil` to block the event (locked state)
- Returns `Unmanaged.passUnretained(event)` to allow it through
- Call `unlock()` when unlock conditions are met (hotkey or auto-timeout)

### Adding New XPC Methods

1. Add method signature to `KeyboardLockerServiceProtocol` in `Common/Shared.swift`
2. Implement method in `KeyboardLockerAgent/AgentService.swift`
3. Add client wrapper in `Client/XPCClient.swift` if needed

### Bundle Identifiers

- Main App: `io.lzhlovesjyq.keyboardlocker`
- Agent: `io.lzhlovesjyq.keyboardlocker.agent`
- CLI: `io.lzhlovesjyq.keyboardlocker.klock`

## Testing Considerations

- **Accessibility Permissions**: LockEngine will throw `.eventTapCreationFailed` if not granted
- **Agent Lifecycle**: Agent must be running for XPC calls to succeed
- **Main Thread**: LockEngine operations dispatch to main thread for CFRunLoop access
- **Event Tap Reliability**: System may disable event tap (timeout/user input); LockEngine attempts re-enable

## Key Dependencies

- CoreGraphics (CGEventTap, CGEvent)
- AppKit (NSXPCConnection, NSXPCListener)
- Foundation (UserDefaults, Codable, DispatchSourceTimer)
- Security (SecStaticCode, code signature verification for XPC access control)
- os (OSAllocatedUnfairLock for thread-safe state management)
