import AppKit
import Client
import CoreGraphics
import Testing

struct HotkeyCaptureTests {
  private static let mappableKeyCode = UInt16(SharedConstants.defaultUnlockKeyCode)

  // MARK: - Modifier translation

  @Test
  func translatesTheFourMatchableModifiers() {
    let flags = HotkeyCapture.eventFlags(
      from: [.command, .control, .option, .shift]
    )

    #expect(flags == [.maskCommand, .maskControl, .maskAlternate, .maskShift])
  }

  /// CapsLock, Fn, and the numeric-pad flag are dropped by the event tap's matcher, so storing them
  /// would record a hotkey that never matches.
  @Test
  func dropsModifiersTheMatcherIgnores() {
    let flags = HotkeyCapture.eventFlags(
      from: [.capsLock, .function, .numericPad, .control]
    )

    #expect(flags == [.maskControl])
  }

  // MARK: - Acceptance

  @Test
  func acceptsAModifiedMappableKey() {
    let outcome = HotkeyCapture.outcome(
      keyCode: Self.mappableKeyCode,
      modifierFlags: [.control, .command]
    )

    let hotkey = outcome.hotkey
    #expect(hotkey?.keyCode == CGKeyCode(Self.mappableKeyCode))
    #expect(hotkey?.modifierFlags == [.maskControl, .maskCommand])
  }

  @Test
  func rejectsAnUnmodifiedKey() {
    let outcome = HotkeyCapture.outcome(
      keyCode: Self.mappableKeyCode,
      modifierFlags: []
    )

    #expect(outcome == .rejected(.hotkeyMissingModifier))
  }

  @Test
  func rejectsAKeyModifiedOnlyByCapsLock() {
    let outcome = HotkeyCapture.outcome(
      keyCode: Self.mappableKeyCode,
      modifierFlags: [.capsLock]
    )

    #expect(outcome == .rejected(.hotkeyMissingModifier))
  }

  @Test
  func rejectsAnUnmappableKeyCode() {
    let outcome = HotkeyCapture.outcome(
      keyCode: 0xFF,
      modifierFlags: [.command]
    )

    #expect(outcome == .rejected(.hotkeyUnmappable))
  }

  /// Every accepted capture must survive the Agent's own validation, or the picker would offer
  /// combinations the write path then rejects.
  @Test(arguments: [
    NSEvent.ModifierFlags.command,
    .control,
    .option,
    .shift,
    [.command, .shift],
  ])
  func acceptedCapturesPassAgentValidation(
    modifiers: NSEvent.ModifierFlags
  ) throws {
    let hotkey = try #require(
      HotkeyCapture.outcome(
        keyCode: Self.mappableKeyCode,
        modifierFlags: modifiers
      ).hotkey
    )

    let settings = KeyboardLockerSettings(
      autoUnlockPolicy: .timed(seconds: 60),
      unlockHotkey: hotkey
    )
    #expect(try settings.validated().unlockHotkey == hotkey)
  }

  // MARK: - Terminators

  /// Escape and Return must leave the recorder rather than be recorded, so the keyboard alone is
  /// always enough to exit it.
  @Test(arguments: [UInt16(53), 36, 76])
  func escapeAndReturnEndRecording(keyCode: UInt16) {
    #expect(HotkeyCapture.isRecordingTerminator(keyCode: keyCode))
  }

  @Test
  func anOrdinaryKeyDoesNotEndRecording() {
    #expect(!HotkeyCapture.isRecordingTerminator(keyCode: Self.mappableKeyCode))
  }
}
