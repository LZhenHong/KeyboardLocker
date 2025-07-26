import AppKit
import Foundation

/// Handles URL scheme requests for keyboard control operations
class URLCommandHandler {
  /// Supported URL commands
  enum URLCommand: String, CaseIterable {
    case lock
    case unlock
    case toggle
    case status

    var localizedDescription: String {
      switch self {
      case .lock:
        return LocalizationKey.actionLock.localized
      case .unlock:
        return LocalizationKey.actionUnlock.localized
      case .toggle:
        return "Toggle keyboard lock state" // No UI display, no need for i18n
      case .status:
        return "Get keyboard lock status" // No UI display, no need for i18n
      }
    }
  }

  /// Response status for URL commands
  enum CommandResponse {
    case success(String)
    case error(String)

    var message: String {
      switch self {
      case let .success(message):
        return message
      case let .error(error):
        return error
      }
    }

    var isSuccess: Bool {
      switch self {
      case .success:
        return true
      case .error:
        return false
      }
    }
  }

  static let shared = URLCommandHandler()

  private weak var keyboardLockManager: KeyboardLockManaging?
  private let notificationManager: NotificationManaging

  private init(notificationManager: NotificationManaging = NotificationManager.shared) {
    self.notificationManager = notificationManager
  }

  /// Set the keyboard lock manager reference
  /// - Parameter manager: The keyboard lock manager instance
  func setKeyboardLockManager(_ manager: KeyboardLockManaging) {
    keyboardLockManager = manager
  }

  /// Process incoming URL and execute the appropriate command
  /// - Parameter url: The URL to process
  /// - Returns: Command response indicating success or failure
  func handleURL(_ url: URL) -> CommandResponse {
    print("📱 Processing URL: \(url)")

    // Validate URL scheme
    guard url.scheme == "keyboardlocker" else {
      let error = LocalizationKey.urlErrorInvalidScheme.localized
      print("❌ Invalid URL scheme: \(url.scheme ?? "nil")")
      return .error(error)
    }

    // Extract command from URL host
    guard let host = url.host else {
      let error = LocalizationKey.urlErrorMissingCommand.localized
      print("❌ Missing command in URL")
      return .error(error)
    }

    // Parse command
    guard let command = URLCommand(rawValue: host.lowercased()) else {
      let supportedCommands = URLCommand.allCases.map { $0.rawValue }.joined(separator: ", ")
      let error = LocalizationKey.urlErrorUnknownCommand.localized(host, supportedCommands)
      print("❌ Unknown command: \(host)")
      return .error(error)
    }

    // Execute command
    return executeCommand(command)
  }

  /// Execute the specified URL command
  /// - Parameter command: The command to execute
  /// - Returns: Command response
  private func executeCommand(_ command: URLCommand) -> CommandResponse {
    guard let manager = keyboardLockManager else {
      let error = LocalizationKey.urlErrorManagerUnavailable.localized
      print("❌ Keyboard lock manager not available")
      return .error(error)
    }

    print("🎯 Executing command: \(command.rawValue)")

    switch command {
    case .lock:
      return executeLockCommand(manager)
    case .unlock:
      return executeUnlockCommand(manager)
    case .toggle:
      return executeToggleCommand(manager)
    case .status:
      return executeStatusCommand(manager)
    }
  }

  /// Execute lock command
  private func executeLockCommand(_ manager: KeyboardLockManaging) -> CommandResponse {
    if manager.isLocked {
      let message = LocalizationKey.statusLocked.localized
      print("ℹ️ Keyboard already locked")
      return .success(message)
    }

    manager.lockKeyboard()

    // Verify lock was successful
    if manager.isLocked {
      let message = LocalizationKey.notificationKeyboardLocked.localized
      print("🔒 Keyboard locked successfully")
      return .success(message)
    } else {
      let error = LocalizationKey.urlResponseLockFailed.localized
      print("❌ Failed to lock keyboard")
      return .error(error)
    }
  }

  /// Execute unlock command
  private func executeUnlockCommand(_ manager: KeyboardLockManaging) -> CommandResponse {
    if !manager.isLocked {
      let message = LocalizationKey.statusUnlocked.localized
      print("ℹ️ Keyboard already unlocked")
      return .success(message)
    }

    manager.unlockKeyboard()

    // Verify unlock was successful
    if !manager.isLocked {
      let message = LocalizationKey.notificationKeyboardUnlocked.localized
      print("🔓 Keyboard unlocked successfully")
      return .success(message)
    } else {
      let error = LocalizationKey.urlResponseUnlockFailed.localized
      print("❌ Failed to unlock keyboard")
      return .error(error)
    }
  }

  /// Execute toggle command
  private func executeToggleCommand(_ manager: KeyboardLockManaging) -> CommandResponse {
    let wasLocked = manager.isLocked

    if wasLocked {
      return executeUnlockCommand(manager)
    } else {
      return executeLockCommand(manager)
    }
  }

  /// Execute status command
  private func executeStatusCommand(_ manager: KeyboardLockManaging) -> CommandResponse {
    let statusText =
      manager.isLocked
        ? LocalizationKey.statusLocked.localized
        : LocalizationKey.statusUnlocked.localized

    print("📊 Current status: \(manager.isLocked ? "locked" : "unlocked")")
    return .success(statusText)
  }

  /// Show user feedback for URL command execution
  /// - Parameter response: The command response to display
  func showUserFeedback(for response: CommandResponse) {
    DispatchQueue.main.async {
      print("💬 User feedback: \(response.message)")

      // Send notification to user about the URL command result
      self.sendNotification(
        title: LocalizationKey.appTitle.localized,
        body: response.message,
        isError: !response.isSuccess
      )
    }
  }

  /// Send notification to user using NotificationManager
  /// - Parameters:
  ///   - title: Notification title
  ///   - body: Notification body message
  ///   - isError: Whether this is an error notification
  private func sendNotification(title: String, body: String, isError: Bool = false) {
    notificationManager.sendNotification(title: title, body: body, isError: isError)
  }
}

/// Extension to provide convenience methods for testing
extension URLCommandHandler {
  /// Test URL creation helper
  static func createTestURL(for command: URLCommand) -> URL? {
    return URL(string: "keyboardlocker://\(command.rawValue)")
  }

  /// Get all supported commands for documentation
  static func getSupportedCommands() -> [String] {
    return URLCommand.allCases.map { "keyboardlocker://\($0.rawValue)" }
  }
}
