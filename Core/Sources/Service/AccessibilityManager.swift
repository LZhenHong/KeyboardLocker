import AppKit
@preconcurrency import ApplicationServices

/// Manages Accessibility permission for CGEventTap-based keyboard filtering
public final class AccessibilityManager {
  private init() {}

  /// Checks current permission status
  /// - Returns: Whether Accessibility permission is granted
  public static func hasPermission() -> Bool {
    AXIsProcessTrusted()
  }

  /// Asks macOS to present the Accessibility permission prompt for the Agent process.
  /// The prompt is asynchronous, so callers must query `hasPermission()` again later.
  public static func requestPermission() {
    let options = [
      kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true,
    ] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)
  }
}
