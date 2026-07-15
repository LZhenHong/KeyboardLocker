import Common
import Foundation
import os

public enum XPCClientError: Error, LocalizedError {
  case serviceUnavailable

  public var errorDescription: String? {
    switch self {
    case .serviceUnavailable:
      "The KeyboardLocker agent is not reachable."
    }
  }
}

/// Async client for the KeyboardLocker Agent.
///
/// Every operation is a **stateless one-off call** to the single global lock owned by the Agent —
/// there is no client-owned "session". State is observed via `LockStateSubscriber`, never inferred
/// from whether a call succeeded.
///
/// A single connection is reused and lazily recreated after invalidation, so callers survive the
/// Agent being relaunched on demand by `launchd`.
public final class XPCClient: @unchecked Sendable {
  public static let shared = XPCClient()

  private let lock = OSAllocatedUnfairLock()
  private var connection: NSXPCConnection?

  private init() {}

  // MARK: - Operations

  public func lock() async throws {
    try await withProxy { service, resume in
      service.lockKeyboard { resume($0) }
    }
  }

  public func unlock() async throws {
    try await withProxy { service, resume in
      service.unlockKeyboard { resume($0) }
    }
  }

  /// Current global lock state.
  public func status() async throws -> Bool {
    try await withProxyReturning { service, resume in
      service.status { isLocked, error in resume(isLocked, error) }
    }
  }

  /// The Agent's current settings, falling back to `.default` if the Agent can't provide them.
  public func currentSettings() async throws -> KeyboardLockerSettings {
    let data: Data? = try await withProxyReturning { service, resume in
      service.currentSettings { resume($0, nil) }
    }
    return KeyboardLockerSettings.decodedFromXPC(data)
  }

  // MARK: - Connection Management

  private func currentConnection() -> NSXPCConnection {
    lock.lock()
    defer { lock.unlock() }

    if let connection {
      return connection
    }

    let connection = NSXPCConnection(machServiceName: SharedConstants.machServiceName)
    connection.remoteObjectInterface = NSXPCInterface(with: KeyboardLockerServiceProtocol.self)

    // Drop the cached connection on teardown so the next call transparently reconnects.
    let clear: @Sendable () -> Void = { [weak self] in self?.clearConnection() }
    connection.invalidationHandler = clear
    connection.interruptionHandler = clear

    connection.resume()
    self.connection = connection
    return connection
  }

  private func clearConnection() {
    lock.lock()
    connection = nil
    lock.unlock()
  }

  /// Bridges a reply-based XPC call returning only an optional `Error` into async/throwing form.
  /// The continuation is resumed exactly once — whether by the reply, the proxy error handler,
  /// or a missing proxy — so a dead Agent throws rather than hanging forever.
  private func withProxy(
    _ body: @escaping (KeyboardLockerServiceProtocol, _ resume: @escaping (Error?) -> Void) -> Void
  ) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      let once = ResumeOnce()
      let connection = currentConnection()

      let proxy = connection.remoteObjectProxyWithErrorHandler { error in
        once.run { continuation.resume(throwing: error) }
      }

      guard let service = proxy as? KeyboardLockerServiceProtocol else {
        once.run { continuation.resume(throwing: XPCClientError.serviceUnavailable) }
        return
      }

      body(service) { error in
        once.run {
          if let error {
            continuation.resume(throwing: error)
          } else {
            continuation.resume()
          }
        }
      }
    }
  }

  /// Same as `withProxy`, for calls that return a value plus an optional `Error`.
  private func withProxyReturning<T>(
    _ body: @escaping (KeyboardLockerServiceProtocol, _ resume: @escaping (T, Error?) -> Void) -> Void
  ) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
      let once = ResumeOnce()
      let connection = currentConnection()

      let proxy = connection.remoteObjectProxyWithErrorHandler { error in
        once.run { continuation.resume(throwing: error) }
      }

      guard let service = proxy as? KeyboardLockerServiceProtocol else {
        once.run { continuation.resume(throwing: XPCClientError.serviceUnavailable) }
        return
      }

      body(service) { value, error in
        once.run {
          if let error {
            continuation.resume(throwing: error)
          } else {
            continuation.resume(returning: value)
          }
        }
      }
    }
  }
}

/// Guarantees a continuation is resumed at most once across the reply and error-handler races.
private final class ResumeOnce: @unchecked Sendable {
  private let lock = OSAllocatedUnfairLock()
  private var done = false

  func run(_ block: () -> Void) {
    lock.lock()
    let shouldRun = !done
    done = true
    lock.unlock()
    if shouldRun {
      block()
    }
  }
}
