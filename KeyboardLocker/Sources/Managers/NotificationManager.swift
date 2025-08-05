import Foundation
import UserNotifications

/// Centralized notification management for the app
class NotificationManager: ObservableObject {
  // MARK: - Published Properties

  @Published var isAuthorized = false

  // MARK: - Private Properties

  private let notificationCenter = UNUserNotificationCenter.current()

  // MARK: - Notification Categories

  enum NotificationCategory: String, CaseIterable {
    case keyboardStatus = "KEYBOARD_STATUS"
    case urlCommand = "URL_COMMAND"
    case urlError = "URL_ERROR"
    case general = "GENERAL"

    var identifier: String {
      rawValue
    }
  }

  // MARK: - Notification Types

  enum NotificationType {
    case keyboardLocked
    case keyboardUnlocked
    case urlCommandSuccess(String)
    case urlCommandError(String)
    case general(title: String, body: String)

    var title: String {
      switch self {
      case .keyboardLocked:
        LocalizationKey.notificationKeyboardLocked.localized
      case .keyboardUnlocked:
        LocalizationKey.notificationKeyboardUnlocked.localized
      case .urlCommandSuccess:
        LocalizationKey.notificationUrlCommand.localized
      case .urlCommandError:
        LocalizationKey.notificationError.localized
      case let .general(title, _):
        title
      }
    }

    var body: String {
      switch self {
      case .keyboardLocked:
        LocalizationKey.notificationLockedMessage.localized
      case .keyboardUnlocked:
        LocalizationKey.notificationUnlockedMessage.localized
      case let .urlCommandSuccess(message):
        message
      case let .urlCommandError(message):
        message
      case let .general(_, body):
        body
      }
    }

    var category: NotificationCategory {
      switch self {
      case .keyboardLocked, .keyboardUnlocked:
        .keyboardStatus
      case .urlCommandSuccess:
        .urlCommand
      case .urlCommandError:
        .urlError
      case .general:
        .general
      }
    }

    var sound: UNNotificationSound {
      switch self {
      case .urlCommandError:
        .defaultCritical
      default:
        .default
      }
    }
  }

  // MARK: - NotificationManaging Protocol Conformance

  /// Send a notification of the specified type if enabled
  /// - Parameters:
  ///   - type: The type of notification to send
  ///   - showNotifications: Whether notifications are enabled
  func sendNotificationIfEnabled(_ type: NotificationType, showNotifications: Bool) {
    guard shouldSendNotification(showNotifications: showNotifications) else {
      print("🔔 Notification skipped - disabled in settings or not authorized")
      return
    }
    sendNotification(type)
  }

  /// Send a custom notification
  /// - Parameters:
  ///   - title: Notification title
  ///   - body: Notification body
  ///   - isError: Whether this is an error notification
  func sendNotification(title: String, body: String, isError _: Bool) {
    sendNotification(.general(title: title, body: body))
  }

  // MARK: - Initialization

  /// Create a new NotificationManager instance
  init() {
    setupNotificationCategories()
    checkAuthorizationStatus()
  }

  // MARK: - Public Methods

  /// Request notification permission from user
  /// - Parameter completion: Completion handler with authorization result
  func requestAuthorization(completion: @escaping (Bool, Error?) -> Void = { _, _ in }) {
    notificationCenter.requestAuthorization(options: [.alert, .sound, .badge]) {
      [weak self] granted, error in
      DispatchQueue.main.async {
        self?.isAuthorized = granted
        completion(granted, error)

        if let error {
          print("❌ Failed to request notification permission: \(error.localizedDescription)")
        } else {
          print("✅ Notification permission \(granted ? "granted" : "denied")")
        }
      }
    }
  }

  /// Check current authorization status
  func checkAuthorizationStatus() {
    notificationCenter.getNotificationSettings { [weak self] settings in
      DispatchQueue.main.async {
        let isAuthorized = settings.authorizationStatus == .authorized

        // Only update if status changed to avoid unnecessary UI updates
        if self?.isAuthorized != isAuthorized {
          self?.isAuthorized = isAuthorized
          print(
            "📱 Notification authorization status: \(isAuthorized ? "authorized" : "not authorized")"
          )
        }
      }
    }
  }

  /// Send a notification of the specified type
  /// - Parameters:
  ///   - type: The type of notification to send
  ///   - completion: Optional completion handler
  func sendNotification(
    _ type: NotificationType,
    completion: @escaping (Error?) -> Void = { _ in }
  ) {
    // Check if notifications are authorized
    guard isAuthorized else {
      print("🔔 Notification not sent - not authorized")
      completion(NotificationError.notAuthorized)
      return
    }

    let content = UNMutableNotificationContent()
    content.title = type.title
    content.body = type.body
    content.sound = type.sound
    content.categoryIdentifier = type.category.identifier

    // Add custom user info for tracking
    content.userInfo = [
      "notificationType": String(describing: type),
      "timestamp": Date().timeIntervalSince1970,
    ]

    let request = UNNotificationRequest(
      identifier: generateNotificationIdentifier(for: type),
      content: content,
      trigger: nil // Immediate delivery
    )

    notificationCenter.add(request) { error in
      DispatchQueue.main.async {
        if let error {
          print("❌ Failed to send notification: \(error.localizedDescription)")
        } else {
          print("✅ Notification sent: \(type.title)")
        }
        completion(error)
      }
    }
  }

