import Foundation
import os
import Service

/// XPC service implementation. Owns the settings source of truth and drives the single
/// global `LockEngine`. All wrappers reach the lock exclusively through this object.
final class AgentService: NSObject, KeyboardLockerServiceProtocol {
  private static let logger = Logger(subsystem: SharedConstants.machServiceName, category: "AgentService")

  private let store = KeyboardLockerSettingsStore()
  private let settingsLock = OSAllocatedUnfairLock()
  private var settings: KeyboardLockerSettings

  override init() {
    let loaded = store.load()
    settings = loaded
    super.init()
    // Seed the engine so a lock triggered before any settings write uses persisted values.
    LockEngine.shared.updateSettings(loaded)
  }

  // MARK: - Locking

  func lockKeyboard(reply: @escaping (Error?) -> Void) {
    let current = currentSettingsValue()
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

  func applySettings(_ data: Data, reply: @escaping (Error?) -> Void) {
    let newSettings = KeyboardLockerSettings.decodedFromXPC(data)

    settingsLock.lock()
    settings = newSettings
    settingsLock.unlock()

    do {
      try store.save(newSettings)
    } catch {
      // Persistence failure is non-fatal for the running lock; surface it but still apply.
      Self.logger.error("Failed to persist settings: \(error.localizedDescription, privacy: .public)")
    }

    executeOnMainThread {
      LockEngine.shared.updateSettings(newSettings)
      reply(nil)
    }
  }

  func currentSettings(reply: @escaping (Data?) -> Void) {
    reply(try? currentSettingsValue().encodedForXPC())
  }

  // MARK: - Accessibility

  func requestAccessibilityPermission(showPrompt: Bool, reply: @escaping (Bool) -> Void) {
    executeOnMainThread {
      reply(AccessibilityManager.requestPermission(showPrompt: showPrompt))
    }
  }

  func accessibilityStatus(reply: @escaping (Bool) -> Void) {
    executeOnMainThread {
      reply(AccessibilityManager.hasPermission())
    }
  }

  // MARK: - Helpers

  private func currentSettingsValue() -> KeyboardLockerSettings {
    settingsLock.lock()
    defer { settingsLock.unlock() }
    return settings
  }

  private func executeOnMainThread(_ operation: @escaping () -> Void) {
    if Thread.isMainThread {
      operation()
    } else {
      DispatchQueue.main.async(execute: operation)
    }
  }
}
