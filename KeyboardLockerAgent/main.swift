import Foundation
import Service

/// Singleton service instance shared across all XPC connections
/// Ensures consistent state and avoids per-connection instance issues
private let sharedService = AgentService()

/// Accepts incoming XPC connections and configures them using the factory
private final class ServiceDelegate: NSObject, NSXPCListenerDelegate {
  func listener(
    _: NSXPCListener,
    shouldAcceptNewConnection newConnection: NSXPCConnection
  ) -> Bool {
    // The listener's code-signing requirement is evaluated before this delegate is called.
    XPCServerConnection.configure(newConnection, exportedService: sharedService)
    return true
  }
}

@MainActor
private func startAgent() {
  let listener = NSXPCListener(machServiceName: SharedConstants.machServiceName)
  do {
    try listener.setConnectionCodeSigningRequirement(
      XPCAccessControl.authorizedClientRequirement()
    )
  } catch {
    fatalError("KeyboardLockerAgent could not configure XPC peer authentication: \(error)")
  }

  let delegate = ServiceDelegate()
  listener.delegate = delegate
  listener.activate()

  print("KeyboardLockerAgent started, listening on \(SharedConstants.machServiceName)")
  RunLoop.main.run()
}

MainActor.assumeIsolated {
  startAgent()
}
