import Core
import Foundation

/// Handles keyboard lock/unlock operations.
final class AgentService: NSObject, KeyboardLockerServiceProtocol {
  override nonisolated init() {
    super.init()
  }

  func lockKeyboard(reply: @escaping (Error?) -> Void) {
    DispatchQueue.main.async {
      do {
        try LockEngine.shared.lock()
        reply(nil)
      } catch {
        reply(error)
      }
    }
  }

  func unlockKeyboard(reply: @escaping (Error?) -> Void) {
    DispatchQueue.main.async {
      LockEngine.shared.unlock()
      reply(nil)
    }
  }

  func status(reply: @escaping (Bool, Error?) -> Void) {
    DispatchQueue.main.async {
      reply(LockEngine.shared.isLocked, nil)
    }
  }
}

/// Accepts incoming XPC connections and exports the AgentService instance.
final class ServiceDelegate: NSObject, NSXPCListenerDelegate {
  nonisolated func listener(_: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
    newConnection.exportedInterface = NSXPCInterface(with: KeyboardLockerServiceProtocol.self)
    newConnection.exportedObject = AgentService()
    newConnection.resume()
    return true
  }
}
