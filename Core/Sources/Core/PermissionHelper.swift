import AppKit
import ApplicationServices

/// Helper class for checking system permissions required by KeyboardLocker
public class PermissionHelper {
  // MARK: - Accessibility Permission

  /// Check if accessibility permission is currently granted
  public static func hasAccessibilityPermission() -> Bool {
    AXIsProcessTrusted()
  }

  /// Check accessibility permission with option to show system prompt
  /// - Parameter promptUser: Whether to show system permission dialog
  /// - Returns: Current permission status
  public static func checkAccessibilityPermission(promptUser: Bool = false) -> Bool {
    if promptUser {
      let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true]
      return AXIsProcessTrustedWithOptions(options as CFDictionary)
    } else {
      return AXIsProcessTrusted()
    }
  }

  /// Request accessibility permission by showing system dialog
  public static func requestAccessibilityPermission() {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true]
    _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
  }

  // MARK: - System URLs

  /// Open System Preferences to Security & Privacy > Accessibility
  public static func openAccessibilitySettings() {
    guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
      return
    }
    NSWorkspace.shared.open(url)
  }
}
