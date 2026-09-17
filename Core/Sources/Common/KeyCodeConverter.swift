import Carbon
import Cocoa

public enum KeyCodeConverter {
  // MARK: - Public API

  /// Convert key code and modifiers to readable shortcut string
  /// - Parameters:
  ///   - keyCode: CGKeyCode value
  ///   - modifiers: CGEventFlags for modifier keys
  ///   - separator: Optional separator between each key (default: empty)
  /// - Returns: Complete shortcut string (e.g., "⌥⌘L" or "⌥ ⌘ L") or nil if conversion fails
  public static func stringFromKeyCode(_ keyCode: CGKeyCode, modifiers: CGEventFlags, separator: String = "") -> String? {
    let modifierString = modifierSymbols(from: modifiers, separator: separator)
    // An unmappable key code must fail the whole conversion instead of surfacing a raw
    // "?" glyph, so callers can fall back to verbal copy.
    guard let keyChar = keyCharacter(for: keyCode) else {
      return nil
    }

    let result: String = if !modifierString.isEmpty, !separator.isEmpty {
      modifierString + separator + keyChar
    } else {
      modifierString + keyChar
    }

    return result.isEmpty ? nil : result
  }

  /// Maps a key press to the character it would type on the current ASCII-capable layout,
  /// honoring shift state. The Agent's unlock-phrase matcher consumes this; shortcut display
  /// keeps using `stringFromKeyCode`.
  /// - Returns: The typed character, or nil for unmappable keys and multi-codepoint results
  ///   (dead-key remnants, control sequences), which are not phrase input.
  public static func typedCharacter(for keyCode: CGKeyCode, shiftDown: Bool) -> Character? {
    let string: String? = if Thread.isMainThread {
      characterFromKeyboardLayout(keyCode, action: kUCKeyActionDown, shiftDown: shiftDown)
    } else {
      DispatchQueue.main.sync {
        characterFromKeyboardLayout(keyCode, action: kUCKeyActionDown, shiftDown: shiftDown)
      }
    }
    guard let string, string.count == 1 else {
      return nil
    }
    return string.first
  }

  // MARK: - Private Helpers

  /// Convert modifier flags to symbol string
  /// - Parameters:
  ///   - modifiers: CGEventFlags for modifier keys
  ///   - separator: Optional separator between each modifier symbol
  /// - Returns: Modifier symbols in macOS standard order (⌃⌥⇧⌘)
  private static func modifierSymbols(from modifiers: CGEventFlags, separator: String = "") -> String {
    var symbols: [String] = []

    if modifiers.contains(.maskControl) {
      symbols.append("⌃")
    }
    if modifiers.contains(.maskAlternate) {
      symbols.append("⌥")
    }
    if modifiers.contains(.maskShift) {
      symbols.append("⇧")
    }
    if modifiers.contains(.maskCommand) {
      symbols.append("⌘")
    }

    return symbols.joined(separator: separator)
  }

  /// Get character representation for a key code
  /// - Parameter keyCode: CGKeyCode value
  /// - Returns: Uppercase character or symbol, nil when the keyboard layout cannot map it
  private static func keyCharacter(for keyCode: CGKeyCode) -> String? {
    let character: String? = if Thread.isMainThread {
      characterFromKeyboardLayout(keyCode, action: kUCKeyActionDisplay, shiftDown: false)
    } else {
      DispatchQueue.main.sync {
        characterFromKeyboardLayout(keyCode, action: kUCKeyActionDisplay, shiftDown: false)
      }
    }
    return character?.uppercased()
  }

  /// Get character from the system keyboard layout using UCKeyTranslate.
  ///
  /// Reads the ASCII-capable layout rather than the current input source: an active input
  /// method (e.g. Pinyin) may carry no Unicode layout data, which would render the hotkey as
  /// "?" precisely while the user is typing in a non-Latin context.
  /// - Parameters:
  ///   - keyCode: CGKeyCode value
  ///   - action: `kUCKeyActionDisplay` for presentation, `kUCKeyActionDown` for typed input
  ///   - shiftDown: whether shift was held, for typed-input fidelity
  /// - Returns: Character string or nil
  /// TIS/TSM APIs abort the process when a UI process calls them concurrently. Keep the complete
  /// input-source lookup and translation on the main thread so every wrapper shares one safe
  /// process-local serialization boundary.
  private static func characterFromKeyboardLayout(
    _ keyCode: CGKeyCode,
    action: Int,
    shiftDown: Bool
  ) -> String? {
    let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource().takeRetainedValue()
    guard let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
      return nil
    }

    let dataRef = unsafeBitCast(layoutData, to: CFData.self)
    let layout = unsafeBitCast(CFDataGetBytePtr(dataRef), to: UnsafePointer<UCKeyboardLayout>.self)

    var deadKeyState: UInt32 = 0
    var length = 0
    var chars = [UniChar](repeating: 0, count: 4)

    // UCKeyTranslate takes modifier state in the high-byte layout: Carbon's shiftKey (0x0200)
    // arrives as 0x02.
    let modifierState = shiftDown ? UInt32(shiftKey >> 8) : 0
    let error = UCKeyTranslate(
      layout,
      keyCode,
      UInt16(action),
      UInt32(modifierState),
      UInt32(LMGetKbdType()),
      UInt32(kUCKeyTranslateNoDeadKeysMask),
      &deadKeyState,
      4,
      &length,
      &chars
    )

    guard error == noErr, length > 0 else {
      return nil
    }

    return String(utf16CodeUnits: chars, count: length)
  }
}
