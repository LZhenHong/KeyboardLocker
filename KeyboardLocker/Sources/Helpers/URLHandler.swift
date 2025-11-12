import AppKit

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
        LocalizationKey.actionLock.localized
      case .unlock:
        LocalizationKey.actionUnlock.localized
      case .toggle:
        "Toggle keyboard lock state" // No UI display, no need for i18n
      case .status:
        "Get keyboard lock status" // No UI display, no need for i18n
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
        message
      case let .error(error):
        error
      }
    }

    var isSuccess: Bool {
      switch self {
      case .success:
        true
      case .error:
        false
      }
    }
  }

  private weak var keyboardLockManager: KeyboardLockManager?
  private let notificationManager: NotificationManager

  /// Create URLCommandHandler with dependencies
  /// - Parameters:
  ///   - keyboardLockManager: Manager for keyboard operations
  ///   - notificationManager: Manager for notifications
  init(keyboardLockManager: KeyboardLockManager, notificationManager: NotificationManager) {
    self.keyboardLockManager = keyboardLockManager
    self.notificationManager = notificationManager
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
      let supportedCommands = URLCommand.allCases.map(\.rawValue).joined(separator: ", ")
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
  private func executeLockCommand(_ manager: KeyboardLockManager) -> CommandResponse {
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
  private func executeUnlockCommand(_ manager: KeyboardLockManager) -> CommandResponse {
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
  private func executeToggleCommand(_ manager: KeyboardLockManager) -> CommandResponse {
    let wasLocked = manager.isLocked

    if wasLocked {
      return executeUnlockCommand(manager)
    } else {
      return executeLockCommand(manager)
    }
  }

  /// Execute status command
  private func executeStatusCommand(_ manager: KeyboardLockManager) -> CommandResponse {
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

      self.notificationManager.sendNotification(
        title: LocalizationKey.appTitle.localized,
        body: response.message,
        isError: !response.isSuccess
      )
    }
  }
}
