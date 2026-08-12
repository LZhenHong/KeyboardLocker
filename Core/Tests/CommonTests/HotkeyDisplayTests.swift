import Common
import CoreGraphics
import XCTest

final class HotkeyDisplayTests: XCTestCase {
  func testDisplayStringRendersGlyphsForMappedKeyCode() {
    let hotkey = KeyboardLockerSettings.Hotkey(keyCode: 37, modifierFlags: [.maskCommand, .maskControl])

    XCTAssertFalse(hotkey.displayString.isEmpty)
    XCTAssertFalse(hotkey.displayString.contains("?"))
    XCTAssertNotEqual(hotkey.displayString, "the configured unlock hotkey")
  }

  func testDisplayStringFallsBackToVerbalPhraseForUnmappedKeyCode() {
    // 255 is outside the virtual key-code range of any keyboard layout, so UCKeyTranslate
    // cannot map it and the verbal fallback must replace the old raw "?" glyph.
    let hotkey = KeyboardLockerSettings.Hotkey(keyCode: 255, modifierFlags: [.maskCommand])

    XCTAssertEqual(hotkey.displayString, "the configured unlock hotkey")
  }
}
