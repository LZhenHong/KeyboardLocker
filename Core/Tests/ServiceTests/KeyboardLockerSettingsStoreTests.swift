import Common
import Foundation
@testable import Service
import Testing

@Suite(.serialized)
final class KeyboardLockerSettingsStoreTests {
  private let suiteName: String
  private let defaults: UserDefaults

  init() {
    suiteName = "KeyboardLockerSettingsStoreTests.\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suiteName)!
  }

  private func withCleanDefaults(_ body: () throws -> Void) rethrows {
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }
    try body()
  }

  @Test
  func freshStoreRegistersAndLoadsDefaults() {
    withCleanDefaults {
      _ = KeyboardLockerSettingsStore(userDefaults: defaults, storageKey: "settings")
      #expect(defaults.data(forKey: "settings") != nil)

      let store = KeyboardLockerSettingsStore(userDefaults: defaults, storageKey: "settings")
      #expect(store.load() == .default)
    }
  }

  @Test
  func loadReturnsPersistedSettings() throws {
    try withCleanDefaults {
      let custom = KeyboardLockerSettings(
        autoUnlockPolicy: .timed(seconds: 120),
        unlockHotkey: KeyboardLockerSettings.Hotkey(
          keyCode: 4,
          modifierFlags: [.maskControl, .maskAlternate]
        )
      )
      defaults.set(try JSONEncoder().encode(custom), forKey: "settings")

      let store = KeyboardLockerSettingsStore(userDefaults: defaults, storageKey: "settings")
      #expect(store.load() == custom)
    }
  }

  @Test
  func corruptPayloadFallsBackToDefaults() {
    withCleanDefaults {
      defaults.set(Data([0xFF, 0xFE, 0x00]), forKey: "settings")

      let store = KeyboardLockerSettingsStore(userDefaults: defaults, storageKey: "settings")
      #expect(store.load() == .default)
    }
  }

  @Test
  func registrationDoesNotOverwriteExistingPayload() throws {
    try withCleanDefaults {
      let custom = KeyboardLockerSettings(
        autoUnlockPolicy: .disabled,
        unlockHotkey: KeyboardLockerSettings.Hotkey(keyCode: 4, modifierFlags: .maskShift)
      )
      defaults.set(try JSONEncoder().encode(custom), forKey: "settings")

      _ = KeyboardLockerSettingsStore(userDefaults: defaults, storageKey: "settings")
      let persisted = try #require(defaults.data(forKey: "settings"))
      #expect(try JSONDecoder().decode(KeyboardLockerSettings.self, from: persisted) == custom)
    }
  }
}
