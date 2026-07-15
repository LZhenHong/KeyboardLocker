import Client
import Foundation
import os
import ServiceManagement

/// Registers the Agent as a launchd-managed login item so `launchd` can start it on demand
/// for any XPC client — even when this App is not running. This is the contract's
/// "Agent Lifecycle Requirement": wrappers must not assume the Agent is already up.
enum AgentRegistrar {
  private static let logger = Logger(subsystem: SharedConstants.machServiceName, category: "AgentRegistrar")

  /// Filename of the launchd plist bundled at `Contents/Library/LaunchAgents/`.
  private static let plistName = "io.lzhlovesjyq.keyboardlocker.agent.plist"

  private static var agent: SMAppService {
    SMAppService.agent(plistName: plistName)
  }

  /// Ensures the Agent is registered. Idempotent; safe to call on every launch.
  static func registerIfNeeded() {
    let service = agent
    switch service.status {
    case .enabled:
      return
    default:
      do {
        try service.register()
        logger.info("Registered agent (status: \(String(describing: service.status), privacy: .public))")
      } catch {
        logger.error("Failed to register agent: \(error.localizedDescription, privacy: .public)")
      }
    }
  }
}
