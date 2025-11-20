# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

KeyboardLocker is a macOS application that locks keyboard and mouse input using CGEventTap. The project uses a three-tier architecture with XPC communication:

1. **KeyboardLocker** (Main App) - SwiftUI-based GUI application
2. **KeyboardLockerAgent** - XPC service that runs the lock engine (requires Accessibility permissions)
3. **klock** - CLI tool for lock/unlock operations
4. **Core** - Swift Package containing shared code and business logic

All three targets communicate via XPC using the `KeyboardLockerServiceProtocol` with the Mach service name `io.lzhlovesjyq.keyboardlocker.agent.service`.

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

### Encapsulation
- Hide implementation details using `private` or `fileprivate`
- Expose clear, minimal public interfaces
- Move nested conditionals into well-named methods
- Use `public` only for APIs consumed by other modules

### Code Quality Maintenance
- Refactor continuously as you work
- Fix technical debt when you encounter it
- Leave code cleaner than you found it
- Prefer editing existing code over creating new files

## Architecture Details

### XPC Communication Flow

1. **Main App → Agent**: `XPCClient.shared.lock()` creates an `NSXPCConnection` to the Mach service
2. **Agent receives request**: `ServiceDelegate` accepts connection and routes to `AgentService`
3. **Agent executes**: `AgentService.lockKeyboard()` calls `LockEngine.shared.lock(settings:)`
4. **Engine runs**: `LockEngine` creates a CGEventTap and optionally schedules auto-unlock timer

### Core Components

#### LockEngine (Core/Sources/Core/Engine/LockEngine.swift)
- Singleton that manages CGEventTap lifecycle
- Monitors keyboard/mouse events via `eventTapCallback` C function
- Supports auto-unlock via `DispatchSourceTimer` based on `AutoUnlockPolicy`
- Detects unlock hotkey combinations (default: ⌃⌘L)
- Thread safety: Assumes main thread usage for XPC handling
- Requires Accessibility permissions to create event tap

#### Settings System (Core/Sources/Core/Model/)
- `KeyboardLockerSettings`: Main settings struct with three components:
  - `autoUnlockPolicy`: Enum supporting `.disabled` or `.timed(seconds:)`
  - `unlockHotkey`: Stores `CGKeyCode` + `CGEventFlags` with validation
  - `showsUnlockNotification`: Boolean for UI notification preference
- `KeyboardLockerSettingsStore`: Persists settings to UserDefaults as JSON
- Settings are shared across App/Agent/CLI via UserDefaults (can be upgraded to App Group)

#### AutoUnlockPolicy
- `AutoUnlockPolicy` is `Identifiable` for SwiftUI integration (ForEach, Picker)
- Provides `.presets` array with common timeout values (disabled, 30s, 60s, 120s)
- The `timeout` computed property returns `TimeInterval?` for easy consumption

### Settings Integration Pattern

See `Docs/SettingsIntegration.md` for detailed guidance on how each target should use settings:

- **SwiftUI App**: Use `@ObservableObject` ViewModel wrapping `KeyboardLockerSettingsStore`
- **Agent**: Load settings before calling `LockEngine.shared.lock(settings:)`
- **CLI**: Load settings once to display unlock hotkey hints

### XPCClient Usage

The `XPCClient` singleton provides async methods with completion handlers:

```swift
XPCClient.shared.lock { error in
    if let error = error {
        // Handle error (usually means Agent not running or permission denied)
    }
}

XPCClient.shared.unlock { error in /* ... */ }

XPCClient.shared.status { isLocked, error in
    // Check current lock state
}
```

### Hotkey Matching

`Hotkey.matches(keyCode:flags:)` filters irrelevant modifiers (CapsLock, NumLock) using `relevantModifierMask` to ensure reliable matching in CGEventTap callbacks.

## Project Structure

```
KeyboardLocker/
├── Core/                           # Swift Package (shared logic)
│   ├── Package.swift               # SPM manifest (macOS 13+)
│   └── Sources/Core/
│       ├── Engine/
│       │   └── LockEngine.swift    # CGEventTap singleton
│       ├── Model/
│       │   ├── KeyboardLockerSettings.swift
│       │   └── KeyboardLockerSettingsStore.swift
│       ├── Protocol/
│       │   ├── KeyboardLockerServiceProtocol.swift  # XPC interface
│       │   └── SharedConstants.swift                # Mach service name
│       └── Client/
│           └── XPCClient.swift     # XPC client wrapper
├── KeyboardLocker/                 # Main SwiftUI app
│   ├── KeyboardLockerApp.swift
│   └── ContentView.swift
├── KeyboardLockerAgent/            # XPC service
│   ├── main.swift                  # NSXPCListener setup
│   ├── AgentService.swift          # Implements KeyboardLockerServiceProtocol
│   └── io.lzhlovesjyq.keyboardlocker.agent.plist
└── klock/                          # CLI tool
    └── main.swift                  # Argument parsing + XPCClient calls
```

## Common Patterns

### Adding New Settings

1. Add property to `KeyboardLockerSettings` struct (must be `Codable`, `Sendable`)
2. Update `KeyboardLockerSettings.default` static property
3. If needed by lock engine, modify `LockEngine.lock(settings:)` to consume it
4. SwiftUI views can bind directly to settings properties (use `Identifiable` for enum cases in pickers)

### Modifying Event Filtering

Event filtering logic is in `LockEngine.handleEvent(proxy:type:event:)`:
- Returns `nil` to block the event (locked state)
- Returns `Unmanaged.passUnretained(event)` to allow it through
- Call `unlock()` when unlock conditions are met (hotkey or auto-timeout)

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
