# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 🌍 CRITICAL RULE: Multi-Language Support

**This project supports multiple languages. ALL user-facing text changes MUST be updated in ALL supported languages (English + Simplified Chinese).**

Before making any changes to text, notifications, UI labels, or error messages:
- ✅ Check `KeyboardLocker/i18n/*.xcstrings` files
- ✅ Update BOTH English (`en`) and Simplified Chinese (`zh-Hans`) variants
- ✅ Never leave incomplete translations

See the [Localization](#localization) section below for detailed guidelines.

---

## 💎 Coding Principles

### DRY Principle (Don't Repeat Yourself)

**Code duplication is STRICTLY PROHIBITED. Follow DRY principle at all times.**

1. **Eliminate code duplication:**
   - ❌ NEVER copy-paste code between files or functions
   - ✅ Extract shared logic into helper functions, classes, or modules
   - ✅ Create abstractions for common patterns
   - Example: `AppIntentHelper.swift` consolidates shared logic for all AppIntents

2. **Reuse existing code:**
   - ✅ ALWAYS search the codebase for existing implementations before writing new code
   - ✅ Use existing helpers, utilities, and managers
   - ✅ Prefer calling existing functions over reimplementing logic
   - Example: Shortcuts use URL schemes which reuse `URLCommandHandler`

3. **Refactor when needed:**
   - ✅ If existing code doesn't fully meet requirements, refactor it to be more general
   - ✅ Make existing code reusable rather than duplicating and modifying
   - ✅ Update all call sites when refactoring shared code

**Why this matters:** Code duplication exponentially increases maintenance burden. A bug in duplicated code must be fixed in multiple places, increasing the risk of inconsistencies.

### Comments and Documentation

**Write self-documenting code. Minimize comments.**

1. **Code should explain itself:**
   - ✅ Use clear, descriptive variable and function names
   - ✅ Write small, focused functions with single responsibilities
   - ✅ Structure code logically to reveal intent
   - ❌ DO NOT add comments that merely repeat what the code does

2. **When to add comments:**
   - ✅ Complex algorithms that aren't immediately obvious
   - ✅ Non-obvious workarounds for platform limitations
   - ✅ Critical business logic decisions
   - ✅ Public API documentation
   - ❌ DO NOT comment every line or function

3. **Examples:**
   ```swift
   // ❌ Bad: Comment repeats the code
   // Lock the keyboard
   keyboardLockCore.lock()

   // ✅ Good: Code is self-explanatory
   keyboardLockCore.lock()

   // ✅ Good: Comment explains WHY, not WHAT
   // CGEvent taps require active run loop, so we use URL scheme to ensure app stays running
   try await AppIntentHelper.executeCommand(command, wasAppRunning: wasRunning)
   ```

### Documentation Files

**Keep only essential documentation. Avoid redundancy.**

1. **Before creating a new document:**
   - ❓ Can this information be added to existing documentation?
   - ❓ Will this document become outdated quickly?
   - ❓ Is this information already in code comments or README?

2. **Essential documents only:**
   - ✅ `CLAUDE.md` - Developer guide for Claude Code (architecture, principles, key components)
   - ✅ `README.md` - User-facing documentation (installation, usage, features)
   - ✅ `docs/` - Specific guides that can't fit in README
   - ❌ DO NOT create separate docs for every feature or implementation detail
   - ❌ DO NOT create documents that duplicate information from other docs

3. **Documentation maintenance:**
   - If information changes, update existing docs rather than adding new ones
   - Remove outdated documentation immediately
   - Consolidate related information into single documents

**Why this matters:** Excessive documentation becomes stale quickly and creates confusion. Developers waste time maintaining redundant docs or reading outdated information.

---

## Project Overview

KeyboardLocker is a macOS menu bar application for locking and unlocking keyboard input. It uses CGEvent taps for keyboard interception and supports multiple control interfaces: GUI menu bar app, CLI tool, URL schemes, and AppleScript commands.

## Build Commands

### Primary Build Commands (via Makefile)
```bash
# Quick release build for local testing (recommended for development)
make quick

# Full signed and archived release build
make build

# Build CLI tool only
make cli

# Clean all build artifacts
make clean

# Install app to /Applications (runs full build first)
make install
```

### Output Locations
- App: `Build/KeyboardLocker.app`
- CLI tool: `Build/CLI/KeyboardLockerTool`
- Release info: `Build/ReleaseInfo.txt`

### Direct Xcode Commands
```bash
# Build app in Debug configuration
xcodebuild -scheme KeyboardLocker -configuration Debug build

# Build CLI tool in Release configuration
xcodebuild -project KeyboardLocker.xcodeproj -scheme KeyboardLockerTool -configuration Release build
```

### Build Scripts
- `scripts/build_release.sh` - Full archive and export pipeline
- `scripts/quick_build.sh` - Fast Release build without archiving
- `scripts/build_cli.sh` - Standalone CLI binary builder

## Architecture

### Three-Layer Structure

**1. Core Package (`Core/`)**
- Swift Package exposing `KeyboardLockCore`, `PermissionHelper`, `UserActivityMonitor`, and shared models
- Responsible for CGEvent tap creation, keyboard event interception, and unlock hotkey detection
- **Stateless unlock logic** - reacts directly to each `CGEvent` without tracking state transitions
- UI-agnostic and reusable across app and CLI targets

**2. App Target (`KeyboardLocker/`)**
- SwiftUI MenuBarExtra app with menu bar icon that changes between `lock.open` and `lock`
- `AppDependencies` wires Core package into ObservableObject managers
- Managers are injected into views via `@EnvironmentObject`
- Handles notifications, settings persistence, URL schemes, and AppleScript commands

**3. CLI Target (`KeyboardLockerTool/`)**
- Standalone command-line wrapper around `KeyboardLockCore`
- Entry point: `KeyboardLockerTool/main.swift`
- Commands: `lock`, `unlock`, `toggle`, `--help`
- The `lock` command blocks until unlocked, pumping the run loop to keep event tap alive
- Shares `CoreConfiguration.shared` and `KeyboardLockCore.shared` with the app

### Key Components

**Core Package:**
- `KeyboardLockCore` - Singleton managing CGEvent tap and lock state
- `PermissionHelper` - Accessibility permission checking
- `UserActivityMonitor` - Auto-lock idle timer using system activity
- `CoreConfiguration` - Shared configuration between app and CLI
- `HotkeyConfiguration` - Hotkey representation with modifiers and key codes

**App Layer:**
- `AppDependencies` - Dependency injection container creating all managers
- `KeyboardLockManager` - UI-facing bridge wrapping `KeyboardLockCore`
- `NotificationManager` - System notifications for lock/unlock events
- `PermissionManager` - Permission UI and status tracking
- `URLCommandHandler` - Handles `keyboardlocker://` URL scheme commands
- `ScriptCommands.swift` - AppleScript command handlers (`LockKeyboardCommand`, `UnlockKeyboardCommand`, `ToggleKeyboardLockCommand`)

**Views:**
- `KeyboardLockerApp` - App entry point using `MenuBarExtra`
- `ContentView` - Main menu dropdown with lock toggle
- `SettingsView` - Configuration for notifications, auto-lock, and hotkey
- `StatusView` - Lock status display with duration
- `PermissionView` - Accessibility permission prompt

### Dependency Injection Pattern

`AppDependencies` centralizes Core package instances and exposes them to the UI layer:

```swift
MenuBarExtra {
    ContentView()
        .environmentObject(dependencies.keyboardLockManager)
        .environmentObject(dependencies.permissionManager)
}
```

Views consume via `@EnvironmentObject`:

```swift
struct ContentView: View {
    @EnvironmentObject private var keyboardLockManager: KeyboardLockManager
    // ...
}
```

### Hotkey Detection

`KeyboardLockCore` handles both `.keyDown` and `.flagsChanged` events for modifier-only unlocks. The unlock logic is **stateless** - it compares event flags directly with the configured hotkey without tracking state:

```swift
private func matchesUnlockModifiers(_ flags: CGEventFlags) -> Bool {
    flags.intersection(Self.relevantModifierMask) == unlockHotkey.eventModifierFlags
}
```

When unlock hotkey is detected, Core invokes `onUnlockHotkeyDetected` callback which triggers unlock in the UI or CLI layer.

## Technology Stack

- Swift 5.9+, SwiftUI, Combine
- MenuBarExtra (requires macOS 13.0+)
- CGEvent taps for keyboard interception
- `.xcstrings` localization (English and Simplified Chinese)
- URL schemes: `keyboardlocker://lock`, `keyboardlocker://unlock`, `keyboardlocker://toggle`, `keyboardlocker://status`
- AppleScript integration via `.sdef` scripting definition
- AppIntents framework for native Shortcuts support (macOS 13.0+)

## Control Interfaces

KeyboardLocker supports 5 different control methods for maximum flexibility:

### 1. GUI Menu Bar App
- Click menu bar icon → toggle lock/unlock
- Global hotkey: `⌘ + ⌥ + L` (configurable)
- Settings for notifications, auto-lock timer, and custom hotkey

### 2. CLI Tool
```bash
# Lock and wait until unlocked
./Build/CLI/KeyboardLockerTool lock

# Unlock immediately
./Build/CLI/KeyboardLockerTool unlock

# Toggle current state
./Build/CLI/KeyboardLockerTool toggle
```

### 3. URL Schemes
```bash
# Via open command
open "keyboardlocker://lock"
open "keyboardlocker://unlock"
open "keyboardlocker://toggle"
open "keyboardlocker://status"
```

### 4. AppleScript
```applescript
tell application "KeyboardLocker"
    lock
    -- or: unlock
    -- or: toggle
end tell
```

### 5. Shortcuts (Native App Intents)

KeyboardLocker provides native Shortcuts support via AppIntents framework, allowing seamless integration with macOS Shortcuts app and Siri.

**Available Actions:**
1. **Set Keyboard Lock State** - Set the keyboard to locked or unlocked state using a boolean parameter (`shouldLock`)
2. **Toggle Keyboard Lock** - Toggles between locked and unlocked states

**Implementation:**
- `SetKeyboardLockStateIntent` - Located in `KeyboardLocker/Sources/Intents/SetKeyboardLockStateIntent.swift`
  - Has a `shouldLock` boolean parameter to control whether to lock (true) or unlock (false)
- `ToggleKeyboardLockIntent` - Located in `KeyboardLocker/Sources/Intents/ToggleKeyboardLockIntent.swift`
  - No parameters, simply toggles the current state
- `KeyboardLockerShortcuts` - App Shortcuts provider defining default shortcuts with Siri phrases
- `IntentErrors` - Shared error definitions for all intents

**Important Implementation Details:**
- AppIntents run in a **separate process**, not in the KeyboardLocker app process
- CGEvent taps require a **continuously running app** with an active run loop to function
- Therefore, Shortcuts use **URL Schemes internally** to communicate with the running app
- If the app is not running, the Intent will automatically launch it in the background (hidden)
- The actual lock/unlock operation happens in the app process via URL handler

**Usage:**

For **Set Keyboard Lock State** action:
1. Open Shortcuts app
2. Create new shortcut
3. Search for "Set Keyboard Lock" or "KeyboardLocker"
4. Add "Set Keyboard Lock State" action
5. Configure the `shouldLock` parameter (true to lock, false to unlock)
6. Run via Shortcuts app, Siri, or automation

For **Toggle Keyboard Lock** action:
1. Open Shortcuts app
2. Create new shortcut
3. Search for "Toggle" or "KeyboardLocker"
4. Add "Toggle Keyboard Lock" action (no parameters needed)
5. Run via Shortcuts app, Siri, or automation

**Permissions:**
- Requires Accessibility permission (same as app)
- First-time usage will prompt for Automation permission if triggered from external apps
- App must have permission to run in the background (granted automatically for menu bar apps)

**Requirements:**
- KeyboardLocker app must be installed in `/Applications` or a standard location
- The app will automatically launch in the background if not already running
- Shortcuts actions communicate with the running app via URL Schemes (`keyboardlocker://`)

**Localization:**
All Shortcuts actions, descriptions, and error messages are fully localized in:
- English (en)
- Simplified Chinese (zh-Hans)

Localization keys in `KeyboardLocker/i18n/Localizable.xcstrings`:
- `shortcuts.intent.*` - Intent titles and descriptions
- `shortcuts.action.*` - Short titles for actions
- `shortcuts.error.*` - Error messages

## Localization

### ⚠️ CRITICAL: Multi-Language Support Requirements

**EVERY text change MUST be updated in ALL supported languages.**

When modifying any user-facing text:
1. ✅ Update ALL language variants in `.xcstrings` files
2. ✅ Maintain consistent tone and meaning across languages
3. ✅ Test that all localizations display correctly
4. ❌ NEVER leave placeholder text like "TODO" or English text in non-English languages
5. ❌ NEVER add new strings without providing all translations

### Supported Languages

Currently supported:
- **English (en)** - Primary/default language
- **Simplified Chinese (zh-Hans)** - 简体中文

### Localization Files

Located in `KeyboardLocker/i18n/`:
- `Localizable.xcstrings` - UI strings (buttons, labels, notifications, settings, etc.)
- `InfoPlist.xcstrings` - App metadata strings (app name, permissions descriptions)

### How to Add/Modify Localized Strings

1. **For code changes:**
   - Use `LocalizationKey` enum for type-safe string access
   - Example: `Text(LocalizationKey.lockKeyboard.localizedString)`

2. **For .xcstrings file changes:**
   - Open the `.xcstrings` file in Xcode String Catalog editor
   - Add/modify the key and provide values for BOTH `en` and `zh-Hans`
   - Alternatively, edit the JSON structure directly:
   ```json
   "your.key.name" : {
     "extractionState" : "manual",
     "localizations" : {
       "en" : {
         "stringUnit" : {
           "state" : "translated",
           "value" : "English text here"
         }
       },
       "zh-Hans" : {
         "stringUnit" : {
           "state" : "translated",
           "value" : "中文文本"
         }
       }
     }
   }
   ```

3. **Translation quality guidelines:**
   - Keep translations natural and idiomatic
   - Maintain consistent terminology across the app
   - Consider character length differences (Chinese is typically more compact)
   - Preserve formatting placeholders like `%@` or `%d`

4. **When removing unused localized strings:**
   - ✅ Remove the key from `LocalizationHelper.swift` (delete the `static let` property)
   - ✅ Remove the entire entry from `.xcstrings` file (including ALL language variants)
   - ✅ Search the codebase to ensure the key is not used anywhere
   - ❌ NEVER leave orphaned keys in `.xcstrings` files
   - ❌ NEVER leave unused properties in `LocalizationHelper.swift`

   **Example cleanup process:**
   ```swift
   // 1. Remove from LocalizationHelper.swift
   // DELETE THIS:
   static let shortcutsActionLockKeyboard = LocalizationKey("shortcuts.action.lock.keyboard")

   // 2. Remove from Localizable.xcstrings
   // DELETE THIS ENTIRE BLOCK:
   // "shortcuts.action.lock.keyboard" : {
   //   "extractionState" : "manual",
   //   "localizations" : { ... }
   // }

   // 3. Search to verify it's not used
   // Run: grep -r "shortcutsActionLockKeyboard" KeyboardLocker/
   // Run: grep -r "shortcuts.action.lock.keyboard" KeyboardLocker/
   ```

   **Why this matters:** Unused localization keys bloat the app, create confusion, and make maintenance harder. Keep the codebase clean by removing strings when features are removed or refactored.

### Common Localization Mistakes to Avoid

- ❌ Hardcoding English strings directly in SwiftUI views
- ❌ Using `String(localized:)` without adding to `.xcstrings`
- ❌ Adding new features without localizing all text
- ❌ Forgetting to localize notification messages
- ❌ Leaving one language incomplete during development

## Permissions

**Accessibility Permission** - Required for CGEvent tap to function. Requested on first launch or first lock attempt. Both app and CLI need this permission.

**Automation Permission** - Required when using AppleScript or URL schemes from external automation tools. Requested when first invoked.

## Requirements

- macOS 13.0+
- Xcode 15.0+ with Command Line Tools
- Apple Development certificate (for signed Release builds via `make build`)
