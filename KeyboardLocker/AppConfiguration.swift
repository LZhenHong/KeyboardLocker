import Foundation
import SwiftUI

/// Configuration manager for application settings and preferences
class AppConfiguration: ObservableObject {
  /// Shared configuration instance
  static let shared = AppConfiguration()

  // MARK: - Core Settings

  @AppStorage("showNotifications") var showNotifications: Bool = true {
    willSet { objectWillChange.send() }
  }

  @AppStorage("autoLockDuration") var autoLockDuration: Int = 0 { // in minutes, 0 = never
    willSet { objectWillChange.send() }
  }

  private init() {}

  // MARK: - Convenience Properties

  /// Whether auto-lock is enabled (when duration > 0)
  var isAutoLockEnabled: Bool {
    return autoLockDuration > 0
  }

  /// Auto-lock duration in seconds for internal use
  var autoLockDurationInSeconds: TimeInterval {
    return TimeInterval(autoLockDuration * 60)
  }

  // MARK: - Reset Method

  /// Reset all settings to defaults
  func resetToDefaults() {
    showNotifications = true
    autoLockDuration = 0
    print("� Configuration reset to defaults")
  }
}

// MARK: - Configuration Constants

extension AppConfiguration {
  /// Default values for configuration
  enum Defaults {
    static let showNotifications = true
    static let autoLockDuration = 0 // minutes, 0 = never
  }
}
