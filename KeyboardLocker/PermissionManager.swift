import AppKit
import Carbon
import Foundation
import UserNotifications

/// Permission management for accessibility and notification permissions
class PermissionManager: ObservableObject {
  // MARK: - Published Properties

  @Published var hasAccessibilityPermission = false
  @Published var hasNotificationPermission = false

  // MARK: - Initialization

  init() {
    checkAllPermissions()
    setupApplicationFocusMonitoring()
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  // MARK: - Public Methods

  /// Check all permission statuses and update published properties
  func checkAllPermissions() {
    checkAccessibilityPermission()
    checkNotificationPermission()
  }

  /// Request accessibility permission by opening system settings
  func requestAccessibilityPermission() {
    // Show immediate authorization prompt if available
    if !AXIsProcessTrusted() {
      // Try to request with prompt first
      let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
      let trusted = AXIsProcessTrustedWithOptions(options)

      DispatchQueue.main.async {
        self.hasAccessibilityPermission = trusted
      }

      // If still not trusted, open system preferences
      if !trusted {
        openAccessibilitySettings()
      }
    }
  }

  /// Request notification permission
  func requestNotificationPermission() {
    UNUserNotificationCenter.current().requestAuthorization(
      options: [.alert, .sound]
    ) { [weak self] granted, error in
      DispatchQueue.main.async {
        self?.hasNotificationPermission = granted
        if let error = error {
          print("Failed to request notification permission: \(error)")
        }
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

    print("Application focus monitoring setup completed")
  }

  /// Handle application becoming active - check permissions
  @objc private func applicationDidBecomeActive() {
    print("Application became active - checking permissions")
    checkAllPermissions()
  }

  private func checkAccessibilityPermission() {
    let currentPermission = AXIsProcessTrusted()

    // Only update and log if the permission status has changed
    if currentPermission != hasAccessibilityPermission {
      DispatchQueue.main.async {
        self.hasAccessibilityPermission = currentPermission
        print("Accessibility permission changed to: \(currentPermission)")
      }
    }
  }

  private func checkNotificationPermission() {
    UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
      let hasPermission = settings.authorizationStatus == .authorized

      DispatchQueue.main.async {
        // Only update if the permission status has changed
        if hasPermission != self?.hasNotificationPermission {
          self?.hasNotificationPermission = hasPermission
          print("Notification permission changed to: \(hasPermission)")
        }
      }
    }
  }

  private func openAccessibilitySettings() {
    guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
      return
    }
    NSWorkspace.shared.open(url)

    // No need for delayed checking - focus monitoring will handle it
    print("Opened accessibility settings")
  }
}
