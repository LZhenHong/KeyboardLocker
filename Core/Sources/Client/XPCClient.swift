import Common
import Foundation

public enum XPCClientError: Error {
  case serviceUnavailable
}

/// XPC client for communicating with the KeyboardLocker agent service.
public enum XPCClient {
  // MARK: - One-off Operations

  /// Queries the current lock state from the agent.
  public static func status(reply: @escaping (Bool, Error?) -> Void) {
    executeOneOff(
      onError: { reply(false, $0) },
      operation: { service, invalidate in
        service.status { isLocked, error in
          reply(isLocked, error)
          invalidate()
        }
      }
    )
  }

  /// Queries whether the agent has Accessibility permission.
  public static func accessibilityStatus(reply: @escaping (Bool) -> Void) {
    executeOneOff(
      onError: { _ in reply(false) },
      operation: { service, invalidate in
        service.accessibilityStatus { granted in
          reply(granted)
          invalidate()
        }
      }
    )
  }

  /// Force unlock (one-off operation).
  public static func unlock(reply: @escaping (Error?) -> Void) {
    executeOneOff(
      onError: { reply($0) },
      operation: { service, invalidate in
        service.unlockKeyboard { error in
          reply(error)
          invalidate()
        }
      }
    )
  }

  // MARK: - Session Management

  /// Creates a persistent lock session.
  public static func startLockSession() -> LockSessionController {
    LockSessionController(onStateChange: nil)
  }

  /// Creates a persistent lock session with state change notifications.
  public static func startLockSession(
    onStateChange: @escaping (Bool) -> Void
  ) -> LockSessionController {
    LockSessionController(onStateChange: onStateChange)
  }

  // MARK: - Private

  private static func executeOneOff(
    onError: @escaping (Error) -> Void,
    operation: @escaping (KeyboardLockerServiceProtocol, _ invalidate: @escaping () -> Void) -> Void
  ) {
    let connection = makeClientConnection()
    let service = connection.remoteObjectProxyWithErrorHandler { error in
      onError(error)
      connection.invalidate()
    } as? KeyboardLockerServiceProtocol

    guard let service else {
      onError(XPCClientError.serviceUnavailable)
      connection.invalidate()
      return
    }

    operation(service) { connection.invalidate() }
  }

  private static func makeClientConnection() -> NSXPCConnection {
    let connection = NSXPCConnection(machServiceName: SharedConstants.machServiceName)
    connection.remoteObjectInterface = NSXPCInterface(with: KeyboardLockerServiceProtocol.self)
    connection.resume()
    return connection
  }
}

// MARK: - Lock Session Controller

/// Manages a persistent XPC connection for lock/unlock operations.
public final class LockSessionController {
  private let connection: NSXPCConnection
  private let service: KeyboardLockerServiceProtocol?
  private var observerToken: ObserverToken?

  fileprivate init(onStateChange: ((Bool) -> Void)?) {
    connection = NSXPCConnection(machServiceName: SharedConstants.machServiceName)
    connection.remoteObjectInterface = NSXPCInterface(with: KeyboardLockerServiceProtocol.self)
    connection.resume()
    service = connection.remoteObjectProxyWithErrorHandler { _ in } as? KeyboardLockerServiceProtocol

    if let onStateChange {
      observerToken = LockStateSubscriber.subscribe(onStateChange)
    }
  }

  deinit {
    connection.invalidate()
  }

  public func lock(reply: @escaping (Error?) -> Void) {
    withService(reply: reply) { $0.lockKeyboard(reply: reply) }
  }

  public func unlock(reply: @escaping (Error?) -> Void) {
    withService(reply: reply) { $0.unlockKeyboard(reply: reply) }
  }

  private func withService(
    reply: @escaping (Error?) -> Void,
    operation: (KeyboardLockerServiceProtocol) -> Void
  ) {
    guard let service else {
      reply(XPCClientError.serviceUnavailable)
      return
    }
    operation(service)
  }
}
