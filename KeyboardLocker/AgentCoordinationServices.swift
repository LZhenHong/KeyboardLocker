import Client
import Foundation
import SystemSurfaces

@MainActor
protocol AgentControlServing: Sendable {
  func beginSafetyCheck() async throws -> LockRequestOutcome
  func lock() async throws
  func unlock() async throws
  func waitUntilUnlocked() async throws
  func requestAccessibilityPermission() async throws
  func resetConnection()
}

/// One-shot lock capabilities used by system automation wrappers.
@MainActor
protocol AgentLockActionServing: Sendable {
  func lock() async throws
  func unlock() async throws
  func status() async throws -> Bool
  /// Atomically flips the global lock in the Agent and returns the resulting state.
  func toggle() async throws -> Bool
}

/// The one-off timed lock used by the popover's quick-lock actions. Kept narrow so the
/// automation fakes above never have to stub a capability they cannot trigger.
@MainActor
protocol AgentTimedLockServing: Sendable {
  /// Creates a lock with a one-off auto-unlock override; the persisted settings never change.
  func beginTimedLock(seconds: TimeInterval) async throws -> LockRequestOutcome
}

@MainActor
protocol AgentReadinessServing: Sendable {
  func serviceDescriptor() async throws -> ServiceDescriptor
  func status() async throws -> Bool
  func hasAccessibilityPermission() async throws -> Bool
  func resetConnection()
}

@MainActor
protocol AgentReplacementServing: Sendable {
  func serviceDescriptor() async throws -> ServiceDescriptor
  func unlock() async throws
  func status() async throws -> Bool
  func prepareForReplacement(
    unlockIfNeeded: Bool,
    expectedAgentInstanceID: UUID
  ) async throws -> ServiceReplacementTicket
  func cancelReplacementPreparation(
    ticket: ServiceReplacementTicket
  ) async throws
  func commitReplacement(
    ticket: ServiceReplacementTicket
  ) async throws
  func resetConnection()
}

/// Settings reads and writes, plus the authoritative lock snapshot the UI presents.
///
/// `currentSettings()` and `lockStatusSnapshot().settings` deliberately answer different
/// questions: the former is the persisted configuration the next lock will use — what the settings
/// UI edits — while the latter is what a running lock is actually enforcing. They differ while the
/// keyboard is locked, because a write does not disturb an active lock.
@MainActor
protocol AgentSettingsServing: Sendable {
  func currentSettings() async throws -> KeyboardLockerSettings
  func applySettings(
    _ settings: KeyboardLockerSettings
  ) async throws -> KeyboardLockerSettings
  func lockStatusSnapshot() async throws -> LockStatusSnapshot
  /// The Agent's bounded history of completed lock generations, for the statistics page.
  func lockHistory() async throws -> LockHistory
}

@MainActor
protocol AgentLockStateObserving: Sendable {
  func subscribe(
    initialState: Bool?,
    _ handler: @escaping (Bool) -> Void
  ) -> ObserverToken
}

/// Complete live Client surface retained by `AppCoordinator`.
///
/// Coordinators depend on the narrower protocols above, so future fakes only implement the
/// external capability under test instead of the entire App Client.
@MainActor
protocol AgentClientServing:
  AgentControlServing,
  AgentLockActionServing,
  AgentReadinessServing,
  AgentReplacementServing,
  AgentSettingsServing,
  AgentTimedLockServing {}

@MainActor
struct LiveAgentClient: AgentClientServing {
  typealias Mutation = @Sendable () async throws -> Void
  typealias SafetyCheckMutation = @Sendable () async throws -> LockRequestOutcome
  typealias StatusQuery = @Sendable () async throws -> Bool
  typealias TimedLockMutation = @Sendable (TimeInterval) async throws -> LockRequestOutcome
  typealias ToggleMutation = @Sendable () async throws -> Bool

  private let beginSafetyCheckMutation: SafetyCheckMutation
  private let lockMutation: Mutation
  private let statusQuery: StatusQuery
  private let surfaceInvalidator: LockStateSurfaceInvalidator
  private let timedLockMutation: TimedLockMutation
  private let toggleMutation: ToggleMutation
  private let unlockMutation: Mutation
  private let waitUntilUnlockedOperation: Mutation

  nonisolated init() {
    self.init(
      lock: {
        try await XPCClient.shared.lock()
      },
      unlock: {
        try await XPCClient.shared.unlock()
      },
      status: {
        try await XPCClient.shared.status()
      },
      toggle: {
        try await XPCClient.shared.toggle()
      },
      beginSafetyCheck: {
        try await XPCClient.shared.beginSafetyCheck()
      },
      waitUntilUnlocked: {
        try await XPCClient.shared.waitUntilUnlocked()
      },
      surfaceInvalidator: .live
    )
  }

  nonisolated init(
    lock: @escaping Mutation,
    unlock: @escaping Mutation,
    status: @escaping StatusQuery,
    toggle: @escaping ToggleMutation,
    beginSafetyCheck: @escaping SafetyCheckMutation = {
      try await XPCClient.shared.beginSafetyCheck()
    },
    beginTimedLock: @escaping TimedLockMutation = { seconds in
      try await XPCClient.shared.beginTimedLock(seconds: seconds, interactively: false)
    },
    waitUntilUnlocked: @escaping Mutation = {
      try await XPCClient.shared.waitUntilUnlocked()
    },
    surfaceInvalidator: LockStateSurfaceInvalidator
  ) {
    beginSafetyCheckMutation = beginSafetyCheck
    lockMutation = lock
    unlockMutation = unlock
    statusQuery = status
    timedLockMutation = beginTimedLock
    toggleMutation = toggle
    waitUntilUnlockedOperation = waitUntilUnlocked
    self.surfaceInvalidator = surfaceInvalidator
  }

