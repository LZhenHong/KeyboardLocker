import AppKit

/// Helper for opening System Settings to specific panes.
public enum SystemSettings {
  /// Opens System Settings to Accessibility privacy pane.
  /// Used when user needs manual guidance to grant permission.
  public static func openAccessibilitySettings() {
    let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    if let url = URL(string: urlString) {
      NSWorkspace.shared.open(url)
    }
  }
}
