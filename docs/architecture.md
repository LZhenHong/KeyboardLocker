# Core Architecture Contract

**This is the foundational rule of the project. Every feature — the App, `klock`, Shortcuts, AppleScript, Widgets, and anything added later — MUST follow it. When a change conflicts with this contract, the contract wins; revise the change, not the contract.**

## Single Core Principle

The **Agent is the one and only place that executes real work.** All other surfaces (App, CLI, Shortcuts, AppleScript, Widgets, extensions) are **thin wrappers** whose sole job is:

1. Translate a user intent into an XPC call to the Agent, and
2. Observe global state via notifications.

A wrapper never owns behavior or state. If two wrappers appear to need the same logic, that logic belongs in the core, not copied into each wrapper.

```
App ─────┐
CLI ─────┤
Shortcut ┼── XPC ──▶ Agent  ◀── the ONLY executor
AppleScript┤            ├─ LockEngine        (event tap, lock lifecycle)
Widget ──┘            ├─ Settings ownership (source of truth)
                       └─ Accessibility      (permission gate)
```

## What Belongs Where

| Concern | Home | Rule |
|---------|------|------|
| Lock/unlock execution (CGEventTap) | **Agent** (`Service/LockEngine`) | Never runs anywhere else. No wrapper touches CGEventTap. |
| Settings (source of truth) | **Agent** | The Agent loads/owns settings and applies them. Wrappers read/write settings only through XPC, never by holding their own `UserDefaults`. |
| Accessibility permission | **Agent** | The Agent holds the permission and answers status/requests over XPC. |
| State broadcast | **Agent** (`LockStateBroadcaster`) | Only the core emits state. Wrappers subscribe, never emit. |
| UI / intent translation | **Wrappers** | Wrappers may hold view state, but no domain logic. |

## Global Lock Semantics

There is one physical keyboard, so lock state is a **single global boolean owned by the Agent**. There is no per-client or per-session ownership of the lock.

- Any wrapper may lock; any wrapper may unlock. A lock started by the CLI is unlockable by the App, and vice versa.
- Lock operations are **stateless one-off XPC calls** (`lock` / `unlock` / `status`), symmetric with each other. Do not model the lock as a "session" a client "owns" — a wrapper's connection lifetime is unrelated to the lock's lifetime.
- To react to state changes, subscribe to the global broadcast (`LockStateSubscriber`). Never infer state from "did my call succeed".

## State Synchronization

Because state lives in exactly one place (the Agent), wrappers stay in sync by always deferring to it. There are two wrapper shapes, and they read state differently:

- **One-shot surfaces** — CLI `status`/`unlock`, AppleScript, Shortcuts (App Intents), any script. They ask the Agent at the moment they run (`XPCClient.status()`) and act on the answer. They hold no cached state, so they are **synchronized by construction** and need no subscription. Do not add notification handling to a one-shot surface.
- **Long-lived, state-reflecting surfaces** — the App menu bar, future Widgets. They display state continuously, so they must both **subscribe** (`LockStateSubscriber`) and **reconcile on becoming visible / on launch** (fetch `status()`), because a broadcast can be missed while the process is suspended.

`LockStateSubscriber` treats notifications as *hints*, not truth: on any signal (Darwin or Distributed) it fetches the authoritative state from the Agent and de-duplicates. The Agent broadcasts on both channels only so a suspended App can be woken (Darwin) and a running one updated promptly (Distributed). A notification payload is never the source of truth.

## Rules for Adding a New Wrapper (Widget, Shortcut, AppleScript, …)

Before writing a wrapper, confirm all of the following:

1. **Imports `Client`, never `Service`.** Wrappers talk to the core through the XPC client only. Importing `Service` (LockEngine, event tap) into a wrapper is a contract violation.
2. **Adds no new domain logic.** If the wrapper needs behavior the core doesn't expose, add it to the Agent + `KeyboardLockerServiceProtocol` first, then call it. Do not implement it wrapper-side.
3. **Holds no independent state.** No private `UserDefaults`, no local lock flag. Read settings and lock state from the core.
4. **Emits nothing to other processes.** Only the Agent broadcasts state.
5. **Degrades honestly when the Agent is unavailable.** Every wrapper must handle "core not reachable" (see the Agent lifecycle requirement below) rather than assuming success.
6. **Reads state the way its shape dictates.** Decide which of the two shapes in "State Synchronization" the wrapper is: a one-shot surface calls `status()` directly and adds **no** notification handling; a long-lived UI subscribes via `LockStateSubscriber` *and* reconciles on becoming visible.

## Agent Lifecycle Requirement

Wrappers depend on the Agent being reachable even when the App is not running. The Agent MUST be registered with the system (`SMAppService`) so `launchd` can launch it on demand for any XPC client. A wrapper that assumes the Agent is already running (e.g. because the App happens to be open) is incorrect.

## Contract Violations to Watch For

These are the concrete failure modes this contract exists to prevent:

- A wrapper holding its own `KeyboardLockerSettingsStore` / `UserDefaults` → settings drift from the core (the Agent would act on stale or default settings).
- A "session" abstraction implying a client owns the lock → confusing behavior where one surface can't unlock what another locked.
- Duplicated lock/settings logic across App and CLI → the exact maintenance explosion the DRY rule forbids.
- A wrapper importing `Service` to "just call the engine directly" → bypasses the single core.
- A one-shot surface (CLI/AppleScript/Shortcuts) subscribing to broadcasts, or caching lock state between invocations → needless complexity and a new drift source; it should just call `status()` when it runs.
- Trusting a notification payload as the state instead of fetching `status()` → stale/reordered/dropped notifications silently desync the UI.
