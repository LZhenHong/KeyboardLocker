import AppKit
import Core

/// Permission management for accessibility and notification permissions
class PermissionManager: ObservableObject {
  // MARK: - Published Properties

  @Published var hasAccessibilityPermission = false

  // Computed property that delegates to NotificationManager
  var hasNotificationPermission: Bool {
    notificationManager.isAuthorized
  }

  // MARK: - Private Properties

  let notificationManager: NotificationManager

  // MARK: - Initialization

  init(notificationManager: NotificationManager) {
    self.notificationManager = notificationManager
    checkAllPermissions()
    setupApplicationFocusMonitoring()
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  // MARK: - Public Methods

  /// Check accessibility permission status (required permission)
  func checkAllPermissions() {
    checkAccessibilityPermission()
  }

  /// Request accessibility permission by opening system settings
  func requestAccessibilityPermission() {
    // Use Core library's permission helper
    let currentStatus = PermissionHelper.checkAccessibilityPermission(promptUser: true)

    DispatchQueue.main.async {
      self.hasAccessibilityPermission = currentStatus
    }

    // If still not trusted, open system preferences
    if !currentStatus {
      PermissionHelper.openAccessibilitySettings()
    }
  }

  /// Request notification permission using NotificationManager
  /// Should only be called when user enables notifications in settings
  func requestNotificationPermission() {
    notificationManager.requestAuthorization { [weak self] (_: Bool, error: Error?) in
      if let error {
        print("Failed to request notification permission: \(error)")
      }
      // Trigger objectWillChange to update any UI that depends on hasNotificationPermission
      DispatchQueue.main.async {
        self?.objectWillChange.send()
      }
    }
  }

  // MARK: - Private Methods

  /// Setup monitoring for application focus changes
  private func setupApplicationFocusMonitoring() {
    // Monitor when app becomes active (gains focus)
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(applicationDidBecomeActive),
      name: NSApplication.didBecomeActiveNotification,
      object: nil
    )

    // Monitor when app window becomes key (for menu bar apps)
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(applicationDidBecomeActive),
      name: NSWindow.didBecomeKeyNotification,
      object: nil
    )
  }

  /// Handle application becoming active - check permissions
  @objc private func applicationDidBecomeActive() {
    checkAllPermissions()
  }

  private func checkAccessibilityPermission() {
    let currentPermission = PermissionHelper.hasAccessibilityPermission()

    // Only update and log if the permission status has changed
    if currentPermission != hasAccessibilityPermission {
      DispatchQueue.main.async {
        self.hasAccessibilityPermission = currentPermission
        print("Accessibility permission changed to: \(currentPermission)")
      }
    }
  }

  private func openAccessibilitySettings() {
    PermissionHelper.openAccessibilitySettings()
    print("Opened accessibility settings")
  }
}
