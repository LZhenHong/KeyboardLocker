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
    let keyChar = keyCharacter(for: keyCode)

    let result: String = if !modifierString.isEmpty, !separator.isEmpty {
      modifierString + separator + keyChar
    } else {
      modifierString + keyChar
    }

    return result.isEmpty ? nil : result
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
  /// - Returns: Uppercase character or symbol
  private static func keyCharacter(for keyCode: CGKeyCode) -> String {
    characterFromKeyboardLayout(keyCode)?.uppercased() ?? "?"
  }

  /// Get character from system keyboard layout using UCKeyTranslate
  /// - Parameter keyCode: CGKeyCode value
  /// - Returns: Character string or nil
  private static func characterFromKeyboardLayout(_ keyCode: CGKeyCode) -> String? {
    let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
    guard let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
      return nil
    }

    let dataRef = unsafeBitCast(layoutData, to: CFData.self)
    let layout = unsafeBitCast(CFDataGetBytePtr(dataRef), to: UnsafePointer<UCKeyboardLayout>.self)

    var deadKeyState: UInt32 = 0
    var length = 0
    var chars = [UniChar](repeating: 0, count: 4)

    let error = UCKeyTranslate(
      layout,
      keyCode,
      UInt16(kUCKeyActionDisplay),
      0, // No modifiers - we want the base character
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
