# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Project Overview

KeyboardLocker suppresses standard keyboard events via CGEventTap on macOS. Mouse input and system-defined media keys remain available. Three-tier architecture over XPC (Mach service `io.lzhlovesjyq.keyboardlocker.agent`):

- **KeyboardLocker** (menu-bar App, Agent lifecycle coordinator, and one-shot system actions) — imports `Client`
- **KeyboardLockerAgent** (XPC service, runs the lock engine, holds Accessibility permission) — imports `Service`
- **klock** (CLI) — imports `Client`
- **KeyboardLockerWidgets** (WidgetKit extension hosting Widget and macOS Control) — imports `Client`
- **Core** (Swift Package): `Common` (shared protocol/settings), `Client` (XPC client, wrappers), `Service` (lock engine, Agent). `Client`/`Service` both `@_exported import Common`.

Bundle IDs: app `io.lzhlovesjyq.keyboardlocker`, agent `…​.agent`, CLI `…​.klock`, WidgetKit extension `…​.widgets`.

## Architecture Contract — read first

**Before adding or changing any feature (App, CLI, Shortcuts, AppleScript, Widgets, …), read [docs/architecture.md](docs/architecture.md).** It defines the non-negotiable contract: the Agent is the single executor, all other surfaces are thin wrappers, the lock is one global state. When a change conflicts with it, the contract wins.

For the process/module boundary and complete XPC call flow, see [docs/xpc.md](docs/xpc.md). For task workflows and component details, see [docs/development.md](docs/development.md). For Shortcuts, AppleScript, CLI, Widget, and Control usage, see [docs/automation.md](docs/automation.md).

## Project-Specific Rules

These override the model's defaults — the rest of Swift style is left to standard idioms.

- **UI copy is English-first.** No hardcoded non-English strings; localization comes before release. Follow macOS HIG.
- **DRY is a hard constraint.** Lock/settings logic lives in the core, never copied into a wrapper. If two surfaces seem to need the same logic, it belongs in the Agent + protocol. See the contract's "contract violations".
- **Minimal public surface.** Default to the most restrictive access level; every `public` in `Core` is a maintenance commitment. Singletons use `private init()`; read-only shared state uses `public private(set)`.
- Comments in English, explain *why* not *what*.

## Build & Format

```bash
xcodebuild -scheme KeyboardLocker -configuration Debug build   # or KeyboardLockerAgent / klock / Core
swift test --package-path Core
swiftformat .   # 2-space indent, alpha-sorted imports; run before committing
```

`.swift-version` intentionally selects the active Xcode toolchain. `Core/Package.swift`
and SwiftFormat keep Swift 5.10 source semantics.
