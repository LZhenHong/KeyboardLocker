import Client
import Foundation
import XCTest

final class KlockStatusOutputTests: XCTestCase {
  func testHumanReadableOutputPreservesExistingContract() {
    XCTAssertEqual(KlockStatusOutput.humanReadable.render(isLocked: true), "Locked")
    XCTAssertEqual(KlockStatusOutput.humanReadable.render(isLocked: false), "Unlocked")
  }

  func testJSONOutputUsesStableBooleanField() throws {
    let locked = KlockStatusOutput.json.render(isLocked: true)
    let unlocked = KlockStatusOutput.json.render(isLocked: false)

    XCTAssertEqual(locked, #"{"locked":true}"#)
    XCTAssertEqual(unlocked, #"{"locked":false}"#)
    XCTAssertEqual(try decodedLockedValue(from: locked), true)
    XCTAssertEqual(try decodedLockedValue(from: unlocked), false)
  }

  func testSnapshotOutputRendersLockedSnapshotWithFixedKeyOrder() {
    let output = KlockStatusOutput.render(
      snapshot: makeSnapshot(
        isLocked: true,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        autoUnlockTargetDate: Date(timeIntervalSince1970: 1_700_000_060)
      )
    )

    XCTAssertEqual(
      output,
      """
      {"autoUnlockTargetDate":"2023-11-14T22:14:20Z","locked":true,"startedAt":"2023-11-14T22:13:20Z","unlockHotkey":"⌃⌘L"}
      """
    )
  }

  func testSnapshotOutputRendersUnlockedSnapshotWithNullDates() {
    let output = KlockStatusOutput.render(
      snapshot: makeSnapshot(isLocked: false, startedAt: nil, autoUnlockTargetDate: nil)
    )

    XCTAssertEqual(
      output,
      #"{"autoUnlockTargetDate":null,"locked":false,"startedAt":null,"unlockHotkey":"⌃⌘L"}"#
    )
  }

  private func makeSnapshot(
    isLocked: Bool,
    startedAt: Date?,
    autoUnlockTargetDate: Date?
  ) -> LockStatusSnapshot {
    LockStatusSnapshot(
      capturedAt: Date(timeIntervalSince1970: 1_700_000_030),
      isLocked: isLocked,
      startedAt: startedAt,
      autoUnlockTargetDate: autoUnlockTargetDate,
      settings: KeyboardLockerSettings(
        autoUnlockPolicy: .disabled,
        unlockHotkey: KeyboardLockerSettings.Hotkey(
          keyCode: 37,
          modifierFlags: [.maskCommand, .maskControl]
        )
      )
    )
  }

  private func decodedLockedValue(from output: String) throws -> Bool? {
    let object = try JSONSerialization.jsonObject(with: Data(output.utf8))
    return (object as? [String: Bool])?["locked"]
  }
}
