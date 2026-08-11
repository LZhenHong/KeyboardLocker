import Client
import Foundation

/// One generation-consistent replacement decision produced by readiness evaluation.
struct AgentUpdatePlan: Equatable {
  enum Mode: Equatable {
    case forced(descriptor: ServiceDescriptor?, isLocked: Bool?)
    case safe(descriptor: ServiceDescriptor, isLocked: Bool)
  }

  let mode: Mode
  let message: String

  var descriptor: ServiceDescriptor? {
    switch mode {
    case let .forced(descriptor, _):
      descriptor
    case let .safe(descriptor, _):
      descriptor
    }
  }

  var isLocked: Bool? {
    switch mode {
    case let .forced(_, isLocked):
      isLocked
    case let .safe(_, isLocked):
      isLocked
    }
  }

  var supportsSafeReplacement: Bool {
    if case .safe = mode {
      return true
    }
    return false
  }

  var canReadLockState: Bool {
    isLocked != nil
  }

  func updatingLockState(_ isLocked: Bool) -> Self {
    switch mode {
    case let .forced(descriptor, currentLockState):
      guard currentLockState != nil else {
        return self
      }
      return Self(
        mode: .forced(descriptor: descriptor, isLocked: isLocked),
        message: message
      )

    case let .safe(descriptor, _):
      return Self(
        mode: .safe(descriptor: descriptor, isLocked: isLocked),
        message: message
      )
    }
  }
}

/// Owns the App-side ordering for replacing a launchd-managed Agent.
///
/// The coordinator contains no presentation state. It guarantees that Service Management restart
/// is attempted only after a safe replacement transaction has committed. Passing a forced plan is
/// a caller precondition that represents the user's explicit authorization of the legacy fallback.
@MainActor
struct AgentReplacementCoordinator {
  enum Outcome {
    case failed(error: Error, currentLockState: Bool?)
    case registration(AgentRegistrar.State)
    case replacementInProgress(ServiceDescriptor)
    case restarted(previousAgentInstanceID: UUID?)
  }

  private let client: any AgentReplacementServing
  private let lifecycle: any AgentReplacementLifecycleServing

  init(
    client: any AgentReplacementServing,
    lifecycle: any AgentReplacementLifecycleServing
  ) {
    self.client = client
    self.lifecycle = lifecycle
  }

  func replace(_ plan: AgentUpdatePlan) async -> Outcome {
    switch plan.mode {
    case let .safe(descriptor, isLocked):
      return await replaceWithTransaction(descriptor: descriptor, isLocked: isLocked)
    case let .forced(descriptor, isLocked):
      return await replaceForced(descriptor: descriptor, isLocked: isLocked)
    }
  }

  private func replaceWithTransaction(
    descriptor: ServiceDescriptor,
    isLocked: Bool
  ) async -> Outcome {
    var replacementTicket: ServiceReplacementTicket?
    var didCommitReplacement = false

    do {
      replacementTicket = try await client.prepareForReplacement(
        unlockIfNeeded: isLocked,
        expectedAgentInstanceID: descriptor.agentInstanceID
      )
      if let replacementTicket {
        try await client.commitReplacement(ticket: replacementTicket)
        didCommitReplacement = true
      }
    } catch {
      if let replacementTicket, !didCommitReplacement {
        try? await client.cancelReplacementPreparation(
          ticket: replacementTicket
        )
      }

      if let descriptor = await reportedReplacementInProgress() {
        return .replacementInProgress(descriptor)
      }

      return .failed(error: error, currentLockState: try? await client.status())
    }

    return await restart(
      reporting: descriptor,
      cancellingUncommittedTicket: replacementTicket,
      didCommit: didCommitReplacement
    )
  }

  /// The forced path has no transaction to roll back and no trusted replacement to re-detect.
  /// A plan without a readable lock state performs no throwing call at all, so it can never
  /// produce `.failed`.
  private func replaceForced(
    descriptor: ServiceDescriptor?,
    isLocked: Bool?
  ) async -> Outcome {
    if isLocked != nil {
      // The legacy path has no cross-client drain. The explicit user action authorizes
      // releasing the known lock immediately before the shortest possible restart window.
      do {
        try await client.unlock()
      } catch {
        return .failed(error: error, currentLockState: try? await client.status())
      }
    }

    return await restart(
      reporting: descriptor,
      cancellingUncommittedTicket: nil,
      didCommit: false
    )
  }

  private func restart(
    reporting descriptor: ServiceDescriptor?,
    cancellingUncommittedTicket replacementTicket: ServiceReplacementTicket?,
    didCommit didCommitReplacement: Bool
  ) async -> Outcome {
    let registrationState = await lifecycle.restart()
    guard case .enabled = registrationState else {
      if let replacementTicket, !didCommitReplacement {
        try? await client.cancelReplacementPreparation(
          ticket: replacementTicket
        )
      }
      client.resetConnection()
      return .registration(registrationState)
    }

    client.resetConnection()
    return .restarted(previousAgentInstanceID: descriptor?.agentInstanceID)
  }

  private func reportedReplacementInProgress() async -> ServiceDescriptor? {
    guard let descriptor = try? await client.serviceDescriptor(),
          descriptor.replacementPending,
          descriptor.agentBundleIdentifier == SharedConstants.agentBundleIdentifier,
          descriptor.protocolVersion.major == ServiceContract.protocolVersion.major,
          descriptor.capabilities.contains(.prepareForReplacement),
          descriptor.capabilities.contains(.committedReplacementDrain)
    else {
      return nil
    }
    return descriptor
  }
}
