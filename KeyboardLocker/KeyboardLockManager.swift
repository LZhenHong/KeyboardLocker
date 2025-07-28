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

    // Setup observers and sync
    setupCoreObservers()
    syncInitialState()
  }

  deinit {
    cleanup()
  }

  /// Clean up resources when object is deallocated
  private func cleanup() {
    // Core API handles its own cleanup
    print("🧹 KeyboardLockManager cleanup completed")
  }

  // MARK: - Public Interface (UI Actions)

  func lockKeyboard() {
    do {
      try coreAPI.lockKeyboard()
      print("✅ Keyboard locked successfully")

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
    print("✅ Keyboard unlocked successfully")

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

  // MARK: - Auto-Lock Management (using Core API directly)

  func startAutoLock() {
    let durationMinutes = max(coreAPI.configuration.autoLockDuration / 60, 1) // Convert to minutes, minimum 1
    coreAPI.configuration.autoLockDuration = durationMinutes * 60 // This will trigger Core API update
    print("✅ Auto-lock enabled with \(durationMinutes) minutes duration (activity-based)")
  }

  func stopAutoLock() {
    coreAPI.configuration.autoLockDuration = 0 // This will trigger Core API update
    print("✅ Auto-lock disabled")
  }

  func toggleAutoLock() {
    if coreAPI.configuration.autoLockDuration > 0 {
      coreAPI.configuration.autoLockDuration = 0
    } else {
      coreAPI.configuration.autoLockDuration = 1800 // Default 30 minutes
    }
    print("✅ Auto-lock toggled")
    // Update UI state
    syncAutoLockConfiguration()
  }

  func updateAutoLockSettings() {
    // Settings are now managed directly through Core API
    print("✅ Auto-lock settings updated with activity monitoring")
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
    print("ℹ️ Permission request sent. Please grant accessibility permission in System Settings.")
  }

  // MARK: - Configuration Access (forwarded to Core directly)

  /// Auto-lock duration in minutes for UI display (using Core config)
  var autoLockDuration: Int {
    coreAPI.configuration.autoLockDuration / 60 // Convert seconds to minutes for UI
  }

  /// Check if auto-lock is enabled (using Core config)
  var isAutoLockEnabled: Bool {
    coreAPI.configuration.autoLockDuration > 0
  }

  /// Get/set notification preference (using Core directly)
  var showNotifications: Bool {
    get { coreAPI.isNotificationsEnabled() }
    set { coreAPI.setNotificationsEnabled(newValue) }
  }

  // MARK: - Utility Methods

  func forceCleanup() {
    // Core API manages its own cleanup
    print("🧹 KeyboardLockManager force cleanup completed")
    syncInitialState()
  }

  // MARK: - Private Methods

  /// Setup observers for Core configuration changes
  private func setupCoreObservers() {
    // Check lock status and auto-lock status periodically
    Timer.publish(every: 0.5, on: .main, in: .common)
      .autoconnect()
      .sink { [weak self] _ in
        self?.isLocked = self?.coreAPI.isLocked ?? false
        self?.autoLockEnabled = (self?.coreAPI.configuration.autoLockDuration ?? 0) > 0
      }
      .store(in: &cancellables)
  }

  /// Sync initial state from Core
  private func syncInitialState() {
    DispatchQueue.main.async {
      self.isLocked = self.coreAPI.isLocked
      self.autoLockEnabled = self.coreAPI.configuration.autoLockDuration > 0
    }
  }

  /// Sync auto-lock configuration from Core
  private func syncAutoLockConfiguration() {
    DispatchQueue.main.async {
      self.autoLockEnabled = self.coreAPI.configuration.autoLockDuration > 0
    }
  }

  // MARK: - Combine Support

  private var cancellables = Set<AnyCancellable>()
}
