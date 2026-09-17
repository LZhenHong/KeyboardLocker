import Client
import CoreGraphics
import Foundation
import Testing

@Suite(.serialized)
struct SystemShortcutConflictsTests {
  /// ⌘Space — Spotlight's shipped combination (keyCode 49 = space, 0x100000 = command).
  private let spotlightHotkey = KeyboardLockerSettings.Hotkey(
    keyCode: 49,
    modifierFlags: [.maskCommand]
  )

  @Test
  func enabledShortcutWithSameCombinationConflictsWithItsKnownName() {
    let conflicts = SystemShortcutConflicts.conflicts(with: spotlightHotkey) {
      [
        "64": entry(enabled: true, keyCode: 49, modifiers: 0x100000),
      ]
    }

    #expect(conflicts == [
      SystemShortcutConflict(name: "Show Spotlight search", isCurrentlyEnabled: true),
    ])
  }

  @Test
  func disabledShortcutStillConflictsMarkedAsCurrentlyOff() {
    // A disabled shortcut cannot fire today, but it is still assigned — the warning exists
    // for the moment the user turns it back on.
    let conflicts = SystemShortcutConflicts.conflicts(with: spotlightHotkey) {
      [
        "64": entry(enabled: false, keyCode: 49, modifiers: 0x100000),
      ]
    }

    #expect(conflicts == [
      SystemShortcutConflict(name: "Show Spotlight search", isCurrentlyEnabled: false),
    ])
  }

  @Test
  func enabledConflictsSortBeforeDisabledOnes() {
    let conflicts = SystemShortcutConflicts.conflicts(with: spotlightHotkey) {
      [
        "60": entry(enabled: false, keyCode: 49, modifiers: 0x100000),
        "64": entry(enabled: true, keyCode: 49, modifiers: 0x100000),
      ]
    }

    #expect(conflicts.map(\.isCurrentlyEnabled) == [true, false])
  }

  @Test
  func sameKeyWithDifferentModifiersDoesNotConflict() {
    // ⌃Space, not ⌘Space.
    let conflicts = SystemShortcutConflicts.conflicts(with: spotlightHotkey) {
      [
        "60": entry(enabled: true, keyCode: 49, modifiers: 0x40000),
      ]
    }

    #expect(conflicts.isEmpty)
  }

  @Test
  func sameModifiersWithDifferentKeyDoesNotConflict() {
    // ⌘A, not ⌘Space.
    let conflicts = SystemShortcutConflicts.conflicts(with: spotlightHotkey) {
      [
        "64": entry(enabled: true, keyCode: 0, modifiers: 0x100000),
      ]
    }

    #expect(conflicts.isEmpty)
  }

  @Test
  func irrelevantModifierBitsAreNormalizedBeforeMatching() {
    // CapsLock (0x10000) mixed into the stored mask must not hide the conflict.
    let conflicts = SystemShortcutConflicts.conflicts(with: spotlightHotkey) {
      [
        "64": entry(enabled: true, keyCode: 49, modifiers: 0x100000 | 0x10000),
      ]
    }

    #expect(conflicts.count == 1)
  }

  @Test
  func unknownIdentifierFallsBackToNoName() {
    let conflicts = SystemShortcutConflicts.conflicts(with: spotlightHotkey) {
      [
        "999": entry(enabled: true, keyCode: 49, modifiers: 0x100000),
      ]
    }

    #expect(conflicts == [SystemShortcutConflict(name: nil, isCurrentlyEnabled: true)])
  }

  @Test
  func entryWithoutAssignedKeyIsIgnored() {
    let conflicts = SystemShortcutConflicts.conflicts(with: spotlightHotkey) {
      [
        "64": entry(enabled: true, keyCode: Int(UInt16.max), modifiers: 0x100000),
      ]
    }

    #expect(conflicts.isEmpty)
  }

  @Test
  func malformedEntriesAreSkipped() {
    let conflicts = SystemShortcutConflicts.conflicts(with: spotlightHotkey) {
      [
        "64": ["enabled": true],
        "65": ["value": ["parameters": ["garbage"]], "enabled": true],
        "66": "not-even-a-dict",
      ]
    }

    #expect(conflicts.isEmpty)
  }

  @Test
  func missingPreferencesProduceNoConflicts() {
    let conflicts = SystemShortcutConflicts.conflicts(with: spotlightHotkey) {
      nil
    }

    #expect(conflicts.isEmpty)
  }

  private func entry(enabled: Bool, keyCode: Int, modifiers: UInt64) -> [String: Any] {
    [
      "enabled": enabled,
      "value": [
        "parameters": [32, keyCode, modifiers],
        "type": "standard",
      ],
    ]
  }
}
