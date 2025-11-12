import Core
import SwiftUI

/// UI-focused keyboard lock manager that bridges Core functionality and UI state
/// This layer handles UI state management and integrates with the Core library
///
/// Design Philosophy:
/// - Uses nested types to encapsulate related functionality
/// - Extensions group methods by responsibility
/// - Clear separation between public API and private implementation
/// - Follows Single Responsibility Principle
class KeyboardLockManager: ObservableObject {
  // MARK: - Nested Types

  /// Manages periodic UI state updates
  private final class UIRefreshScheduler {
    private var timer: Timer?

    var isActive: Bool {
      timer != nil
    }

    func start(interval: TimeInterval = 1.0, onUpdate: @escaping () -> Void) {
      stop()

      timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
        onUpdate()
      }

      // Immediate update
      onUpdate()
    }

    func stop() {
      timer?.invalidate()
      timer = nil
    }
  }

  // MARK: - Published State

  @Published private(set) var isLocked = false
  @Published private(set) var lockDuration: TimeInterval?
  @Published private(set) var autoLockRemainingTime: TimeInterval?

  // MARK: - Dependencies

  private let core: KeyboardLockCore
  private let config: CoreConfiguration
  private let activityMonitor: UserActivityMonitor
  private let notificationManager: NotificationManager

  // MARK: - Coordinators

  private let refreshScheduler = UIRefreshScheduler()

  // MARK: - State

  private var isUserOperation = false

  // MARK: - Lifecycle

  /// Create KeyboardLockManager with injected dependencies
  /// - Parameters:
  ///   - core: Core keyboard functionality
  ///   - config: Configuration management
  ///   - activityMonitor: User activity monitoring
  ///   - notificationManager: Notification handling
  init(
    core: KeyboardLockCore,
    config: CoreConfiguration,
    activityMonitor: UserActivityMonitor,
    notificationManager: NotificationManager
  ) {
    self.core = core
    self.config = config
    self.activityMonitor = activityMonitor
    self.notificationManager = notificationManager

    configureSubscriptions()
    syncInitialState()
  }

  /// Configure reactive state subscriptions from Core components
  private func configureSubscriptions() {
    core.onLockStateChanged = { [weak self] isLocked, _ in
      self?.handleLockStateChange(isLocked)
    }

    core.onUnlockHotkeyDetected = { [weak self] in
      DispatchQueue.main.async {
        self?.unlockKeyboard()
      }
    }

    updateAutoLockState()
  }

  /// Sync initial state from Core components
  private func syncInitialState() {
    DispatchQueue.main.async {
      self.isLocked = self.core.isLocked
      self.updateUIState()

      if self.shouldRunUIUpdater {
        self.startUIUpdates()
      }
    }
  }

  /// Handle lock state change coming from Core layer
  private func handleLockStateChange(_ isLocked: Bool) {
    DispatchQueue.main.async {
      self.isLocked = isLocked
      self.updateUIUpdater()
      self.notifyIfNeeded(isLocked: isLocked)
    }
  }

  /// Send notifications for non-user initiated state changes
  private func notifyIfNeeded(isLocked: Bool) {
    guard !isUserOperation else { return }

    let notificationType: NotificationManager.NotificationType = isLocked ? .keyboardLocked : .keyboardUnlocked

    notificationManager.sendNotificationIfEnabled(
      notificationType,
      showNotifications: config.showNotifications
    )
  }

  deinit {
    refreshScheduler.stop()
  }
}

// MARK: - Public API

extension KeyboardLockManager {
  /// Lock the keyboard (user-initiated, no notification)
  func lockKeyboard() {
    performUserOperation {
      try core.lockKeyboard()
    }
  }

  /// Unlock the keyboard (user-initiated, no notification)
  func unlockKeyboard() {
    guard core.isLocked else { return }

    performUserOperation {
      core.unlockKeyboard()
    }
  }

  /// Toggle keyboard lock state (user-initiated)
  func toggleLock() {
    performUserOperation {
      core.toggleLock()
    }
  }

  /// Get time since last user activity (for UI display)
  func getTimeSinceLastActivity() -> TimeInterval {
    activityMonitor.timeSinceLastActivity
  }

  /// Reset user activity timer manually
  func resetUserActivityTimer() {
    activityMonitor.resetActivityTimer()
  }

  /// Check if required permissions are granted
  func checkPermissions() -> Bool {
    PermissionHelper.hasAccessibilityPermission()
  }