  /// Remove all pending notifications
  func removeAllPendingNotifications() {
    notificationCenter.removeAllPendingNotificationRequests()
    print("🗑️ All pending notifications removed")
  }

  /// Remove all delivered notifications
  func removeAllDeliveredNotifications() {
    notificationCenter.removeAllDeliveredNotifications()
    print("🗑️ All delivered notifications removed")
  }

  /// Remove notifications by category
  /// - Parameter category: The category to remove
  func removeNotifications(for category: NotificationCategory) {
    notificationCenter.getPendingNotificationRequests { [weak self] requests in
      let identifiersToRemove =
        requests
          .filter { $0.content.categoryIdentifier == category.identifier }
          .map(\.identifier)

      self?.notificationCenter.removePendingNotificationRequests(
        withIdentifiers: identifiersToRemove)
      print(
        "🗑️ Removed \(identifiersToRemove.count) pending notifications for category: \(category.identifier)"
      )
    }

    notificationCenter.getDeliveredNotifications { [weak self] notifications in
      let identifiersToRemove =
        notifications
          .filter { $0.request.content.categoryIdentifier == category.identifier }
          .map(\.request.identifier)

      self?.notificationCenter.removeDeliveredNotifications(withIdentifiers: identifiersToRemove)
      print(
        "🗑️ Removed \(identifiersToRemove.count) delivered notifications for category: \(category.identifier)"
      )
    }
  }

  // MARK: - Convenience Methods

  /// Send keyboard locked notification
  func notifyKeyboardLocked() {
    sendNotification(.keyboardLocked)
  }

  /// Send keyboard unlocked notification
  func notifyKeyboardUnlocked() {
    sendNotification(.keyboardUnlocked)
  }

  /// Send URL command success notification
  /// - Parameter message: Success message to display
  func notifyURLCommandSuccess(_ message: String) {
    sendNotification(.urlCommandSuccess(message))
  }

  /// Send URL command error notification
  /// - Parameter message: Error message to display
  func notifyURLCommandError(_ message: String) {
    sendNotification(.urlCommandError(message))
  }

  // MARK: - Private Methods

  private func setupNotificationCategories() {
    let categories = NotificationCategory.allCases.map { category in
      UNNotificationCategory(
        identifier: category.identifier,
        actions: [],
        intentIdentifiers: [],
        options: []
      )
    }

    notificationCenter.setNotificationCategories(Set(categories))
    print("📋 Notification categories configured: \(categories.map(\.identifier))")
  }

  private func generateNotificationIdentifier(for type: NotificationType) -> String {
    let timestamp = Date().timeIntervalSince1970
    switch type {
    case .keyboardLocked:
      return "keyboard_locked_\(timestamp)"
    case .keyboardUnlocked:
      return "keyboard_unlocked_\(timestamp)"
    case .urlCommandSuccess:
      return "url_success_\(timestamp)"
    case .urlCommandError:
      return "url_error_\(timestamp)"
    case .general:
      return "general_\(timestamp)"
    }
  }
}

// MARK: - Error Types

enum NotificationError: Error, LocalizedError {
  case notAuthorized
  case invalidContent
  case systemError(Error)

  var errorDescription: String? {
    switch self {
    case .notAuthorized:
      "Notifications not authorized"
    case .invalidContent:
      "Invalid notification content"
    case let .systemError(error):
      "System error: \(error.localizedDescription)"
    }
  }
}

// MARK: - Extension for Settings Integration

extension NotificationManager {
  /// Check if notifications should be shown based on user settings
  /// - Parameter showNotifications: User's notification preference
  /// - Returns: Whether notifications should be sent
  func shouldSendNotification(showNotifications: Bool) -> Bool {
    showNotifications && isAuthorized
  }

  /// Send notification conditionally based on user settings
  /// - Parameters:
  ///   - type: Notification type to send
  ///   - showNotifications: User's notification preference
  ///   - completion: Optional completion handler
  func sendNotificationIfEnabled(
    _ type: NotificationType,
    showNotifications: Bool,
    completion: @escaping (Error?) -> Void = { _ in }
  ) {
    guard shouldSendNotification(showNotifications: showNotifications) else {
      print("🔔 Notification skipped - disabled in settings or not authorized")
      completion(nil)
      return
    }

    sendNotification(type, completion: completion)
  }
}
