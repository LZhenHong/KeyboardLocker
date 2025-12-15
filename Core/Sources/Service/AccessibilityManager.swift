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
}
