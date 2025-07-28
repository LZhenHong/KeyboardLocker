import Combine
import Foundation

/// Simplified Core API for KeyboardLocker
/// This provides a unified interface for both CLI and GUI applications
public class KeyboardLockerAPI: ObservableObject {
  // MARK: - Singleton

  public static let shared = KeyboardLockerAPI()

  // MARK: - Core Components

  private let core = KeyboardLockCore.shared
  private let activityMonitor = UserActivityMonitor.shared

  /// The shared configuration instance
  public var configuration: CoreConfiguration {
    CoreConfiguration.shared
  }

  // MARK: - Initialization

  private init() {
    setupActivityMonitor()
    setupConfigurationObserver()
    print("🚀 KeyboardLockerAPI initialized")
  }

  // MARK: - Lock/Unlock Operations

  /// Lock the keyboard
  public func lockKeyboard() throws {
    try core.lockKeyboard()
    print("🔒 Keyboard locked via API")
  }

  /// Unlock the keyboard
  public func unlockKeyboard() {
    core.unlockKeyboard()
    print("🔓 Keyboard unlocked via API")
  }

  /// Toggle keyboard lock state
  public func toggleKeyboardLock() {
    core.toggleLock()
  }

  /// Get current lock status
  public var isLocked: Bool {
    core.basicLockInfo.isLocked
  }

  /// Get locked at timestamp
  public var lockedAt: Date? {
    core.basicLockInfo.lockedAt
  }

  /// Get lock duration string
  public func getLockDurationString() -> String? {
    guard let lockedAt else { return nil }
    let duration = Date().timeIntervalSince(lockedAt)
    let minutes = Int(duration / 60)
    let seconds = Int(duration.truncatingRemainder(dividingBy: 60))
    return String(format: "%02d:%02d", minutes, seconds)
  }

  // MARK: - Auto-lock Configuration (Core Logic Only)

  /// Enable auto-lock with specified duration in seconds
  /// Core只关心传入的时间值，不管理UI选项
  public func enableAutoLock(seconds: TimeInterval) {
    configuration.autoLockDuration = Int(seconds)
    activityMonitor.enableAutoLock(seconds: seconds)

    // Start activity monitoring if not already started
    if seconds > 0 {
      activityMonitor.startMonitoring()
      print("✅ Auto-lock enabled: \(Int(seconds / 60)) minutes")
    } else {
      activityMonitor.stopMonitoring()
      print("❌ Auto-lock disabled")
    }
  }

  /// Enable auto-lock with specified duration in minutes (convenience method)
  public func enableAutoLock(minutes: Int) {
    enableAutoLock(seconds: TimeInterval(minutes * 60))
  }

  /// Disable auto-lock
  public func disableAutoLock() {
    enableAutoLock(seconds: 0)
  }

  /// Get current auto-lock status
  public func isAutoLockEnabled() -> Bool {
    configuration.isAutoLockEnabled
  }

  /// Get auto-lock duration in seconds (Core stores in seconds)
  public func getAutoLockDurationSeconds() -> Int {
    configuration.autoLockDuration
  }

  /// Get auto-lock duration in minutes (convenience method for UI)
  public func getAutoLockDuration() -> Int {
    configuration.autoLockDuration / 60
  }

  /// Get time since last user activity (for UI display)
  public func getTimeSinceLastActivity() -> TimeInterval {
    activityMonitor.timeSinceLastActivity
  }

  /// Reset user activity timer manually
  public func resetUserActivityTimer() {
    activityMonitor.resetActivityTimer()
  }

  // MARK: - Configuration Management

  /// Export current configuration
  public func exportConfiguration() -> [String: Any] {
    configuration.exportConfiguration()
  }

  /// Import configuration
  public func importConfiguration(_ newConfig: [String: Any]) {
    configuration.importConfiguration(newConfig)
  }

  /// Reset configuration to defaults
  public func resetConfiguration() {
    configuration.resetToDefaults()
  }

  /// Set notification preferences
  public func setNotificationsEnabled(_ enabled: Bool) {
    configuration.showNotifications = enabled
  }

  /// Get notification preferences
  public func isNotificationsEnabled() -> Bool {
    configuration.showNotifications
  }

  // MARK: - Permission Management

  /// Check if accessibility permission is granted
  public func hasAccessibilityPermission() -> Bool {
    // Basic implementation - could be enhanced with proper permission checking
    true
  }

  /// Request accessibility permission
  public func requestAccessibilityPermission() {
    print("⚠️ Accessibility permission required")
  }

  // MARK: - Private Setup Methods

  /// Setup activity monitor with auto-lock callback
  private func setupActivityMonitor() {
    activityMonitor.onAutoLockTriggered = { [weak self] in
      do {
        try self?.lockKeyboard()
        print("🔒 Auto-lock triggered - keyboard locked")
      } catch {
        print("❌ Auto-lock failed: \(error.localizedDescription)")
      }
    }
  }

  /// Setup configuration observer to sync auto-lock settings
  private func setupConfigurationObserver() {
    // Sync initial auto-lock configuration
    let duration = configuration.autoLockDuration
    if duration > 0 {
      activityMonitor.enableAutoLock(seconds: TimeInterval(duration))
      activityMonitor.startMonitoring()
    }
  }
}
