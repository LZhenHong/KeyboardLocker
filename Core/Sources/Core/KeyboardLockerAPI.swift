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
  }

  // MARK: - Lock/Unlock Operations

  /// Lock the keyboard
  public func lockKeyboard() throws {
    try core.lockKeyboard()
  }

  /// Unlock the keyboard
  public func unlockKeyboard() {
    core.unlockKeyboard()
  }

  /// Toggle keyboard lock state
  public func toggleKeyboardLock() {
    core.toggleLock()
  }

  /// Lock keyboard with specified duration (timed lock)
  public func lockKeyboardWithDuration(_ duration: CoreConfiguration.Duration) throws {
    try core.lockKeyboardWithDuration(duration)
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

    // Check if this is a timed lock
    if let timedDuration = core.currentTimedLockDuration {
      if case .infinite = timedDuration {
        // For infinite timed lock, show elapsed time
        let duration = Date().timeIntervalSince(lockedAt)
        let minutes = Int(duration / 60)
        let seconds = Int(duration.truncatingRemainder(dividingBy: 60))
        return String(format: "%02d:%02d", minutes, seconds)
      } else if let remainingTime = core.getTimedLockRemainingTime() {
        // For finite timed lock, show remaining time
        let minutes = Int(remainingTime / 60)
        let seconds = Int(remainingTime.truncatingRemainder(dividingBy: 60))
        return String(format: "%02d:%02d", minutes, seconds)
      }
    }

    // For regular lock, show elapsed time
    let duration = Date().timeIntervalSince(lockedAt)
    let minutes = Int(duration / 60)
    let seconds = Int(duration.truncatingRemainder(dividingBy: 60))
    return String(format: "%02d:%02d", minutes, seconds)
  }

  // MARK: - Auto-lock Configuration (Core Logic Only)

  /// Enable auto-lock with specified duration in minutes
  public func enableAutoLock(minutes: Int) {
    let autoLockSetting: CoreConfiguration.Duration = minutes == 0 ? .never : .minutes(minutes)

    configuration.autoLockDuration = autoLockSetting
    activityMonitor.enableAutoLock(seconds: autoLockSetting.seconds)

    // Start activity monitoring if enabled
    if autoLockSetting.isEnabled {
      activityMonitor.startMonitoring()
    } else {
      activityMonitor.stopMonitoring()
    }
  }

  /// Enable auto-lock with specified duration in seconds (for backward compatibility)
  public func enableAutoLock(seconds: TimeInterval) {
    let minutes = Int(seconds / 60)
    enableAutoLock(minutes: minutes)
  }

  /// Disable auto-lock
  public func disableAutoLock() {
    configuration.autoLockDuration = .never
    activityMonitor.enableAutoLock(seconds: 0)
    activityMonitor.stopMonitoring()
  }

  /// Get current auto-lock status
  public func isAutoLockEnabled() -> Bool {
    configuration.isAutoLockEnabled
  }

  /// Get auto-lock duration in seconds
  public func getAutoLockDurationSeconds() -> Int {
    Int(configuration.autoLockDurationInSeconds)
  }

  /// Get auto-lock duration in minutes
  public func getAutoLockDuration() -> Int {
    configuration.autoLockDuration.minutes
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

  // MARK: - State Change Callbacks

  /// Set callback for lock state changes
  /// - Parameter callback: Called when lock state changes with (isLocked, lockedAt)
  public func setLockStateChangeCallback(_ callback: @escaping (Bool, Date?) -> Void) {
    core.onLockStateChanged = callback
  }

  /// Set callback for unlock hotkey detection
  /// - Parameter callback: Called when unlock hotkey is detected
  public func setUnlockHotkeyCallback(_ callback: @escaping () -> Void) {
    core.onUnlockHotkeyDetected = callback
  }

  // MARK: - Permission Management

  /// Check if accessibility permission is granted
  public func hasAccessibilityPermission() -> Bool {
    // Basic implementation - could be enhanced with proper permission checking
    true
  }

  /// Request accessibility permission
  public func requestAccessibilityPermission() {
    PermissionHelper.requestAccessibilityPermission()
  }

  // MARK: - Private Setup Methods

  /// Setup activity monitor with auto-lock callback
  private func setupActivityMonitor() {
    activityMonitor.onAutoLockTriggered = { [weak self] in
      do {
        try self?.lockKeyboard()
      } catch {
        print("❌ Auto-lock failed: \(error.localizedDescription)")
      }
    }
  }

  /// Setup configuration observer to sync auto-lock settings
  private func setupConfigurationObserver() {
    // Sync initial auto-lock configuration using new enum
    let autoLockConfig = configuration.autoLockDuration
    if autoLockConfig.isEnabled {
      activityMonitor.enableAutoLock(seconds: autoLockConfig.seconds)
      activityMonitor.startMonitoring()
    }
  }
}
