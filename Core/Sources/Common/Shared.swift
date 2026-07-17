import Foundation

// MARK: - Shared Constants

public enum SharedConstants {
  /// Mach service name for XPC communication between the Agent and authorized wrappers.
  public static let machServiceName = "io.lzhlovesjyq.keyboardlocker.agent"

  private static let appBundleIdentifier = "io.lzhlovesjyq.keyboardlocker"

  /// Bundle identifier of the launchd-managed Agent bundled with the App.
  public static let agentBundleIdentifier = "io.lzhlovesjyq.keyboardlocker.agent"

  private static let commandLineToolBundleIdentifier = "io.lzhlovesjyq.keyboardlocker.klock"

  /// One WidgetKit extension process hosts both the status Widget and macOS Control.
  private static let widgetKitExtensionBundleIdentifier = "io.lzhlovesjyq.keyboardlocker.widgets"

  /// Default unlock key code for 'L' key (⌃⌘L)
  public static let defaultUnlockKeyCode: UInt16 = 37

  /// Exact code-signing identifiers allowed to talk to the Agent's Mach service.
  public static let authorizedClientBundleIdentifiers: Set<String> = [
    appBundleIdentifier,
    commandLineToolBundleIdentifier,
    widgetKitExtensionBundleIdentifier,
  ]
}

// MARK: - Lock Requests

/// Whether one atomic lock request created the global lock or found it already active.
///
/// This describes a state transition, not client ownership. The Agent still owns one global lock,
/// and any authorized wrapper may explicitly unlock it.
public enum LockRequestOutcome: Equatable, Sendable {
  case acquired
  case alreadyLocked
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

  /// Requests a lock that treats Control-C as an additional unlock gesture only when this call
  /// atomically creates the global lock. `didAcquireLock` is false for a strict duplicate no-op.
  func lockKeyboardInteractively(
    reply: @escaping (_ didAcquireLock: Bool, _ error: Error?) -> Void
  )

  /// Applies the Focus Filter's desired state. Disabling releases only a lock generation that
  /// the Focus Filter itself created; it never unlocks a pre-existing or subsequently claimed
  /// global lock.
  func setFocusFilterLockEnabled(
    _ enabled: Bool,
    reply: @escaping (Error?) -> Void
  )

  func unlockKeyboard(reply: @escaping (Error?) -> Void)
  func status(reply: @escaping (Bool, Error?) -> Void)

  /// Returns one authoritative point-in-time lock snapshot as JSON-encoded
  /// `LockStatusSnapshot`. This is additive; legacy clients continue using `status`.
  func lockStatusSnapshot(reply: @escaping (Data?, Error?) -> Void)

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
