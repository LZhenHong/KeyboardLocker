import Foundation

// MARK: - Shared Constants

public enum SharedConstants {
  /// Mach service name for XPC communication between App/Agent/CLI
  public static let machServiceName = "io.lzhlovesjyq.keyboardlocker.agent"

  /// Default unlock key code for 'L' key (⌃⌘L)
  public static let defaultUnlockKeyCode: UInt16 = 37

  /// Bundle identifiers allowed to talk to the agent's Mach service
  public static let authorizedClientBundleIdentifiers: Set<String> = [
    "io.lzhlovesjyq.keyboardlocker",
    "io.lzhlovesjyq.keyboardlocker.klock",
  ]
}

// MARK: - Notification Names

/// Shared notification identifiers for cross-process communication.
public enum NotificationNames {
  /// Notification name for lock state changes.
  /// Used by Darwin (lightweight, no payload) and Distributed (with payload) notifications.
  public static let stateChanged = "io.lzhlovesjyq.keyboardlocker.state.changed"
}

// MARK: - XPC Service Protocol

/// XPC service protocol for keyboard locking operations.
/// Implemented by Agent, consumed by App/CLI clients.
@objc(KeyboardLockerServiceProtocol)
public protocol KeyboardLockerServiceProtocol {
  // MARK: Keyboard Locking Methods

  func lockKeyboard(reply: @escaping (Error?) -> Void)
  func unlockKeyboard(reply: @escaping (Error?) -> Void)
  func status(reply: @escaping (Bool, Error?) -> Void)

  // MARK: Accessibility Permission Methods

  func accessibilityStatus(reply: @escaping (Bool) -> Void)
}
