import Common
import CoreGraphics
import Testing

@MainActor
@Suite(.serialized)
struct HotkeyDisplayTests {
  @Test
  func displayStringRendersGlyphsForMappedKeyCode() {
    let hotkey = KeyboardLockerSettings.Hotkey(keyCode: 37, modifierFlags: [.maskCommand, .maskControl])

    #expect(!hotkey.displayString.isEmpty)
    #expect(!hotkey.displayString.contains("?"))
    #expect(hotkey.displayString != "the configured unlock hotkey")
  }

  @Test
  func displayStringFallsBackToVerbalPhraseForUnmappedKeyCode() {
    // 255 is outside the virtual key-code range of any keyboard layout, so UCKeyTranslate
    // cannot map it and the verbal fallback must replace the old raw "?" glyph.
    let hotkey = KeyboardLockerSettings.Hotkey(keyCode: 255, modifierFlags: [.maskCommand])

    #expect(hotkey.displayString == "the configured unlock hotkey")
  }

  @Test
  func concurrentDisplayRequestsSerializeKeyboardLayoutAccess() async {
    let hotkey = KeyboardLockerSettings.Hotkey(
      keyCode: 37,
      modifierFlags: [.maskCommand, .maskControl]
    )

    let values = await withTaskGroup(of: String.self, returning: [String].self) { group in
      for _ in 0..<64 {
        group.addTask {
          hotkey.displayString
        }
      }

      var values: [String] = []
      for await value in group {
        values.append(value)
      }
      return values
    }

    #expect(values.count == 64)
    #expect(values.allSatisfy { $0 == "⌃⌘L" })
  }
}
