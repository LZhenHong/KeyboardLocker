@testable import Common
import CoreGraphics
import Foundation
import Testing

struct KeyboardLockerSettingsValidationTests {
  /// 'L' is used by the shipped default, so it is known to be mappable on any ASCII-capable layout.
  private static let mappableKeyCode = CGKeyCode(SharedConstants.defaultUnlockKeyCode)

  private static func settings(
    keyCode: CGKeyCode = mappableKeyCode,
    modifiers: CGEventFlags = [.maskControl, .maskCommand],
    policy: KeyboardLockerSettings.AutoUnlockPolicy = .timed(seconds: 60),
    phrase: String? = nil
  ) -> KeyboardLockerSettings {
    KeyboardLockerSettings(
      autoUnlockPolicy: policy,
      unlockHotkey: KeyboardLockerSettings.Hotkey(
        keyCode: keyCode,
        modifierFlags: modifiers
      ),
      unlockPhrase: phrase
    )
  }

  // MARK: - Hotkey guardrails

  @Test
  func defaultSettingsAreValid() throws {
    let validated = try KeyboardLockerSettings.default.validated()

    #expect(validated == .default)
  }

  @Test
  func hotkeyWithoutModifiersIsRejected() {
    let candidate = Self.settings(modifiers: [])

    #expect(throws: KeyboardLockerSettingsValidationError.hotkeyMissingModifier) {
      try candidate.validated()
    }
  }

  @Test
  func capsLockAloneDoesNotCountAsAModifier() {
    // CapsLock is stripped by `matches(keyCode:flags:)`, so accepting it would store a hotkey
    // the event tap could never match.
    let candidate = Self.settings(modifiers: [.maskAlphaShift])

    #expect(throws: KeyboardLockerSettingsValidationError.hotkeyMissingModifier) {
      try candidate.validated()
    }
  }

  @Test(arguments: [
    CGEventFlags.maskCommand,
    .maskControl,
    .maskAlternate,
    .maskShift,
  ])
  func eachRelevantModifierAloneIsAccepted(modifier: CGEventFlags) throws {
    let validated = try Self.settings(modifiers: modifier).validated()

    #expect(validated.unlockHotkey.modifierFlags == modifier)
  }

  @Test
  func unmappableKeyCodeIsRejected() {
    // 0xFF is not a key on any physical layout, so UCKeyTranslate cannot produce a glyph.
    let candidate = Self.settings(keyCode: 0xFF)

    #expect(throws: KeyboardLockerSettingsValidationError.hotkeyUnmappable) {
      try candidate.validated()
    }
  }

  // MARK: - Auto-unlock guardrails

  @Test
  func disabledAutoUnlockIsAccepted() throws {
    // Allowed on purpose: the UI marks it as not recommended and confirms it, but a long
    // unattended lock is a legitimate use.
    let validated = try Self.settings(policy: .disabled).validated()

    #expect(validated.autoUnlockPolicy == .disabled)
  }

  @Test(arguments: [5.0, 60.0, 3600.0])
  func inRangeTimeoutsAreAccepted(seconds: TimeInterval) throws {
    let validated = try Self.settings(policy: .timed(seconds: seconds)).validated()

    #expect(validated.autoUnlockPolicy == .timed(seconds: seconds))
  }

  @Test(arguments: [4.0, 0.0, -1.0, 3601.0, 86400.0])
  func outOfRangeTimeoutsAreRejected(seconds: TimeInterval) {
    #expect(
      throws: KeyboardLockerSettingsValidationError.autoUnlockOutOfRange(
        KeyboardLockerSettings.allowedAutoUnlockRange
      )
    ) {
      try Self.settings(policy: .timed(seconds: seconds)).validated()
    }
  }

  @Test(arguments: [Double.nan, .infinity, -.infinity])
  func nonFiniteTimeoutsAreRejected(seconds: TimeInterval) {
    #expect(throws: KeyboardLockerSettingsValidationError.autoUnlockNotFinite) {
      try Self.settings(policy: .timed(seconds: seconds)).validated()
    }
  }

  @Test
  func fractionalTimeoutIsRoundedToWholeSeconds() throws {
    let validated = try Self.settings(policy: .timed(seconds: 59.6)).validated()

    #expect(validated.autoUnlockPolicy == .timed(seconds: 60))
  }

  @Test
  func aTimeoutJustBelowTheLowerBoundRoundsIntoRange() throws {
    // 4.7 rounds to 5, which is in range. Checking the bound after rounding avoids rejecting a
    // value for a sub-second difference the UI cannot express.
    let validated = try Self.settings(policy: .timed(seconds: 4.7)).validated()

    #expect(validated.autoUnlockPolicy == .timed(seconds: 5))
  }

  @Test
  func validationIsIdempotent() throws {
    let once = try Self.settings(policy: .timed(seconds: 59.6)).validated()
    let twice = try once.validated()

    #expect(once == twice)
  }

  // MARK: - Unlock phrase guardrails

  @Test
  func nilPhraseDisablesTheGesture() throws {
    #expect(try Self.settings().validated().unlockPhrase == nil)
  }

  @Test
  func phraseIsLowercasedAndPreserved() throws {
    let validated = try Self.settings(phrase: "Unlock Me 2").validated()

    #expect(validated.unlockPhrase == "unlock me 2")
  }

  @Test(arguments: ["cat", "unlock me", String(repeating: "a", count: 64)])
  func phrasesInsideTheLengthRangeAreAccepted(phrase: String) throws {
    #expect(try Self.settings(phrase: phrase).validated().unlockPhrase == phrase)
  }

  @Test(arguments: ["", "ab", "  ", String(repeating: "a", count: 65)])
  func phrasesOutsideTheLengthRangeAreRejected(phrase: String) {
    #expect(
      throws: KeyboardLockerSettingsValidationError.unlockPhraseInvalidLength(
        KeyboardLockerSettings.allowedUnlockPhraseLength
      )
    ) {
      try Self.settings(phrase: phrase).validated()
    }
  }

  @Test(arguments: ["unlock!", "café", "open\tsesame", "pass/word"])
  func phrasesWithDisallowedCharactersAreRejected(phrase: String) {
    #expect(throws: KeyboardLockerSettingsValidationError.unlockPhraseInvalidCharacters) {
      try Self.settings(phrase: phrase).validated()
    }
  }

  @Test
  func spaceOnlyPhraseIsRejected() {
    // Inside the length range and the character set, but a held spacebar must not be a gesture.
    #expect(throws: KeyboardLockerSettingsValidationError.unlockPhraseInvalidCharacters) {
      try Self.settings(phrase: "   ").validated()
    }
  }
}
