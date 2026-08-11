import Common
import Service
import XCTest

final class KeyboardLockerSettingsStoreTests: XCTestCase {
  private var suiteName: String!
  private var defaults: UserDefaults!

  override func setUp() {
    super.setUp()
    suiteName = "KeyboardLockerSettingsStoreTests.\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suiteName)
  }

  override func tearDown() {
    defaults.removePersistentDomain(forName: suiteName)
    defaults = nil
    suiteName = nil
    super.tearDown()
  }

  func testFreshStoreRegistersAndLoadsDefaults() {
    _ = KeyboardLockerSettingsStore(userDefaults: defaults, storageKey: "settings")
    XCTAssertNotNil(defaults.data(forKey: "settings"))

    let store = KeyboardLockerSettingsStore(userDefaults: defaults, storageKey: "settings")
    XCTAssertEqual(store.load(), .default)
  }

  func testLoadReturnsPersistedSettings() throws {
    let custom = KeyboardLockerSettings(
      autoUnlockPolicy: .timed(seconds: 120),
      unlockHotkey: KeyboardLockerSettings.Hotkey(
        keyCode: 4,
        modifierFlags: [.maskControl, .maskAlternate]
      )
    )
    defaults.set(try JSONEncoder().encode(custom), forKey: "settings")

    let store = KeyboardLockerSettingsStore(userDefaults: defaults, storageKey: "settings")
    XCTAssertEqual(store.load(), custom)
  }

  func testCorruptPayloadFallsBackToDefaults() {
    defaults.set(Data([0xFF, 0xFE, 0x00]), forKey: "settings")

    let store = KeyboardLockerSettingsStore(userDefaults: defaults, storageKey: "settings")
    XCTAssertEqual(store.load(), .default)
  }

  func testRegistrationDoesNotOverwriteExistingPayload() throws {
    let custom = KeyboardLockerSettings(
      autoUnlockPolicy: .disabled,
      unlockHotkey: KeyboardLockerSettings.Hotkey(keyCode: 4, modifierFlags: .maskShift)
    )
    defaults.set(try JSONEncoder().encode(custom), forKey: "settings")

    _ = KeyboardLockerSettingsStore(userDefaults: defaults, storageKey: "settings")
    let persisted = try XCTUnwrap(defaults.data(forKey: "settings"))
    XCTAssertEqual(try JSONDecoder().decode(KeyboardLockerSettings.self, from: persisted), custom)
  }
}
