import Foundation
import os

/// Persists `KeyboardLockerSettings` to `UserDefaults`
final class KeyboardLockerSettingsStore {
  private static let logger = Logger(
    subsystem: SharedConstants.machServiceName,
    category: "SettingsStore"
  )

  private let userDefaults: UserDefaults
  private let storageKey: String
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  init(
    userDefaults: UserDefaults = .standard,
    storageKey: String = "keyboardlocker.settings"
  ) {
    self.userDefaults = userDefaults
    self.storageKey = storageKey
    registerDefaultsIfNeeded()
  }

  /// Loads settings from storage, returning default settings when none exist.
  ///
  /// A present-but-undecodable payload means the stored bytes no longer match the schema.
  /// The Agent stays functional by falling back to defaults, but the corruption is always
  /// logged instead of being silently swallowed.
  func load() -> KeyboardLockerSettings {
    guard let data = userDefaults.data(forKey: storageKey) else {
      return .default
    }
    do {
      return try decoder.decode(KeyboardLockerSettings.self, from: data)
    } catch {
      Self.logger.error(
        "Stored settings are undecodable; falling back to defaults: \(error.localizedDescription)"
      )
      return .default
    }
  }

  private func registerDefaultsIfNeeded() {
    guard userDefaults.object(forKey: storageKey) == nil else {
      return
    }
    do {
      let data = try encoder.encode(KeyboardLockerSettings.default)
      userDefaults.set(data, forKey: storageKey)
    } catch {
      Self.logger.error("Could not encode default settings: \(error.localizedDescription)")
    }
  }
}
