import Client
import Foundation

@MainActor
protocol AgentControlServing {
  func lock() async throws
  func unlock() async throws
  func requestAccessibilityPermission() async throws
  func resetConnection()
}

@MainActor
protocol AgentReadinessServing {
  func serviceDescriptor() async throws -> ServiceDescriptor
  func status() async throws -> Bool
  func hasAccessibilityPermission() async throws -> Bool
  func resetConnection()
}

@MainActor
protocol AgentReplacementServing {
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

/// Complete live Client surface retained by `AppCoordinator`.
///
/// Coordinators depend on the narrower protocols above, so future fakes only implement the
/// external capability under test instead of the entire App Client.
@MainActor
protocol AgentClientServing:
  AgentControlServing,
  AgentReadinessServing,
  AgentReplacementServing {}

@MainActor
struct LiveAgentClient: AgentClientServing {
  func serviceDescriptor() async throws -> ServiceDescriptor {
    try await XPCClient.shared.serviceDescriptor()
  }

  func lock() async throws {
    try await XPCClient.shared.lock()
  }

  func unlock() async throws {
    try await XPCClient.shared.unlock()
  }

  func status() async throws -> Bool {
    try await XPCClient.shared.status()
  }

  func prepareForReplacement(
    unlockIfNeeded: Bool,
    expectedAgentInstanceID: UUID
  ) async throws -> ServiceReplacementTicket {
    try await XPCClient.shared.prepareForReplacement(
      unlockIfNeeded: unlockIfNeeded,
      expectedAgentInstanceID: expectedAgentInstanceID
    )
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
protocol AgentReadinessLifecycleServing {
  func ensureEnabled() -> AgentRegistrar.State
  func compatibility(
    of descriptor: ServiceDescriptor
  ) -> AgentRegistrar.Compatibility
}

@MainActor
protocol AgentReplacementLifecycleServing {
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
