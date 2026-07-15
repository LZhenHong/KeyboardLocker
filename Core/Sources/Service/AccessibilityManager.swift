import AppKit
import ApplicationServices

/// Manages Accessibility permission for CGEventTap-based keyboard/mouse monitoring
public final class AccessibilityManager {
  private init() {}

  /// Checks current permission status
  /// - Returns: Whether Accessibility permission is granted
  public static func hasPermission() -> Bool {
    AXIsProcessTrusted()
  }
}
