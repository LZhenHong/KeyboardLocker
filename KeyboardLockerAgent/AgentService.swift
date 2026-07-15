import Foundation
import os
import Service

/// XPC service implementation. Owns the settings source of truth and drives the single
/// global `LockEngine`. All wrappers reach the lock exclusively through this object.
final class AgentService: NSObject, KeyboardLockerServiceProtocol {
  private let settings: KeyboardLockerSettings

  override init() {
    let loaded = KeyboardLockerSettingsStore().load()
    settings = loaded
    super.init()
    // Seed the engine so a lock uses persisted values.
    LockEngine.shared.updateSettings(loaded)
  }

  // MARK: - Locking

  func lockKeyboard(reply: @escaping (Error?) -> Void) {
    let current = settings
    executeOnMainThread {
      do {
        try LockEngine.shared.lock(settings: current)
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

  // MARK: - Settings

  func currentSettings(reply: @escaping (Data?) -> Void) {
    reply(try? settings.encodedForXPC())
  }

  // MARK: - Helpers

  private func executeOnMainThread(_ operation: @escaping () -> Void) {
    if Thread.isMainThread {
      operation()
    } else {
      DispatchQueue.main.async(execute: operation)
    }
  }
}
