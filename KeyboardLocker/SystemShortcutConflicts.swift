import Client
import CoreGraphics
import Foundation

/// One system keyboard shortcut that uses the same combination as a candidate hotkey.
struct SystemShortcutConflict: Equatable {
  /// Community-documented name for well-known shortcut IDs, nil for the rest.
  let name: String?
  /// Whether the system shortcut is currently on. A disabled one cannot fire today, but it is
  /// still assigned — and the user can turn it back on into a conflict.
  let isCurrentlyEnabled: Bool
}

/// Best-effort conflict detection against macOS system keyboard shortcuts.
///
/// macOS offers no API to enumerate hotkeys other apps have claimed, so this reads the one
/// authoritative set it can reach: the user's system shortcuts from the
/// `com.apple.symbolichotkeys` preferences (Spotlight, input sources, screenshots, Mission
/// Control…). The plist format is undocumented, which is exactly why results surface as
/// warnings rather than rejections — a miss here is not proof of absence, and a hit may name
/// a shortcut the user has since remapped.
///
/// Note that enabled system shortcuts usually consume their combination before any app sees
/// it, so most of them can never be recorded in the first place; the warning matters most for
/// the shortcuts that do let the keystroke through, and for disabled ones that would conflict
/// the moment the user turns them back on.
enum SystemShortcutConflicts {
  /// The user's system shortcuts using exactly this combination: same key code and the same
  /// four relevant modifiers, normalized by `Hotkey.matches` — the same equality the engine
  /// applies at the event tap. Enabled shortcuts sort first.
  static func conflicts(
    with hotkey: KeyboardLockerSettings.Hotkey,
    shortcuts: () -> [String: Any]? = readSystemShortcuts
  ) -> [SystemShortcutConflict] {
    guard let entries = shortcuts() else {
      return []
    }

    var result: [SystemShortcutConflict] = []
    for (identifier, value) in entries {
      guard let entry = value as? [String: Any],
            let valuePayload = entry["value"] as? [String: Any],
            let parameters = valuePayload["parameters"] as? [Any],
            parameters.count >= 3,
            let keyCode = (parameters[1] as? NSNumber)?.uint16Value,
            let modifiers = (parameters[2] as? NSNumber)?.uint64Value
      else {
        continue
      }
      // Entries without an assigned key carry 0xFFFF.
      guard keyCode != UInt16.max,
            hotkey.matches(keyCode: keyCode, flags: CGEventFlags(rawValue: modifiers))
      else {
        continue
      }
      result.append(SystemShortcutConflict(
        name: knownNames[identifier],
        isCurrentlyEnabled: (entry["enabled"] as? NSNumber)?.boolValue ?? false
      ))
    }

    return result.sorted {
      $0.isCurrentlyEnabled != $1.isCurrentlyEnabled
        ? $0.isCurrentlyEnabled
        : ($0.name ?? "") < ($1.name ?? "")
    }
  }

  private static func readSystemShortcuts() -> [String: Any]? {
    CFPreferencesCopyAppValue(
      "AppleSymbolicHotKeys" as CFString,
      "com.apple.symbolichotkeys" as CFString
    ) as? [String: Any]
  }

  /// Community-documented IDs for the shortcuts users collide with most often. Undocumented
  /// by Apple and extended only cautiously; unknown IDs fall back to a generic message.
  private static let knownNames: [String: String] = [
    "28": "Save picture of screen as a file",
    "29": "Copy picture of screen to the clipboard",
    "30": "Save picture of selected area as a file",
    "31": "Copy picture of selected area to the clipboard",
    "60": "Select the previous input source",
    "61": "Select the next input source",
    "64": "Show Spotlight search",
    "65": "Show Finder search window",
    "79": "Mission Control",
    "80": "Application windows",
    "81": "Show Desktop",
  ]
}
