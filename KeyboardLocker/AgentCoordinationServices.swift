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
  AgentReplacementServing {}

@MainActor
struct LiveAgentClient: AgentClientServing {
  typealias Mutation = @Sendable () async throws -> Void
  typealias SafetyCheckMutation = @Sendable () async throws -> LockRequestOutcome
  typealias StatusQuery = @Sendable () async throws -> Bool
  typealias ToggleMutation = @Sendable () async throws -> Bool

  private let beginSafetyCheckMutation: SafetyCheckMutation
  private let lockMutation: Mutation
  private let statusQuery: StatusQuery
  private let surfaceInvalidator: LockStateSurfaceInvalidator
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
    waitUntilUnlocked: @escaping Mutation = {
      try await XPCClient.shared.waitUntilUnlocked()
    },
    surfaceInvalidator: LockStateSurfaceInvalidator
  ) {
    beginSafetyCheckMutation = beginSafetyCheck
    lockMutation = lock
    unlockMutation = unlock
    statusQuery = status
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
