import Client
import Foundation
import os
import ServiceManagement

/// Registers the Agent as a launchd-managed login item so `launchd` can start it on demand
/// for any XPC client — even when this App is not running. This is the contract's
/// "Agent Lifecycle Requirement": wrappers must not assume the Agent is already up.
enum AgentRegistrar {
  enum State: Equatable {
    case enabled
    case approvalRequired
    case unavailable(Failure)
  }

  enum Failure: Error, Equatable {
    case invalidBundle(String)
    case notFound
    case registrationFailed(String)
    case restartFailed(String)

    var message: String {
      switch self {
      case let .invalidBundle(message):
        "The bundled KeyboardLocker agent is invalid. \(message)"
      case .notFound:
        "The bundled KeyboardLocker agent could not be found. Reinstall the complete application bundle."
      case let .registrationFailed(message):
        "The KeyboardLocker agent could not be registered. \(message)"
      case let .restartFailed(message):
        "The KeyboardLocker agent could not be restarted. \(message)"
      }
    }
  }

  enum Compatibility: Equatable {
    case bundledAgentUpgradeAvailable(message: String, bundledBuild: String)
    case compatible
    case invalidBundle(Failure)
    case updateRequired(
      message: String,
      canReadLockState: Bool,
      supportsSafeReplacement: Bool
    )
  }

  private static let logger = Logger(subsystem: SharedConstants.machServiceName, category: "AgentRegistrar")

  /// Filename of the launchd plist bundled at `Contents/Library/LaunchAgents/`.
  private static let plistName = "io.lzhlovesjyq.keyboardlocker.agent.plist"

  private static var agent: SMAppService {
    SMAppService.agent(plistName: plistName)
  }

  /// Ensures the Agent is registered and returns the user-visible lifecycle state.
  static func ensureEnabled() -> State {
    let service = agent
    switch service.status {
    case .enabled:
      return .enabled

    case .requiresApproval:
      return .approvalRequired

    case .notFound:
      return .unavailable(.notFound)

    case .notRegistered:
      do {
        try service.register()
        logger.info("Registered agent (status: \(String(describing: service.status), privacy: .public))")
      } catch {
        logger.error("Failed to register agent: \(error.localizedDescription, privacy: .public)")
        return stateAfterRegistration(service.status, error: error)
      }
      return stateAfterRegistration(service.status)

    @unknown default:
      return .unavailable(.registrationFailed("The system returned an unsupported registration status."))
    }
  }

  static func openApprovalSettings() {
    SMAppService.openSystemSettingsLoginItems()
  }

  /// Compares the running Agent's self-reported contract with the Agent bundled in this App.
  /// This is lifecycle compatibility only and must not be treated as peer authentication.
  static func compatibility(of descriptor: ServiceDescriptor) -> Compatibility {
    let requirements: ServiceCompatibilityRequirements
    do {
      requirements = try bundledCompatibilityRequirements()
    } catch let failure as Failure {
      return .invalidBundle(failure)
    } catch {
      return .invalidBundle(.invalidBundle(error.localizedDescription))
    }

    let issues = descriptor.compatibilityIssues(against: requirements)
    guard !issues.isEmpty else {
      return .compatible
    }

    let details = issues.compactMap(\.errorDescription).joined(separator: " ")
    let identifierMatches = descriptor.agentBundleIdentifier == requirements.agentBundleIdentifier
    let sameProtocolMajor = descriptor.protocolVersion.major == requirements.minimumProtocolVersion.major
    let canReadLockState = identifierMatches
      && sameProtocolMajor
      && descriptor.capabilities.contains(.lockControl)
    let supportsSafeReplacement = canReadLockState
      && descriptor.capabilities.contains(.prepareForReplacement)
      && descriptor.capabilities.contains(.committedReplacementDrain)

    switch compareBuilds(running: descriptor.agentBuild, bundled: requirements.agentBuild) {
    case .orderedAscending where supportsSafeReplacement:
      return .bundledAgentUpgradeAvailable(
        message: """
        The running background agent is older than the version bundled with this app. \(details)
        """,
        bundledBuild: requirements.agentBuild
      )

    case .orderedDescending:
      return .updateRequired(
        message: """
        A newer background agent is running than the version bundled with this app. \
        Replacing it will use the older bundled version. \(details)
        """,
        canReadLockState: canReadLockState,
        supportsSafeReplacement: supportsSafeReplacement
      )

    case .orderedAscending, .orderedSame, nil:
      return .updateRequired(
        message: """
        The running background agent does not match the version bundled with this app. \(details)
        """,
        canReadLockState: canReadLockState,
        supportsSafeReplacement: supportsSafeReplacement
      )
    }
  }