  /// Request required permissions from the user
  func requestPermissions() {
    PermissionHelper.requestAccessibilityPermission()
  }

  /// Force cleanup for Core resources and resync state
  func forceCleanup() {
    core.forceCleanup()
    syncInitialState()
  }
}

// MARK: - Computed Properties

extension KeyboardLockManager {
  /// Auto-lock duration in minutes for UI display
  var autoLockDuration: Int {
    config.autoLockDuration.minutes
  }

  /// Check if auto-lock is enabled
  var isAutoLockEnabled: Bool {
    config.isAutoLockEnabled
  }

  /// Format lock duration as string for UI display
  var lockDurationText: String? {
    guard let duration = lockDuration else { return nil }

    let minutes = Int(duration / 60)
    let seconds = Int(duration.truncatingRemainder(dividingBy: 60))
    return String(format: "%02d:%02d", minutes, seconds)
  }

  /// Format auto-lock remaining time as string for UI display
  var autoLockStatusText: String {
    let duration = autoLockDuration
    if duration == 0 {
      return LocalizationKey.autoLockDisabled.localized
    }

    guard let remainingTime = autoLockRemainingTime else {
      return LocalizationKey.autoLockReadyToLock.localized
    }

    if remainingTime > 0 {
      let countdownString = remainingTime.formattedCountdown
      return LocalizationKey.autoLockCountdownFormat.localized(countdownString)
    } else {
      return LocalizationKey.autoLockReadyToLock.localized
    }
  }
}

// MARK: - Auto-Lock Management

extension KeyboardLockManager {
  /// Update auto-lock state based on current configuration
  private func updateAutoLockState() {
    if isAutoLockEnabled {
      enableAutoLockMonitoring()
    } else {
      activityMonitor.stopMonitoring()
    }

    updateUIUpdater()
  }

  /// Enable auto-lock monitoring with current configuration
  private func enableAutoLockMonitoring() {
    let duration = config.autoLockDuration
    guard isAutoLockEnabled else { return }

    activityMonitor.enableAutoLock(seconds: duration.seconds)
    activityMonitor.onAutoLockTriggered = { [weak self] in
      self?.handleAutoLockTrigger()
    }
    activityMonitor.startMonitoring()
  }

  /// Triggered by auto-lock system (sends notification)
  private func handleAutoLockTrigger() {
    do {
      try core.lockKeyboard()
      print("🤖 Auto-lock activated")
    } catch {
      print("❌ Auto-lock failed: \(error.localizedDescription)")
    }
  }
}

// MARK: - UI State Management

extension KeyboardLockManager {
  /// Determine whether UI updater should be running
  private var shouldRunUIUpdater: Bool {
    isLocked || isAutoLockEnabled
  }

  /// Start periodic UI state updates
  private func startUIUpdates() {
    refreshScheduler.start { [weak self] in
      self?.updateUIState()
    }
  }

  /// Stop periodic UI state updates
  private func stopUIUpdates() {
    refreshScheduler.stop()
    lockDuration = nil
    autoLockRemainingTime = nil
  }

  /// Update UI updater based on current state
  private func updateUIUpdater() {
    if shouldRunUIUpdater {
      startUIUpdates()
    } else {
      stopUIUpdates()
    }
  }

  /// Update all UI state values
  private func updateUIState() {
    lockDuration = calculateLockDuration()
    autoLockRemainingTime = calculateAutoLockRemainingTime()
  }
}

// MARK: - State Calculation

extension KeyboardLockManager {
  /// Calculate lock duration in seconds for UI display
  private func calculateLockDuration() -> TimeInterval? {
    guard core.isLocked else { return nil }

    // Otherwise show elapsed time since lock started
    guard let lockedAt = core.lockedAt else { return nil }
    return Date().timeIntervalSince(lockedAt)
  }

  /// Calculate auto-lock remaining time in seconds for UI display
  private func calculateAutoLockRemainingTime() -> TimeInterval? {
    let duration = autoLockDuration
    guard duration > 0, isAutoLockEnabled else { return nil }

    let timeSinceActivity = getTimeSinceLastActivity()
    return max(0, TimeInterval(duration * 60) - timeSinceActivity)
  }
}

// MARK: - Helpers

extension KeyboardLockManager {
  /// Execute a user-initiated operation (no notifications)
  private func performUserOperation(_ operation: () throws -> Void) {
    isUserOperation = true
    defer { isUserOperation = false }

    do {
      try operation()
    } catch {
      print("❌ User operation failed: \(error.localizedDescription)")
    }
  }
}
