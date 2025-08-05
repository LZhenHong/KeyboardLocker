import Combine
import Core
import SwiftUI

/// UI-focused keyboard lock manager that bridges Core functionality and UI state
/// This layer handles UI state management and integrates with the Core library
class KeyboardLockManager: ObservableObject {
  // MARK: - Published UI State

  @Published var isLocked = false
  @Published var autoLockEnabled = false

  // MARK: - Dependencies

  // Core functionality - injected dependencies
  private let core: KeyboardLockCore
  private let config: CoreConfiguration
  private let activityMonitor: UserActivityMonitor

  // UI-specific dependencies
  private let notificationManager: NotificationManager

  // MARK: - Combine Subscriptions

  private var cancellables = Set<AnyCancellable>()

  // MARK: - Initialization

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

    setupStateSubscriptions()
    syncInitialState()
  }

  deinit {
    cleanup()
  }

  /// Clean up resources when object is deallocated
  private func cleanup() {
    cancellables.removeAll()
  }

  // MARK: - Public Interface (UI Actions)

  func lockKeyboard() {
    do {
      try core.lockKeyboard()
    } catch {
      print("❌ Failed to lock keyboard: \(error.localizedDescription)")
    }
  }

  func unlockKeyboard() {
    guard core.isKeyboardLocked else {
      return
    }
    core.unlockKeyboard()
  }

  func toggleLock() {
    core.toggleLock()
  }

  /// Start a timed lock with specified duration
  func lockKeyboard(with duration: CoreConfiguration.Duration) {
    do {
      try core.lockKeyboard()
      // For timed locks, we implement timer logic in the UI layer
      // This keeps business logic separate from core functionality
      if case let .minutes(minutes) = duration, minutes > 0 {
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(minutes * 60)) {
          self.core.unlockKeyboard()
          print("⏰ Timed lock completed after \(minutes) minutes")
        }
      } else if case .infinite = duration {
        print("♾️ Infinite timed lock started (manual unlock required)")
      }
    } catch {
      print("❌ Failed to start timed lock: \(error.localizedDescription)")
    }
  }

  // MARK: - Auto-Lock Management

  func startAutoLock() {
    // Use 30 minutes as default when enabling auto-lock if currently disabled
    if !config.autoLockDuration.isEnabled {
      config.autoLockDuration = .minutes(30)
    }
    enableAutoLockMonitoring()
  }

  func stopAutoLock() {
    config.autoLockDuration = .never
    activityMonitor.stopMonitoring()
  }

  func toggleAutoLock() {
    if config.autoLockDuration.isEnabled {
      config.autoLockDuration = .never
      activityMonitor.stopMonitoring()
    } else {
      config.autoLockDuration = .minutes(30)
      enableAutoLockMonitoring()
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

  // MARK: - Status and Information

  func getLockDurationString() -> String? {
    guard let lockedAt = core.keyboardLockedAt else { return nil }

    let duration = Date().timeIntervalSince(lockedAt)
    let minutes = Int(duration / 60)
    let seconds = Int(duration.truncatingRemainder(dividingBy: 60))
    return String(format: "%02d:%02d", minutes, seconds)
  }

  func checkPermissions() -> Bool {
    PermissionHelper.hasAccessibilityPermission()
  }

  func requestPermissions() {
    PermissionHelper.requestAccessibilityPermission()
  }

  // MARK: - Configuration Access

  /// Auto-lock duration in minutes for UI display
  var autoLockDuration: Int {
    config.autoLockDuration.minutes
  }

  /// Check if auto-lock is enabled
  var isAutoLockEnabled: Bool {
    config.autoLockDuration.isEnabled
  }

  /// Get/set notification preference
  var showNotifications: Bool {
    get { config.showNotifications }
    set { config.showNotifications = newValue }
  }

  // MARK: - Utility Methods

  func forceCleanup() {
    core.forceCleanup()
    syncInitialState()
  }

  // MARK: - Private Setup Methods

  /// Setup reactive state subscriptions from Core components
  private func setupStateSubscriptions() {
    // Setup lock state callback
    core.onLockStateChanged = { [weak self] isLocked, _ in
      DispatchQueue.main.async {
        self?.isLocked = isLocked

        // Send notifications based on state change
        let notificationType: NotificationManager.NotificationType =
          isLocked ? .keyboardLocked : .keyboardUnlocked
        self?.notificationManager.sendNotificationIfEnabled(
          notificationType,
          showNotifications: self?.config.showNotifications ?? false
        )
      }
    }

    // Subscribe to configuration changes for auto-lock state
    config.$autoLockDuration
      .receive(on: DispatchQueue.main)
      .sink { [weak self] duration in
        self?.autoLockEnabled = duration.isEnabled
        if duration.isEnabled {
          self?.enableAutoLockMonitoring()
        } else {
          self?.activityMonitor.stopMonitoring()
        }
      }
      .store(in: &cancellables)
  }

  /// Sync initial state from Core components
  private func syncInitialState() {
    DispatchQueue.main.async {
      self.isLocked = self.core.isKeyboardLocked
      self.autoLockEnabled = self.config.autoLockDuration.isEnabled
    }
  }

  /// Enable auto-lock monitoring with current configuration
  private func enableAutoLockMonitoring() {
    let duration = config.autoLockDuration
    if duration.isEnabled {
      activityMonitor.enableAutoLock(seconds: duration.seconds)
      activityMonitor.onAutoLockTriggered = { [weak self] in
        self?.lockKeyboard()
      }
      activityMonitor.startMonitoring()
    }
  }
}
