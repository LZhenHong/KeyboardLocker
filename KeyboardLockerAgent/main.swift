import Foundation
import Service

/// Accepts incoming XPC connections and configures them using the factory
private final class ServiceDelegate: NSObject, NSXPCListenerDelegate {
  private let sharedService: AgentService

  init(sharedService: AgentService) {
    self.sharedService = sharedService
  }

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
  // One process-wide service owns the authoritative settings, replacement transaction, and
  // LockEngine. Every accepted connection receives only a proxy to this same instance.
  let sharedService = AgentService()
  // Install the notification category and clear any stale locked notification before the
  // listener can accept a lock request.
  LockStatusNotifier.shared.start()
  let listener = NSXPCListener(machServiceName: SharedConstants.machServiceName)
  do {
    try listener.setConnectionCodeSigningRequirement(
      XPCAccessControl.authorizedClientRequirement()
    )
  } catch {
    fatalError("KeyboardLockerAgent could not configure XPC peer authentication: \(error)")
  }

  let delegate = ServiceDelegate(sharedService: sharedService)
  listener.delegate = delegate
  listener.activate()

  print("KeyboardLockerAgent started, listening on \(SharedConstants.machServiceName)")
  // `NSXPCListener.delegate` is weak. Retain both objects explicitly for the lifetime of the
  // process instead of relying on optimizer-dependent local-variable lifetime extension.
  withExtendedLifetime((listener, delegate)) {
    RunLoop.main.run()
  }
}

MainActor.assumeIsolated {
  startAgent()
}
