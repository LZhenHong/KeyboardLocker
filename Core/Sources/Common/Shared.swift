import Foundation

// MARK: - Shared Constants

public enum SharedConstants {
  /// Mach service name for XPC communication between App/Agent/CLI
  public static let machServiceName = "io.lzhlovesjyq.keyboardlocker.agent"

  /// Bundle identifier of the launchd-managed Agent bundled with the App.
  public static let agentBundleIdentifier = "io.lzhlovesjyq.keyboardlocker.agent"

  /// Default unlock key code for 'L' key (⌃⌘L)
  public static let defaultUnlockKeyCode: UInt16 = 37

  /// Exact code-signing identifiers allowed to talk to the Agent's Mach service.
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
  // MARK: Bootstrap Methods

  /// Returns a versioned process descriptor before clients invoke capability-gated methods.
  func serviceDescriptor(reply: @escaping (Data?, Error?) -> Void)

  // MARK: Keyboard Locking Methods

  func lockKeyboard(reply: @escaping (Error?) -> Void)
  func unlockKeyboard(reply: @escaping (Error?) -> Void)
  func status(reply: @escaping (Bool, Error?) -> Void)

  /// Atomically enters a short-lived fail-safe drain and optionally unlocks before returning its
  /// exclusive ownership ticket.
  func prepareForReplacement(
    unlockIfNeeded: Bool,
    expectedAgentInstanceID: UUID,
    reply: @escaping (Data?, Error?) -> Void
  )

  /// Commits a prepared drain immediately before Service Management unregister is submitted.
  /// A committed drain cannot expire or be cancelled; only old-Agent process exit clears it.
  func commitReplacement(
    ticket: Data,
    reply: @escaping (Error?) -> Void
  )

  /// Returns the phase of the exact replacement ticket without mutating the transaction.
  func replacementStatus(
    ticket: Data,
    reply: @escaping (Data?, Error?) -> Void
  )

  /// Cancels a still-prepared drain before Service Management unregister is submitted.
  func cancelReplacementPreparation(
    ticket: Data,
    reply: @escaping (Error?) -> Void
  )

  // MARK: Accessibility Methods

  /// Returns whether the Agent process currently has Accessibility permission.
  func hasAccessibilityPermission(reply: @escaping (Bool) -> Void)

  /// Asks the Agent process to trigger the system Accessibility permission prompt.
  /// A successful reply means the prompt request was sent, not that access was granted.
  func requestAccessibilityPermission(reply: @escaping (Error?) -> Void)

  // MARK: Settings Methods

  /// Returns the Agent's current settings as JSON-encoded `KeyboardLockerSettings`.
  /// Retained for compatibility with protocol 1.1 clients.
  func currentSettings(reply: @escaping (Data?) -> Void)

  /// Returns the Agent's current settings and reports serialization failures explicitly.
  func currentSettingsWithError(reply: @escaping (Data?, Error?) -> Void)
}
