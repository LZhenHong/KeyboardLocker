import Core
import Foundation

/// Accepts incoming XPC connections and exports the AgentService instance
final class ServiceDelegate: NSObject, NSXPCListenerDelegate {
  nonisolated func listener(
    _: NSXPCListener,
    shouldAcceptNewConnection newConnection: NSXPCConnection
  ) -> Bool {
    newConnection.exportedInterface = NSXPCInterface(with: KeyboardLockerServiceProtocol.self)
    newConnection.exportedObject = AgentService()
    newConnection.resume()
    return true
  }
}

let listener = NSXPCListener(machServiceName: SharedConstants.machServiceName)
let delegate = ServiceDelegate()
listener.delegate = delegate
listener.resume()
print("KeyboardLockerAgent started, listening on \(SharedConstants.machServiceName)")
RunLoop.main.run()
