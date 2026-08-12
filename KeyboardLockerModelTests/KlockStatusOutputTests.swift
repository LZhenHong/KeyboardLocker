import Client
import Foundation
import Testing

@Suite(.serialized)
struct KlockStatusOutputTests {
  @Test
  func humanReadableOutputPreservesExistingContract() {
    #expect(KlockStatusOutput.humanReadable.render(isLocked: true) == "Locked")
    #expect(KlockStatusOutput.humanReadable.render(isLocked: false) == "Unlocked")
  }

  @Test
  func jSONOutputUsesStableBooleanField() throws {
    let locked = KlockStatusOutput.json.render(isLocked: true)
    let unlocked = KlockStatusOutput.json.render(isLocked: false)

    #expect(locked == #"{"locked":true}"#)
    #expect(unlocked == #"{"locked":false}"#)
    #expect(try decodedLockedValue(from: locked) == true)
    #expect(try decodedLockedValue(from: unlocked) == false)
  }

  @Test
  func snapshotOutputRendersLockedSnapshotWithFixedKeyOrder() {
    let output = KlockStatusOutput.render(
      snapshot: makeSnapshot(
        isLocked: true,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        autoUnlockTargetDate: Date(timeIntervalSince1970: 1_700_000_060)
      )
    )

    #expect(
      output ==
        """
        {"autoUnlockTargetDate":"2023-11-14T22:14:20Z","locked":true,"startedAt":"2023-11-14T22:13:20Z","unlockHotkey":"⌃⌘L"}
        """
    )
  }

  @Test
  func snapshotOutputRendersUnlockedSnapshotWithNullDates() {
    let output = KlockStatusOutput.render(
      snapshot: makeSnapshot(isLocked: false, startedAt: nil, autoUnlockTargetDate: nil)
    )

    #expect(
      output ==
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
