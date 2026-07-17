import Client
import Foundation

/// Resolves Service Management, XPC contract, replacement, lock, and Accessibility facts.
///
/// This type returns domain outcomes so presentation code can remain outside the business layer.
@MainActor
struct AgentReadinessCoordinator {
  enum Outcome {
    case agentDidNotRestart
    case cancelled
    case failure(Error, context: String?)
    case invalidBundle(AgentRegistrar.Failure)
    case ready(isLocked: Bool, hasAccessibilityPermission: Bool)
    case registration(AgentRegistrar.State)
    case replacementInProgress(ServiceDescriptor)
    case updateAvailable(
      descriptor: ServiceDescriptor,
      message: String,
      bundledBuild: String,
      isLocked: Bool
    )
    case updateRequired(AgentUpdatePlan)
  }

  private let client: any AgentReadinessServing
  private let lifecycle: any AgentReadinessLifecycleServing

  init(
    client: any AgentReadinessServing,
    lifecycle: any AgentReadinessLifecycleServing
  ) {
    self.client = client
    self.lifecycle = lifecycle
  }

  func inspect(
    expectedPreviousAgentInstanceID: UUID? = nil
  ) async -> Outcome {
    let registrationState = lifecycle.ensureEnabled()
    guard !Task.isCancelled else {
      return .cancelled
    }
    guard case .enabled = registrationState else {
      return .registration(registrationState)
    }

    let descriptor: ServiceDescriptor
    do {
      descriptor = try await client.serviceDescriptor()
    } catch let initialHandshakeError {
      guard !Task.isCancelled else {
        return .cancelled
      }

      client.resetConnection()
      do {
        descriptor = try await client.serviceDescriptor()
      } catch let retryHandshakeError {
        return await inspectUnverifiedAgent(
          initialError: initialHandshakeError,
          retryError: retryHandshakeError
        )
      }
    }

    guard !Task.isCancelled else {
      return .cancelled
    }
    if let expectedPreviousAgentInstanceID,
       descriptor.agentInstanceID == expectedPreviousAgentInstanceID
    {
      return .agentDidNotRestart
    }

    let compatibility = lifecycle.compatibility(of: descriptor)
    if isTrustedReplacementInProgress(
      descriptor: descriptor,
      compatibility: compatibility
    ) {
      return .replacementInProgress(descriptor)
    }

    switch compatibility {
    case let .bundledAgentUpgradeAvailable(message, bundledBuild):
      do {
        let isLocked = try await client.status()
        guard !Task.isCancelled else {
          return .cancelled
        }
        return .updateAvailable(
          descriptor: descriptor,
          message: message,
          bundledBuild: bundledBuild,
          isLocked: isLocked
        )
      } catch {
        return .failure(error, context: nil)
      }

    case .compatible:
      do {
        async let lockState = client.status()
        async let permissionState = client.hasAccessibilityPermission()
        let (isLocked, hasAccessibilityPermission) = try await (
          lockState,
          permissionState
        )
        guard !Task.isCancelled else {
          return .cancelled
        }
        return .ready(
          isLocked: isLocked,
          hasAccessibilityPermission: hasAccessibilityPermission
        )
      } catch {
        return .failure(error, context: nil)
      }

    case let .invalidBundle(failure):
      return .invalidBundle(failure)

    case let .updateRequired(message, canReadLockState, supportsSafeReplacement):
      guard canReadLockState else {
        guard !supportsSafeReplacement else {
          return .failure(
            AgentReadinessError.safeReplacementRequiresReadableLockState,
            context: nil
          )
        }
        return .updateRequired(AgentUpdatePlan(
          mode: .forced(descriptor: descriptor, isLocked: nil),
          message: message
        ))
      }

      do {
        let isLocked = try await client.status()
        guard !Task.isCancelled else {
          return .cancelled
        }
        let mode: AgentUpdatePlan.Mode = supportsSafeReplacement
          ? .safe(descriptor: descriptor, isLocked: isLocked)
          : .forced(descriptor: descriptor, isLocked: isLocked)
        return .updateRequired(AgentUpdatePlan(
          mode: mode,
          message: message
        ))
      } catch {
        return .failure(error, context: nil)
      }
    }
  }

  private func inspectUnverifiedAgent(
    initialError: Error,
    retryError: Error
  ) async -> Outcome {
    client.resetConnection()

    do {
      let isLocked = try await client.status()
      guard !Task.isCancelled else {
        return .cancelled
      }
      return .updateRequired(AgentUpdatePlan(
        mode: .forced(descriptor: nil, isLocked: isLocked),
        message: """
        The running background agent's XPC contract could not be verified after reconnecting. \
        It may use an earlier contract, or its descriptor handshake may be failing. Replacing \
        this unverified Agent cannot block another client from locking during the transition, \
        so a new lock created in that brief window may be released.
        """
      ))
    } catch {
      return .failure(
        error,
        context: """
        Descriptor handshake failed before and after reconnecting: \
        \(initialError.localizedDescription) \(retryError.localizedDescription)
        """
      )
    }
  }

  private func isTrustedReplacementInProgress(
    descriptor: ServiceDescriptor,
    compatibility: AgentRegistrar.Compatibility
  ) -> Bool {
    guard descriptor.replacementPending,
          descriptor.agentBundleIdentifier == SharedConstants.agentBundleIdentifier,
          descriptor.protocolVersion.major == ServiceContract.protocolVersion.major,
          descriptor.capabilities.contains(.prepareForReplacement),
          descriptor.capabilities.contains(.committedReplacementDrain)
    else {
      return false
    }

    if case .invalidBundle = compatibility {
      return false
    }
    return true
  }
}

private enum AgentReadinessError: Error, LocalizedError {
  case safeReplacementRequiresReadableLockState

  var errorDescription: String? {
    switch self {
    case .safeReplacementRequiresReadableLockState:
      "Safe Agent replacement requires a readable authoritative lock state."
    }
  }
}
