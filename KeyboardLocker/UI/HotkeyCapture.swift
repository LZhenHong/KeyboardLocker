import AppKit
import Client

/// Pure translation from a captured key event to a candidate unlock hotkey.
///
/// Separated from the recorder view so the accept/reject matrix is testable without synthesizing
/// `NSEvent`s. Validation defers to `KeyboardLockerSettings.Hotkey.validated()`, so the picker can
/// never accept a combination the Agent would refuse.
enum HotkeyCapture {
  enum Outcome: Equatable {
    case accepted(KeyboardLockerSettings.Hotkey)
    case rejected(KeyboardLockerSettingsValidationError)

    var hotkey: KeyboardLockerSettings.Hotkey? {
      guard case let .accepted(hotkey) = self else {
        return nil
      }
      return hotkey
    }
  }

  /// Maps AppKit's modifier flags onto the Quartz flags the event tap matches against.
  ///
  /// Only the four the matcher normalizes to are carried over; CapsLock, Fn, and the numeric-pad
  /// flag are dropped here rather than being stored and silently ignored at match time.
  static func eventFlags(from modifierFlags: NSEvent.ModifierFlags) -> CGEventFlags {
    var flags: CGEventFlags = []
    if modifierFlags.contains(.command) {
      flags.insert(.maskCommand)
    }
    if modifierFlags.contains(.control) {
      flags.insert(.maskControl)
    }
    if modifierFlags.contains(.option) {
      flags.insert(.maskAlternate)
    }
    if modifierFlags.contains(.shift) {
      flags.insert(.maskShift)
    }
    return flags
  }

  static func outcome(
    keyCode: UInt16,
    modifierFlags: NSEvent.ModifierFlags
  ) -> Outcome {
    let candidate = KeyboardLockerSettings.Hotkey(
      keyCode: CGKeyCode(keyCode),
      modifierFlags: eventFlags(from: modifierFlags)
    )

    do {
      return try .accepted(candidate.validated())
    } catch let error as KeyboardLockerSettingsValidationError {
      return .rejected(error)
    } catch {
      // `Hotkey.validated()` only throws validation errors; treat anything else as unmappable
      // rather than presenting an unrecognized failure in a hotkey picker.
      return .rejected(.hotkeyUnmappable)
    }
  }

  /// Whether a key event should end recording instead of becoming a hotkey.
  ///
  /// Escape cancels and Return commits by convention; neither can be recorded, so treating them
  /// as candidates would trap the user in a recorder they cannot leave with the keyboard.
  static func isRecordingTerminator(keyCode: UInt16) -> Bool {
    keyCode == kVK_Escape || keyCode == kVK_Return || keyCode == kVK_ANSI_KeypadEnter
  }
}

// `kVK_*` constants live in Carbon.HIToolbox; these three are named locally to avoid importing
// Carbon into the UI layer for nothing more than three integers.
private let kVK_Escape: UInt16 = 53
private let kVK_Return: UInt16 = 36
private let kVK_ANSI_KeypadEnter: UInt16 = 76
