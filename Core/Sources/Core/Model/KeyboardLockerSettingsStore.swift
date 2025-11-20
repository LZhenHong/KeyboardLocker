import Foundation

/// Persists `KeyboardLockerSettings` to `UserDefaults`
public final class KeyboardLockerSettingsStore {
  private let userDefaults: UserDefaults
  private let storageKey: String
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  public init(
    userDefaults: UserDefaults = .standard,
    storageKey: String = "keyboardlocker.settings"
  ) {
    self.userDefaults = userDefaults
    self.storageKey = storageKey
    registerDefaultsIfNeeded()
  }

  /// Loads settings from storage, returns default settings if none exist
  public func load() -> KeyboardLockerSettings {
    guard let data = userDefaults.data(forKey: storageKey),
          let settings = try? decoder.decode(KeyboardLockerSettings.self, from: data)
    else {
      return .default
    }
    return settings
  }

  /// Saves settings to storage, throws error if encoding fails
  public func save(_ settings: KeyboardLockerSettings) throws {
    let data = try encoder.encode(settings)
    userDefaults.set(data, forKey: storageKey)
  }

  private func registerDefaultsIfNeeded() {
    guard userDefaults.object(forKey: storageKey) == nil else {
      return
    }
    if let data = try? encoder.encode(KeyboardLockerSettings.default) {
      userDefaults.set(data, forKey: storageKey)
    }
  }
}
