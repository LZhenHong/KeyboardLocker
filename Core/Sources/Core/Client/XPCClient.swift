import Foundation

public class XPCClient {
  public static let shared = XPCClient()

  private init() {}

  private func createConnection() -> NSXPCConnection {
    let connection = NSXPCConnection(machServiceName: SharedConstants.machServiceName, options: [])
    connection.remoteObjectInterface = NSXPCInterface(with: KeyboardLockerServiceProtocol.self)
    connection.resume()
    return connection
  }

  private func executeRemoteCall(
    onError: @escaping (Error) -> Void,
    operation: @escaping (KeyboardLockerServiceProtocol, NSXPCConnection) -> Void
  ) {
    let connection = createConnection()
    guard let service = connection.remoteObjectProxyWithErrorHandler({ error in
      onError(error)
    }) as? KeyboardLockerServiceProtocol else {
      return
    }
    operation(service, connection)
  }

  /// Requests the agent to lock keyboard and mouse input
  /// - Parameter reply: Completion handler called with nil on success, or error if agent unavailable or permission denied
  public func lock(reply: @escaping (Error?) -> Void) {
    executeRemoteCall(onError: reply) { service, connection in
      service.lockKeyboard { error in
        reply(error)
        connection.invalidate()
      }
    }
  }

  /// Requests the agent to unlock keyboard and mouse input
  /// - Parameter reply: Completion handler called with nil on success, or error if agent unavailable
  public func unlock(reply: @escaping (Error?) -> Void) {
    executeRemoteCall(onError: reply) { service, connection in
      service.unlockKeyboard { error in
        reply(error)
        connection.invalidate()
      }
    }
  }

  /// Queries the current lock state from the agent
  /// - Parameter reply: Completion handler called with (isLocked, error) tuple
  public func status(reply: @escaping (Bool, Error?) -> Void) {
    executeRemoteCall(onError: { error in reply(false, error) }) { service, connection in
      service.status { isLocked, error in
        reply(isLocked, error)
        connection.invalidate()
      }
    }
  }

  /// Queries whether the agent process is trusted for Accessibility APIs
  /// - Parameter reply: Completion handler called with Boolean status
  public func accessibilityStatus(reply: @escaping (Bool) -> Void) {
    executeRemoteCall(onError: { _ in reply(false) }) { service, connection in
      service.accessibilityStatus { granted in
        reply(granted)
        connection.invalidate()
      }
    }
  }
}
