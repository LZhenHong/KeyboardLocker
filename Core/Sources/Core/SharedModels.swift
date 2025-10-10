import Foundation

// MARK: - Error Types

/// Keyboard lock operation errors
public enum KeyboardLockError: Error, LocalizedError {
  case permissionDenied
  case eventTapCreationFailed
  case runLoopSourceCreationFailed
  case alreadyLocked
  case notLocked
  case invalidConfiguration
  case systemError(String)

  public var errorDescription: String? {
    switch self {
    case .permissionDenied:
      "Accessibility permission is required to control keyboard input"
    case .eventTapCreationFailed:
      "Failed to create event tap for keyboard monitoring"
    case .runLoopSourceCreationFailed:
      "Failed to create run loop source"
    case .alreadyLocked:
      "Keyboard is already locked"
    case .notLocked:
      "Keyboard is not currently locked"
    case .invalidConfiguration:
      "Invalid configuration provided"
    case let .systemError(message):
      "System error: \(message)"
    }
  }

  public var failureReason: String? {
    errorDescription
  }
}

// MARK: - IPC Commands

/// Commands that can be sent from CLI tool to main app
public enum IPCCommand: String, Codable, CaseIterable {
  case lock
  case unlock
  case toggle
  case status

  public var description: String {
    switch self {
    case .lock:
      "Lock the keyboard"
    case .unlock:
      "Unlock the keyboard"
    case .toggle:
      "Toggle keyboard lock status"
    case .status:
      "Get current keyboard lock status"
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
    IPCResponse(success: true, message: message, data: data)
  }

  /// Convenience initializer for error responses
  public static func error(_ message: String) -> IPCResponse {
    IPCResponse(success: false, message: message, data: nil)
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
      "Accessibility permission is required to control keyboard input"
    case .eventTapCreationFailed:
      "Failed to create event tap for keyboard monitoring"
    case .ipcConnectionFailed:
      "Failed to connect to main application"
    case .invalidCommand:
      "Invalid command provided"
    case .mainAppNotRunning:
      "Main application is not running"
    case .alreadyLocked:
      "Keyboard is already locked"
    case .notLocked:
      "Keyboard is not currently locked"
    }
  }
}

// MARK: - Constants

/// Shared constants used across the application
public enum CoreConstants {
  /// IPC service name for XPC communication
  public static let ipcServiceName = "io.lzhlovesjyq.keyboardlocker.ipc"

  /// Main app bundle identifier
  public static let mainAppBundleID = "io.lzhlovesjyq.KeyboardLocker"

  /// Default unlock key combination (Cmd + Option + L)
  public static let defaultUnlockKeyCode: UInt16 = 37 // 'L' key

  /// Timeout for IPC connections (in seconds)
  public static let ipcTimeout: TimeInterval = 5.0
}

// MARK: - Lock Status

/// Current status of the keyboard lock
public struct LockStatus: Codable {
  public let isLocked: Bool
  public let lockedAt: Date?

  public init(
    isLocked: Bool,
    lockedAt: Date? = nil
  ) {
    self.isLocked = isLocked
    self.lockedAt = lockedAt
  }

  /// Convert to dictionary for IPC data
  public func toDictionary() -> [String: String] {
    var dict: [String: String] = ["locked": isLocked ? "true" : "false"]

    if let lockedAt {
      let formatter = ISO8601DateFormatter()
      dict["lockedAt"] = formatter.string(from: lockedAt)
    }

    return dict
  }
}
