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
  }

  // MARK: - Public Methods

  /// Check all permission statuses and update published properties
  func checkAllPermissions() {
    checkAccessibilityPermission()
    checkNotificationPermission()
  }

  /// Request accessibility permission by opening system settings
  func requestAccessibilityPermission() {
    openAccessibilitySettings()
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

  private func checkAccessibilityPermission() {
    hasAccessibilityPermission = AXIsProcessTrusted()
  }

  private func checkNotificationPermission() {
    UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
      DispatchQueue.main.async {
        self?.hasNotificationPermission = settings.authorizationStatus == .authorized
      }
    }
  }

  private func openAccessibilitySettings() {
    guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
      return
    }
    NSWorkspace.shared.open(url)

    // Check permission status after a delay to allow user to grant permission
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
      self.checkAllPermissions()
    }
  }
}
