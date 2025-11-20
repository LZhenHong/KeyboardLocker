import Core
import Foundation

/// Handles keyboard lock/unlock operations.
final class AgentService: NSObject, KeyboardLockerServiceProtocol {
  override nonisolated init() {
    super.init()
  }

  private func executeOnMainThread(_ operation: @escaping () -> Void) {
    DispatchQueue.main.async {
      operation()
    }
  }

  func lockKeyboard(reply: @escaping (Error?) -> Void) {
    executeOnMainThread {
      do {
        try LockEngine.shared.lock()
        reply(nil)
      } catch {
        reply(error)
      }
    }
  }

  func unlockKeyboard(reply: @escaping (Error?) -> Void) {
    executeOnMainThread {
      LockEngine.shared.unlock()
      reply(nil)
    }
  }

  func status(reply: @escaping (Bool, Error?) -> Void) {
    executeOnMainThread {
      reply(LockEngine.shared.isLocked, nil)
    }
  }
}
