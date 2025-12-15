import Common
import Foundation

/// Configures XPC connections on the server (Agent) side.
public enum XPCServerConnection {
  /// Configures an incoming connection on the Agent side.
  /// Sets up the exported interface and object for client calls.
  public static func configure(
    _ connection: NSXPCConnection,
    exportedService: KeyboardLockerServiceProtocol
  ) {
    connection.exportedInterface = NSXPCInterface(with: KeyboardLockerServiceProtocol.self)
    connection.exportedObject = exportedService
    connection.resume()
  }
}
