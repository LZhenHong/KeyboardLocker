import AppKit
import ApplicationServices

/// Manages Accessibility permission for CGEventTap-based keyboard/mouse monitoring
public final class AccessibilityPermissionManager {
  private init() {}

  /// Checks current permission status
  /// - Returns: Whether Accessibility permission is granted
  public static func hasPermission() -> Bool {
    AXIsProcessTrusted()
  }

  /// Requests Accessibility permission from the user
  /// - Parameter showPrompt: Whether to trigger macOS system prompt
  /// - Returns: Current permission status after request
  @discardableResult
  public static func requestPermission(showPrompt: Bool = true) -> Bool {
    // Early return if already granted to avoid unnecessary system calls
    if hasPermission() {
      return true
    }

    guard showPrompt else {
      return false
    }

    // Trigger macOS system prompt that opens Privacy & Security settings
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
  }

  /// Opens System Settings to Accessibility privacy pane
  /// Used when user needs manual guidance to grant permission
  public static func openSystemSettings() {
    // Deep link to specific privacy pane for better UX
    let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    if let url = URL(string: urlString) {
      NSWorkspace.shared.open(url)
    }
  }
}
