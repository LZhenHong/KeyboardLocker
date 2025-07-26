import Foundation

// MARK: - Notification Manager Protocol

/// Protocol for notification management to reduce coupling
protocol NotificationManaging {
  var isAuthorized: Bool { get }

  /// Send a notification if notifications are enabled
  /// - Parameters:
  ///   - type: The type of notification to send
  ///   - showNotifications: Whether notifications are enabled
  func sendNotificationIfEnabled(_ type: NotificationManager.NotificationType, showNotifications: Bool)

  /// Send a custom notification
  /// - Parameters:
  ///   - title: Notification title
  ///   - body: Notification body
  ///   - isError: Whether this is an error notification
  func sendNotification(title: String, body: String, isError: Bool)

  /// Request authorization for notifications
  /// - Parameter completion: Completion handler with success status and optional error
  func requestAuthorization(completion: @escaping (Bool, Error?) -> Void)

  /// Check current authorization status
  func checkAuthorizationStatus()
}

// MARK: - Keyboard Lock Managing Protocol

/// Protocol for keyboard lock management to reduce coupling
protocol KeyboardLockManaging: AnyObject {
  var isLocked: Bool { get }

  func lockKeyboard()
  func unlockKeyboard()
  func toggleLock()
  func getLockDurationString() -> String?
  func forceCleanup()

  // Auto-lock management
  func startAutoLock()
  func stopAutoLock()
  func toggleAutoLock()
  func updateAutoLockSettings()
}

/// Enhanced protocol with result-based operations for better error handling
protocol KeyboardLockManagingAdvanced: KeyboardLockManaging {
  func lockKeyboard() -> KeyboardLockResult
  func unlockKeyboard() -> KeyboardLockResult
}

// MARK: - Operation Result

/// Result type for keyboard operations
enum KeyboardLockResult {
  case success
  case failure(KeyboardLockerError)

  var isSuccess: Bool {
    switch self {
    case .success:
      return true
    case .failure:
      return false
    }
  }

  var error: KeyboardLockerError? {
    switch self {
    case .success:
      return nil
    case let .failure(error):
      return error
    }
  }
}

// MARK: - Error Types

enum KeyboardLockerError: LocalizedError {
  case accessibilityPermissionDenied
  case eventTapCreationFailed
  case runLoopSourceCreationFailed
  case invalidEventType
  case managerNotAvailable

  var errorDescription: String? {
    switch self {
    case .accessibilityPermissionDenied:
      return "Accessibility permission not granted"
    case .eventTapCreationFailed:
      return "Failed to create event tap"
    case .runLoopSourceCreationFailed:
      return "Failed to create run loop source"
    case .invalidEventType:
      return "Invalid event type encountered"
    case .managerNotAvailable:
      return "Keyboard lock manager not available"
    }
  }
}
