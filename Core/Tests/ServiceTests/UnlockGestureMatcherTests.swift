import Common
import CoreGraphics
@testable import Service
import Testing

@Suite(.serialized)
struct UnlockGestureMatcherTests {
  private let configuredHotkey = KeyboardLockerSettings.Hotkey(
    keyCode: 37,
    modifierFlags: [.maskControl, .maskCommand]
  )

  @Test
  func configuredHotkeyAlwaysUnlocks() {
    #expect(
      matches(
        keyCode: configuredHotkey.keyCode,
        flags: configuredHotkey.modifierFlags,
        allowsControlCUnlock: false
      )
    )
  }

  @Test
  func controlCUnlocksInteractiveLock() {
    #expect(
      matches(
        keyCode: UnlockGestureMatcher.controlCKeyCode,
        flags: [.maskControl],
        allowsControlCUnlock: true
      )
    )
  }

  @Test
  func controlCDoesNotUnlockNonInteractiveLock() {
    #expect(
      !matches(
        keyCode: UnlockGestureMatcher.controlCKeyCode,
        flags: [.maskControl],
        allowsControlCUnlock: false
      )
    )
  }

  @Test
  func controlCRejectsAdditionalRelevantModifiers() {
    #expect(
      !matches(
        keyCode: UnlockGestureMatcher.controlCKeyCode,
        flags: [.maskControl, .maskCommand],
        allowsControlCUnlock: true
      )
    )
  }

  @Test
  func controlCIgnoresCapsLock() {
    #expect(
      matches(
        keyCode: UnlockGestureMatcher.controlCKeyCode,
        flags: [.maskControl, .maskAlphaShift],
        allowsControlCUnlock: true
      )
    )
  }

  @Test
  func autoRepeatAndKeyUpNeverUnlock() {
    #expect(
      !matches(
        keyCode: UnlockGestureMatcher.controlCKeyCode,
        flags: [.maskControl],
        allowsControlCUnlock: true,
        isAutoRepeat: true
      )
    )
    #expect(
      !matches(
        type: .keyUp,
        keyCode: UnlockGestureMatcher.controlCKeyCode,
        flags: [.maskControl],
        allowsControlCUnlock: true
      )
    )
  }

  private func matches(
    type: CGEventType = .keyDown,
    keyCode: CGKeyCode,
    flags: CGEventFlags,
    allowsControlCUnlock: Bool,
    isAutoRepeat: Bool = false
  ) -> Bool {
    UnlockGestureMatcher.matches(
      type: type,
      keyCode: keyCode,
      flags: flags,
      isAutoRepeat: isAutoRepeat,
      configuredHotkey: configuredHotkey,
      allowsControlCUnlock: allowsControlCUnlock
    )
  }
}
