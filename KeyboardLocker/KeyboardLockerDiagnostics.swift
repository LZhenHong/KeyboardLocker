import Client
import Foundation

@MainActor
struct KeyboardLockerDiagnosticsCollector {
  struct AppIdentity: Equatable {
    let build: String
    let bundleIdentifier: String
    let version: String
  }

  typealias AccessibilityQuery = @MainActor @Sendable () async throws -> Bool
  typealias DescriptorQuery = @MainActor @Sendable () async throws -> ServiceDescriptor
  typealias LockSnapshotQuery = @MainActor @Sendable () async throws -> LockStatusSnapshot

  private let accessibilityQuery: AccessibilityQuery
  private let appIdentity: AppIdentity
  private let descriptorQuery: DescriptorQuery
  private let lockSnapshotQuery: LockSnapshotQuery
  private let now: @MainActor @Sendable () -> Date
  private let operatingSystemVersion: String
  private let registrationStatus: @MainActor @Sendable () -> String

  static var live: Self {
    let bundle = Bundle.main
    return Self(
      appIdentity: AppIdentity(
        build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
        bundleIdentifier: bundle.bundleIdentifier ?? "unknown",
        version: bundle.object(
          forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "unknown"
      ),
      operatingSystemVersion: ProcessInfo.processInfo.operatingSystemVersionString,
      registrationStatus: {
        AgentRegistrar.registrationStatusDescription
      },
      descriptor: {
        try await XPCClient.shared.serviceDescriptor()
      },
      accessibility: {
        try await XPCClient.shared.hasAccessibilityPermission()
      },
      lockSnapshot: {
        try await XPCClient.shared.lockStatusSnapshot()
      },
      now: Date.init
    )
  }

  init(
    appIdentity: AppIdentity,
    operatingSystemVersion: String,
    registrationStatus: @escaping @MainActor @Sendable () -> String,
    descriptor: @escaping DescriptorQuery,
    accessibility: @escaping AccessibilityQuery,
    lockSnapshot: @escaping LockSnapshotQuery,
    now: @escaping @MainActor @Sendable () -> Date
  ) {
    self.appIdentity = appIdentity
    self.operatingSystemVersion = operatingSystemVersion
    self.registrationStatus = registrationStatus
    descriptorQuery = descriptor
    accessibilityQuery = accessibility
    lockSnapshotQuery = lockSnapshot
    self.now = now
  }

  func report(appSnapshot: AppCoordinator.Snapshot) async -> String {
    let descriptor = await capture(descriptorQuery)
    let accessibility = await capture(accessibilityQuery)
    let lockSnapshot = await capture(lockSnapshotQuery)

    var lines = [
      "KeyboardLocker Diagnostics",
      "Generated: \(format(now()))",
      "App: \(appIdentity.version) (\(appIdentity.build))",
      "App Identifier: \(appIdentity.bundleIdentifier)",
      "macOS: \(operatingSystemVersion)",
      "Agent Registration: \(registrationStatus())",
      "App State: \(appSnapshot.state.diagnosticDescription)",
      "App Activity: \(appSnapshot.activity?.diagnosticDescription ?? "none")",
      "Safety Check: \(appSnapshot.safetyCheckState.diagnosticDescription)",
      "Last Error: \(redact(appSnapshot.lastError) ?? "none")",
      "",
      "Agent",
    ]

    switch descriptor {
    case let .success(value):
      lines.append(contentsOf: [
        "Status: available",
        "Identifier: \(value.agentBundleIdentifier)",
        "Version: \(value.agentVersion) (\(value.agentBuild))",
        "Protocol: \(value.protocolVersion.major).\(value.protocolVersion.minor)",
        "Instance: \(value.agentInstanceID.uuidString)",
        "Replacement: \(value.replacementPhase.rawValue)",
        "Capabilities: \(value.capabilities.map(\.rawValue).sorted().joined(separator: ", "))",
      ])

    case let .failure(error):
      lines.append("Status: unavailable (\(redact(error.localizedDescription) ?? "unknown error"))")
    }

    switch accessibility {
    case let .success(isGranted):
      lines.append("Accessibility: \(isGranted ? "granted" : "not-granted")")
    case let .failure(error):
      lines.append("Accessibility: unavailable (\(redact(error.localizedDescription) ?? "unknown error"))")
    }

    lines.append(contentsOf: ["", "Lock"])
    switch lockSnapshot {
    case let .success(value):
      lines.append(contentsOf: [
        "Status: \(value.isLocked ? "locked" : "unlocked")",
        "Started: \(value.startedAt.map(format) ?? "none")",
        "Auto Unlock: \(value.autoUnlockTargetDate.map(format) ?? "none")",
        "Policy: \(value.settings.autoUnlockPolicy.diagnosticDescription)",
        "Unlock Hotkey: \(value.settings.unlockHotkey.displayString)",
      ])

    case let .failure(error):
      lines.append("Status: unavailable (\(redact(error.localizedDescription) ?? "unknown error"))")
    }

    return lines.joined(separator: "\n")
  }

  private func capture<Value>(
    _ operation: @MainActor @Sendable () async throws -> Value
  ) async -> Result<Value, Error> {
    do {
      return try await .success(operation())
    } catch {
      return .failure(error)
    }
  }

  private func format(_ date: Date) -> String {
    ISO8601DateFormatter().string(from: date)
  }

  /// Keeps reports useful while excluding path-like fragments that may carry a user name.
  private func redact(_ text: String?) -> String? {
    guard let text else {
      return nil
    }

    let redacted = text.replacingOccurrences(
      of: #"(?:file://|~/|/)[^\s]+"#,
      with: "<redacted-path>",
      options: .regularExpression
    )
    let collapsed = redacted
      .split(whereSeparator: \.isWhitespace)
      .map(String.init)
      .joined(separator: " ")
    return collapsed.isEmpty ? nil : collapsed
  }
}

private extension AppCoordinator.State {
  var diagnosticDescription: String {
    switch self {
    case let .checking(lastKnownLock):
      "checking (last-known: \(lastKnownLock.map(String.init) ?? "unknown"))"
    case .agentApprovalRequired:
      "agent-approval-required"
    case .agentReplacementInProgress:
      "agent-replacement-in-progress"
    case let .agentUpdateRequired(isLocked, _):
      "agent-update-required (locked: \(isLocked.map(String.init) ?? "unknown"))"
    case let .accessibilityRequired(isLocked):
      "accessibility-required (locked: \(isLocked))"
    case let .ready(isLocked):
      "ready (locked: \(isLocked))"
    case let .unavailable(_, canRestartAgent):
      "unavailable (restart-available: \(canRestartAgent))"
    }
  }
}

private extension AppCoordinator.Activity {
  var diagnosticDescription: String {
    switch self {
    case .locking:
      "locking"
    case .requestingAccessibility:
      "requesting-accessibility"
    case .restartingAgent:
      "restarting-agent"
    case .startingSafetyCheck:
      "starting-safety-check"
    case .unlocking:
      "unlocking"
    case .updatingAgent:
      "updating-agent"
    }
  }
}

private extension AppCoordinator.SafetyCheckState {
  var diagnosticDescription: String {
    switch self {
    case .completed:
      "completed"
    case .failed:
      "failed"
    case .idle:
      "idle"
    case .running:
      "running"
    }
  }
}

private extension KeyboardLockerSettings.AutoUnlockPolicy {
  var diagnosticDescription: String {
    switch self {
    case .disabled:
      "disabled"
    case let .timed(seconds):
      "timed (\(seconds.formatted()) seconds)"
    }
  }
}