  func serviceDescriptor() async throws -> ServiceDescriptor {
    try await XPCClient.shared.serviceDescriptor()
  }

  func lock() async throws {
    try await lockMutation()
    surfaceInvalidator.invalidate()
  }

  func beginSafetyCheck() async throws -> LockRequestOutcome {
    let outcome = try await beginSafetyCheckMutation()
    if outcome == .acquired {
      surfaceInvalidator.invalidate()
    }
    return outcome
  }

  func beginTimedLock(seconds: TimeInterval) async throws -> LockRequestOutcome {
    let outcome = try await timedLockMutation(seconds)
    if outcome == .acquired {
      surfaceInvalidator.invalidate()
    }
    return outcome
  }

  func unlock() async throws {
    try await unlockMutation()
    surfaceInvalidator.invalidate()
  }

  func status() async throws -> Bool {
    try await statusQuery()
  }

  func toggle() async throws -> Bool {
    let isLocked = try await toggleMutation()
    surfaceInvalidator.invalidate()
    return isLocked
  }

  func waitUntilUnlocked() async throws {
    try await waitUntilUnlockedOperation()
  }

  func prepareForReplacement(
    unlockIfNeeded: Bool,
    expectedAgentInstanceID: UUID
  ) async throws -> ServiceReplacementTicket {
    let ticket = try await XPCClient.shared.prepareForReplacement(
      unlockIfNeeded: unlockIfNeeded,
      expectedAgentInstanceID: expectedAgentInstanceID
    )
    if unlockIfNeeded {
      surfaceInvalidator.invalidate()
    }
    return ticket
  }

  func cancelReplacementPreparation(
    ticket: ServiceReplacementTicket
  ) async throws {
    try await XPCClient.shared.cancelReplacementPreparation(ticket: ticket)
  }

  func commitReplacement(
    ticket: ServiceReplacementTicket
  ) async throws {
    try await XPCClient.shared.commitReplacement(ticket: ticket)
  }

  func hasAccessibilityPermission() async throws -> Bool {
    try await XPCClient.shared.hasAccessibilityPermission()
  }

  func currentSettings() async throws -> KeyboardLockerSettings {
    try await XPCClient.shared.currentSettings()
  }

  func applySettings(
    _ settings: KeyboardLockerSettings
  ) async throws -> KeyboardLockerSettings {
    let stored = try await XPCClient.shared.applySettings(settings)
    // The widget and control render the unlock hotkey, so a stored configuration change has to
    // reach the system-managed surfaces the same way a lock state change does.
    surfaceInvalidator.invalidate()
    return stored
  }

  func lockStatusSnapshot() async throws -> LockStatusSnapshot {
    try await XPCClient.shared.lockStatusSnapshot()
  }

  func lockHistory() async throws -> LockHistory {
    try await XPCClient.shared.lockHistory()
  }

  func requestAccessibilityPermission() async throws {
    try await XPCClient.shared.requestAccessibilityPermission()
  }

  func resetConnection() {
    XPCClient.shared.resetConnection()
  }
}

@MainActor
struct LiveAgentLockStateObserver: AgentLockStateObserving {
  private let observer: any AgentLockStateObserving
  private let surfaceInvalidator: LockStateSurfaceInvalidator

  init() {
    self.init(
      observer: LockStateSubscriberObserver(),
      surfaceInvalidator: .live
    )
  }

  init(
    observer: any AgentLockStateObserving,
    surfaceInvalidator: LockStateSurfaceInvalidator
  ) {
    self.observer = observer
    self.surfaceInvalidator = surfaceInvalidator
  }

  func subscribe(
    initialState: Bool?,
    _ handler: @escaping (Bool) -> Void
  ) -> ObserverToken {
    // A fresh App observation lifetime calibrates the system-owned surfaces even when the
    // authoritative Boolean matches the App's seed and the subscriber emits no callback.
    surfaceInvalidator.invalidate()
    return observer.subscribe(initialState: initialState) { isLocked in
      // The underlying subscriber already coalesces signals and re-queries the Agent. This is a
      // presentation refresh hint only; the Boolean forwarded to the coordinator remains the
      // authoritative state.
      surfaceInvalidator.invalidate()
      handler(isLocked)
    }
  }
}

@MainActor
private struct LockStateSubscriberObserver: AgentLockStateObserving {
  func subscribe(
    initialState: Bool?,
    _ handler: @escaping (Bool) -> Void
  ) -> ObserverToken {
    LockStateSubscriber.subscribe(initialState: initialState, handler)
  }
}

@MainActor
protocol AgentReadinessLifecycleServing: Sendable {
  func ensureEnabled() -> AgentRegistrar.State
  func compatibility(
    of descriptor: ServiceDescriptor
  ) -> AgentRegistrar.Compatibility
}

@MainActor
protocol AgentReplacementLifecycleServing: Sendable {
  func restart() async -> AgentRegistrar.State
}

/// Complete lifecycle surface retained by `AppCoordinator`.
@MainActor
protocol AgentLifecycleServing:
  AgentReadinessLifecycleServing,
  AgentReplacementLifecycleServing {}

@MainActor
struct LiveAgentLifecycle: AgentLifecycleServing {
  func ensureEnabled() -> AgentRegistrar.State {
    AgentRegistrar.ensureEnabled()
  }

  func compatibility(
    of descriptor: ServiceDescriptor
  ) -> AgentRegistrar.Compatibility {
    AgentRegistrar.compatibility(of: descriptor)
  }

  func restart() async -> AgentRegistrar.State {
    await AgentRegistrar.restart()
  }
}
