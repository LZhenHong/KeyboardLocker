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

  public func lock(reply: @escaping (Error?) -> Void) {
    let connection = createConnection()
    let service = connection.remoteObjectProxyWithErrorHandler { error in
      reply(error)
    } as? KeyboardLockerServiceProtocol

    service?.lockKeyboard(reply: { error in
      reply(error)
      connection.invalidate()
    })
  }

  public func unlock(reply: @escaping (Error?) -> Void) {
    let connection = createConnection()
    let service = connection.remoteObjectProxyWithErrorHandler { error in
      reply(error)
    } as? KeyboardLockerServiceProtocol

    service?.unlockKeyboard(reply: { error in
      reply(error)
      connection.invalidate()
    })
  }

  public func status(reply: @escaping (Bool, Error?) -> Void) {
    let connection = createConnection()
    let service = connection.remoteObjectProxyWithErrorHandler { error in
      reply(false, error)
    } as? KeyboardLockerServiceProtocol

    service?.status(reply: { isLocked, error in
      reply(isLocked, error)
      connection.invalidate()
    })
  }
}
