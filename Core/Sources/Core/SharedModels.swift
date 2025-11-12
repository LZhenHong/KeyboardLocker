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

// MARK: - Constants

/// Shared constants used across the application
public enum CoreConstants {
  /// Main app bundle identifier
  public static let mainAppBundleID = "io.lzhlovesjyq.KeyboardLocker"

  /// Default unlock key combination (Cmd + Option + L)
  public static let defaultUnlockKeyCode: UInt16 = 37 // 'L' key
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
}
