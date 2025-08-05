import Core
import SwiftUI

/// UI-focused keyboard lock manager that uses Core Library's unified API
/// This layer handles only UI-specific concerns like notifications
class KeyboardLockManager: ObservableObject, KeyboardLockManaging {
  @Published var isLocked = false
  @Published var autoLockEnabled = false

  // Core API - unified interface for all functionality
  private let coreAPI = KeyboardLockerAPI.shared

  // UI-specific dependencies
  private let notificationManager: NotificationManaging

  init(
    notificationManager: NotificationManaging = NotificationManager.shared
  ) {
    self.notificationManager = notificationManager

    // Setup state change callback and sync
    setupLockStateCallback()
    syncInitialState()
  }

  deinit {
    cleanup()
  }

  /// Clean up resources when object is deallocated
  private func cleanup() {
    // Core API handles its own cleanup
  }

  // MARK: - Public Interface (UI Actions)

  func lockKeyboard() {
    do {
      try coreAPI.lockKeyboard()

      // Send notification to user (UI concern)
      notificationManager.sendNotificationIfEnabled(
        .keyboardLocked, // Use locked notification for auto-lock
        showNotifications: coreAPI.isNotificationsEnabled()
      )
    } catch {
      print("❌ Failed to lock keyboard: \(error.localizedDescription)")
    }
  }

  func unlockKeyboard() {
    guard coreAPI.isLocked else {
      return
    }

    coreAPI.unlockKeyboard()

    // Send notification to user (UI concern)
    notificationManager.sendNotificationIfEnabled(
      .keyboardUnlocked,
      showNotifications: coreAPI.isNotificationsEnabled()
    )
  }

  func toggleLock() {
    coreAPI.toggleKeyboardLock()

    // Send notification based on new state
    let notificationType: NotificationManager.NotificationType = coreAPI.isLocked ? .keyboardLocked : .keyboardUnlocked
    notificationManager.sendNotificationIfEnabled(
      notificationType,
      showNotifications: coreAPI.isNotificationsEnabled()
    )
  }

  /// Start a timed lock with specified duration
  func lockKeyboard(with duration: CoreConfiguration.Duration) {
    do {
      try coreAPI.lockKeyboardWithDuration(duration)

      // Send notification to user (UI concern)
      notificationManager.sendNotificationIfEnabled(
        .keyboardLocked,
        showNotifications: coreAPI.isNotificationsEnabled()
      )
    } catch {
      print("❌ Failed to start timed lock: \(error.localizedDescription)")
    }
  }

  // MARK: - Auto-Lock Management (using Core API directly)

  func startAutoLock() {
    // Use thirtyMinutes as default when enabling auto-lock if currently disabled
    if !coreAPI.configuration.autoLockDuration.isEnabled {
      coreAPI.configuration.autoLockDuration = .minutes(30)
    }
  }

  func stopAutoLock() {
    coreAPI.configuration.autoLockDuration = .never
  }

  func toggleAutoLock() {
    if coreAPI.configuration.autoLockDuration.isEnabled {
      coreAPI.configuration.autoLockDuration = .never
    } else {
      coreAPI.configuration.autoLockDuration = .minutes(30)
    }
    // Update UI state
    syncAutoLockConfiguration()
  }

  /// Get time since last user activity (for UI display)
  func getTimeSinceLastActivity() -> TimeInterval {
    coreAPI.getTimeSinceLastActivity()
  }

  /// Reset user activity timer manually
  func resetUserActivityTimer() {
    coreAPI.resetUserActivityTimer()
  }

  // MARK: - Status and Information

  func getLockDurationString() -> String? {
    coreAPI.getLockDurationString()
  }

  func checkPermissions() -> Bool {
    coreAPI.hasAccessibilityPermission()
  }

  func requestPermissions() {
    coreAPI.requestAccessibilityPermission()
  }

  // MARK: - Configuration Access (直接使用CoreConfiguration)

  /// Auto-lock duration in minutes for UI display
  var autoLockDuration: Int {
    CoreConfiguration.shared.autoLockDuration.minutes
  }

  /// Check if auto-lock is enabled
  var isAutoLockEnabled: Bool {
    CoreConfiguration.shared.autoLockDuration.isEnabled
  }

  /// Get/set notification preference (using Core directly)
  var showNotifications: Bool {
    get { coreAPI.isNotificationsEnabled() }
    set { coreAPI.setNotificationsEnabled(newValue) }
  }

  // MARK: - Utility Methods

  func forceCleanup() {
    // Core API manages its own cleanup
    syncInitialState()
  }

  // MARK: - Private Methods

  /// Setup lock state change callback from Core
  private func setupLockStateCallback() {
    // Use Core's callback instead of timer-based polling
    coreAPI.setLockStateChangeCallback { [weak self] isLocked, _ in
      DispatchQueue.main.async {
        self?.isLocked = isLocked
        // Auto-lock state should also be synced when lock state changes
        self?.autoLockEnabled = self?.coreAPI.configuration.autoLockDuration.isEnabled ?? false
      }
    }
  }

  /// Sync initial state from Core
  private func syncInitialState() {
    DispatchQueue.main.async {
      self.isLocked = self.coreAPI.isLocked
      self.autoLockEnabled = self.coreAPI.configuration.autoLockDuration.isEnabled
    }
  }

  /// Sync auto-lock configuration from Core
  private func syncAutoLockConfiguration() {
    DispatchQueue.main.async {
      self.autoLockEnabled = self.coreAPI.configuration.autoLockDuration.isEnabled
    }
  }
}
