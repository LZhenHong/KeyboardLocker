import Common
import CoreGraphics
@testable import Service
import XCTest

final class UnlockGestureMatcherTests: XCTestCase {
  private let configuredHotkey = KeyboardLockerSettings.Hotkey(
    keyCode: 37,
    modifierFlags: [.maskControl, .maskCommand]
  )

  func testConfiguredHotkeyAlwaysUnlocks() {
    XCTAssertTrue(
      matches(
        keyCode: configuredHotkey.keyCode,
        flags: configuredHotkey.modifierFlags,
        allowsControlCUnlock: false
      )
    )
  }

  func testControlCUnlocksInteractiveLock() {
    XCTAssertTrue(
      matches(
        keyCode: UnlockGestureMatcher.controlCKeyCode,
        flags: [.maskControl],
        allowsControlCUnlock: true
      )
    )
  }

  func testControlCDoesNotUnlockNonInteractiveLock() {
    XCTAssertFalse(
      matches(
        keyCode: UnlockGestureMatcher.controlCKeyCode,
        flags: [.maskControl],
        allowsControlCUnlock: false
      )
    )
  }

  func testControlCRejectsAdditionalRelevantModifiers() {
    XCTAssertFalse(
      matches(
        keyCode: UnlockGestureMatcher.controlCKeyCode,
        flags: [.maskControl, .maskCommand],
        allowsControlCUnlock: true
      )
    )
  }

  func testControlCIgnoresCapsLock() {
    XCTAssertTrue(
      matches(
        keyCode: UnlockGestureMatcher.controlCKeyCode,
        flags: [.maskControl, .maskAlphaShift],
        allowsControlCUnlock: true
      )
    )
  }

  func testAutoRepeatAndKeyUpNeverUnlock() {
    XCTAssertFalse(
      matches(
        keyCode: UnlockGestureMatcher.controlCKeyCode,
        flags: [.maskControl],
        allowsControlCUnlock: true,
        isAutoRepeat: true
      )
    )
    XCTAssertFalse(
      matches(
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