  private static func compareBuilds(
    running: String,
    bundled: String
  ) -> ComparisonResult? {
    guard let runningBuild = ServiceBuildVersion(running),
          let bundledBuild = ServiceBuildVersion(bundled)
    else {
      return nil
    }
    if runningBuild < bundledBuild {
      return .orderedAscending
    }
    if runningBuild > bundledBuild {
      return .orderedDescending
    }
    return .orderedSame
  }

  /// Stops the currently registered Agent and waits for it to exit before registering the
  /// bundled version. Callers must first enforce the lock-safety policy in
  /// `AgentReplacementCoordinator`.
  static func restart() async -> State {
    let service = agent

    switch service.status {
    case .notRegistered:
      return ensureEnabled()

    case .notFound:
      return .unavailable(.notFound)

    case .enabled, .requiresApproval:
      do {
        try await service.unregister()
      } catch {
        guard service.status == .notRegistered else {
          logger.error("Failed to restart agent: \(error.localizedDescription, privacy: .public)")
          return .unavailable(.restartFailed(error.localizedDescription))
        }
      }
      return ensureEnabled()

    @unknown default:
      return .unavailable(.restartFailed("The system returned an unsupported registration status."))
    }
  }

  private static func stateAfterRegistration(
    _ status: SMAppService.Status,
    error: Error? = nil
  ) -> State {
    switch status {
    case .enabled:
      .enabled
    case .requiresApproval:
      .approvalRequired
    case .notFound:
      .unavailable(.notFound)
    case .notRegistered:
      .unavailable(.registrationFailed(error?.localizedDescription ?? "Registration did not complete."))
    @unknown default:
      .unavailable(.registrationFailed(
        error?.localizedDescription ?? "The system returned an unsupported registration status."
      ))
    }
  }

  private static func bundledCompatibilityRequirements() throws -> ServiceCompatibilityRequirements {
    let agentURL = Bundle.main.bundleURL
      .appendingPathComponent("Contents", isDirectory: true)
      .appendingPathComponent("Library", isDirectory: true)
      .appendingPathComponent("LoginItems", isDirectory: true)
      .appendingPathComponent("KeyboardLockerAgent.app", isDirectory: true)

    guard FileManager.default.fileExists(atPath: agentURL.path),
          let bundle = Bundle(url: agentURL)
    else {
      throw Failure.notFound
    }
    guard let bundleIdentifier = bundle.bundleIdentifier, !bundleIdentifier.isEmpty else {
      throw Failure.invalidBundle("CFBundleIdentifier is missing.")
    }
    guard bundleIdentifier == SharedConstants.agentBundleIdentifier else {
      throw Failure.invalidBundle(
        "Expected identifier \(SharedConstants.agentBundleIdentifier), found \(bundleIdentifier)."
      )
    }
    guard let version = bundle.object(
      forInfoDictionaryKey: "CFBundleShortVersionString"
    ) as? String, !version.isEmpty else {
      throw Failure.invalidBundle("CFBundleShortVersionString is missing.")
    }
    guard let build = bundle.object(
      forInfoDictionaryKey: "CFBundleVersion"
    ) as? String, !build.isEmpty else {
      throw Failure.invalidBundle("CFBundleVersion is missing.")
    }

    return ServiceCompatibilityRequirements(
      agentBundleIdentifier: bundleIdentifier,
      agentVersion: version,
      agentBuild: build
    )
  }
}
