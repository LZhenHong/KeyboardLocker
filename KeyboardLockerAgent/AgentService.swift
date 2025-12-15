import Foundation
import Service

/// XPC service implementation for keyboard lock/unlock operations.
final class AgentService: NSObject, KeyboardLockerServiceProtocol {
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

  func accessibilityStatus(reply: @escaping (Bool) -> Void) {
    executeOnMainThread {
      reply(AccessibilityManager.hasPermission())
    }
  }

  private func executeOnMainThread(_ operation: @escaping () -> Void) {
    if Thread.isMainThread {
      operation()
    } else {
      DispatchQueue.main.async(execute: operation)
    }
  }
}
