import Foundation

// MARK: - IPC Commands

/// Commands that can be sent from CLI tool to main app
public enum IPCCommand: String, Codable, CaseIterable {
  case lock
  case unlock
  case toggle
  case status
  case quit

  public var description: String {
    switch self {
    case .lock:
      return "Lock the keyboard"
    case .unlock:
      return "Unlock the keyboard"
    case .toggle:
      return "Toggle keyboard lock status"
    case .status:
      return "Get current keyboard lock status"
    case .quit:
      return "Quit the main application"
    }
  }
}

// MARK: - IPC Response

/// Response structure for IPC communication
public struct IPCResponse: Codable {
  public let success: Bool
  public let message: String
  public let data: [String: String]?
  public let timestamp: Date

  public init(success: Bool, message: String, data: [String: String]? = nil) {
    self.success = success
    self.message = message
    self.data = data
    timestamp = Date()
  }

  /// Convenience initializer for success responses
  public static func success(_ message: String, data: [String: String]? = nil) -> IPCResponse {
    return IPCResponse(success: true, message: message, data: data)
  }

  /// Convenience initializer for error responses
  public static func error(_ message: String) -> IPCResponse {
    return IPCResponse(success: false, message: message, data: nil)
  }
}

// MARK: - Error Types

/// Errors that can occur in Core operations
public enum CoreError: Error, LocalizedError {
  case accessibilityPermissionDenied
  case eventTapCreationFailed
  case ipcConnectionFailed
  case invalidCommand
  case mainAppNotRunning
  case alreadyLocked
  case notLocked

  public var errorDescription: String? {
    switch self {
    case .accessibilityPermissionDenied:
      return "Accessibility permission is required to control keyboard input"
    case .eventTapCreationFailed:
      return "Failed to create event tap for keyboard monitoring"
    case .ipcConnectionFailed:
      return "Failed to connect to main application"
    case .invalidCommand:
      return "Invalid command provided"
    case .mainAppNotRunning:
      return "Main application is not running"
    case .alreadyLocked:
      return "Keyboard is already locked"
    case .notLocked:
      return "Keyboard is not currently locked"
    }
  }
}

// MARK: - Constants

/// Shared constants used across the application
public enum CoreConstants {
  /// IPC service name for XPC communication
  public static let ipcServiceName = "com.keyboardlocker.ipc"

  /// Main app bundle identifier
  public static let mainAppBundleID = "com.keyboardlocker.app"

  /// Default unlock key combination (Cmd + Option + L)
  public static let defaultUnlockKeyCode: UInt16 = 37 // 'L' key

  /// Timeout for IPC connections (in seconds)
  public static let ipcTimeout: TimeInterval = 5.0

  /// Auto-lock timer intervals (in minutes)
  public enum AutoLockInterval: Int, CaseIterable {
    case never = 0
    case fifteen = 15
    case thirty = 30
    case sixty = 60

    public var description: String {
      switch self {
      case .never:
        return "Never"
      case .fifteen:
        return "15 minutes"
      case .thirty:
        return "30 minutes"
      case .sixty:
        return "1 hour"
      }
    }

    public var timeInterval: TimeInterval {
      return TimeInterval(rawValue * 60)
    }
  }
}

// MARK: - Lock Status

/// Current status of the keyboard lock
public struct LockStatus: Codable {
  public let isLocked: Bool
  public let lockedAt: Date?
  public let autoLockEnabled: Bool
  public let autoLockInterval: Int // minutes, 0 for never

  public init(
    isLocked: Bool,
    lockedAt: Date? = nil,
    autoLockEnabled: Bool = false,
    autoLockInterval: Int = 0
  ) {
    self.isLocked = isLocked
    self.lockedAt = lockedAt
    self.autoLockEnabled = autoLockEnabled
    self.autoLockInterval = autoLockInterval
  }

  /// Convert to dictionary for IPC data
  public func toDictionary() -> [String: String] {
    var dict: [String: String] = [
      "locked": isLocked ? "true" : "false",
      "autoLockEnabled": autoLockEnabled ? "true" : "false",
      "autoLockInterval": "\(autoLockInterval)",
    ]

    if let lockedAt = lockedAt {
      let formatter = ISO8601DateFormatter()
      dict["lockedAt"] = formatter.string(from: lockedAt)
    }

    return dict
  }
}
