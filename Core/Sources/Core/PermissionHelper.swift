import AppKit
import ApplicationServices
import Foundation

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

  // MARK: - Screen Recording Permission (if needed for enhanced security)

  /// Check if screen recording permission is granted
  /// This might be required for some advanced event monitoring
  public static func hasScreenRecordingPermission() -> Bool {
    if #available(macOS 10.15, *) {
      // For now, we'll assume screen recording permission is not strictly required
      // In a real implementation, you might use ScreenCaptureKit or other methods
      true
    } else {
      // Screen recording permission not required on older macOS versions
      true
    }
  }

  // MARK: - Permission Status Summary

  /// Get a summary of all required permissions
  /// - Returns: Dictionary with permission names and their status
  public static func getPermissionStatus() -> [String: Bool] {
    [
      "accessibility": hasAccessibilityPermission(),
      "screenRecording": hasScreenRecordingPermission(),
    ]
  }

  /// Check if all required permissions are granted
  /// - Returns: True if all required permissions are available
  public static func hasAllRequiredPermissions() -> Bool {
    hasAccessibilityPermission()
    // Add other required permissions here if needed
    // && hasScreenRecordingPermission()
  }

  // MARK: - System URLs

  /// Open System Preferences to Security & Privacy > Accessibility
  public static func openAccessibilitySettings() {
    guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
      return
    }
    NSWorkspace.shared.open(url)
  }

  /// Open System Preferences to Security & Privacy > Screen Recording
  public static func openScreenRecordingSettings() {
    if #available(macOS 10.15, *) {
      guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
        return
      }
      NSWorkspace.shared.open(url)
    }
  }

  // MARK: - Validation Helpers

  /// Validate that the current process can perform keyboard locking operations
  /// - Throws: CoreError if required permissions are not available
  public static func validatePermissions() throws {
    guard hasAccessibilityPermission() else {
      throw CoreError.accessibilityPermissionDenied
    }

    // Add additional permission checks here if needed
  }

  /// Get user-friendly permission status message
  /// - Returns: Localized string describing permission status
  public static func getPermissionStatusMessage() -> String {
    if hasAllRequiredPermissions() {
      return "All required permissions are granted"
    } else {
      var missingPermissions: [String] = []

      if !hasAccessibilityPermission() {
        missingPermissions.append("Accessibility")
      }

      if !hasScreenRecordingPermission() {
        missingPermissions.append("Screen Recording")
      }

      return "Missing permissions: \(missingPermissions.joined(separator: ", "))"
    }
  }
}
