import Foundation

/// Factory for creating and managing application dependencies
/// This helps reduce coupling and makes testing easier
class DependencyFactory {
  /// Shared instance for application-wide dependency management
  static let shared = DependencyFactory()

  private init() {}

  // MARK: - Factory Methods

  /// Create a notification manager instance
  /// - Returns: NotificationManaging instance
  func makeNotificationManager() -> NotificationManaging {
    return NotificationManager.shared
  }

  /// Create a keyboard lock manager instance
  /// - Parameters:
  ///   - notificationManager: Optional notification manager, uses default if nil
  ///   - configuration: Optional configuration, uses shared if nil
  /// - Returns: KeyboardLockManaging instance
  func makeKeyboardLockManager(
    notificationManager: NotificationManaging? = nil,
    configuration: AppConfiguration? = nil
  ) -> KeyboardLockManaging {
    let notificationMgr = notificationManager ?? makeNotificationManager()
    let config = configuration ?? AppConfiguration.shared
    return KeyboardLockManager(notificationManager: notificationMgr, configuration: config)
  }

  /// Create a URL command handler instance
  /// - Parameter notificationManager: Optional notification manager, uses default if nil
  /// - Returns: URLCommandHandler instance
  func makeURLCommandHandler(
    notificationManager _: NotificationManaging? = nil
  ) -> URLCommandHandler {
    // Since URLCommandHandler uses a singleton pattern, we return the shared instance
    // In a more sophisticated dependency injection system, we might create new instances
    return URLCommandHandler.shared
  }

  /// Create a permission manager instance
  /// - Parameter notificationManager: Optional notification manager, uses default if nil
  /// - Returns: PermissionManager instance
  func makePermissionManager(
    notificationManager: NotificationManager? = nil
  ) -> PermissionManager {
    let notificationMgr: NotificationManager
    if let providedManager = notificationManager {
      notificationMgr = providedManager
    } else if let defaultManager = makeNotificationManager() as? NotificationManager {
      notificationMgr = defaultManager
    } else {
      // Fallback: create a new instance directly
      notificationMgr = NotificationManager.shared
    }
    return PermissionManager(notificationManager: notificationMgr)
  }
}

// MARK: - Testing Support

#if DEBUG
  extension DependencyFactory {
    /// Create a mock notification manager for testing
    /// - Returns: Mock NotificationManaging instance
    func makeMockNotificationManager() -> NotificationManaging {
      return MockNotificationManager()
    }

    /// Create a keyboard lock manager with mock dependencies for testing
    /// - Returns: KeyboardLockManaging instance with mock dependencies
    func makeMockKeyboardLockManager() -> KeyboardLockManaging {
      let mockNotificationManager = makeMockNotificationManager()
      return KeyboardLockManager(notificationManager: mockNotificationManager)
    }
  }

  /// Mock notification manager for testing purposes
  class MockNotificationManager: NotificationManaging {
    var sentNotifications: [(type: NotificationManager.NotificationType, showNotifications: Bool)] = []
    var customNotifications: [(title: String, body: String, isError: Bool)] = []

    // Implement the required protocol property
    var isAuthorized: Bool = true

    func sendNotificationIfEnabled(_ type: NotificationManager.NotificationType, showNotifications: Bool) {
      sentNotifications.append((type: type, showNotifications: showNotifications))
      print("Mock: Would send notification \(type) with showNotifications=\(showNotifications)")
    }

    func sendNotification(title: String, body: String, isError: Bool) {
      customNotifications.append((title: title, body: body, isError: isError))
      print("Mock: Would send custom notification - Title: \(title), Body: \(body), Error: \(isError)")
    }

    func requestAuthorization(completion: @escaping (Bool, Error?) -> Void) {
      print("Mock: Would request authorization")
      // Simulate success for testing
      completion(true, nil)
    }

    func checkAuthorizationStatus() {
      print("Mock: Would check authorization status")
    }
  }
#endif
