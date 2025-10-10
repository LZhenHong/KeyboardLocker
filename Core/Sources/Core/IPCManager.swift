import AppKit

// MARK: - XPC Service Protocol

/// Protocol for XPC communication between main app and CLI tool
@objc protocol IPCServiceProtocol {
  func executeCommand(_ command: String, withReply reply: @escaping ([String: Any]) -> Void)
}

// MARK: - IPC Manager

/// Manager for Inter-Process Communication between main app and CLI tool
public class IPCManager: NSObject {
  public static let shared = IPCManager()

  // MARK: - Properties

  private let serviceName = CoreConstants.ipcServiceName
  private var listener: NSXPCListener?

  private var isServerRunning: Bool {
    listener != nil
  }

  // MARK: - Initialization

  override private init() {
    super.init()
  }

  // MARK: - Server Methods (Main App)

  /// Start IPC server in main app
  public func startServer() {
    guard !isServerRunning else {
      print("IPC Server already running")
      return
    }

    listener = NSXPCListener(machServiceName: serviceName)
    listener?.delegate = self
    listener?.resume()

    print("🚀 IPC Server started on service: \(serviceName)")
  }

  /// Stop IPC server
  public func stopServer() {
    listener?.invalidate()
    listener = nil
    print("🛑 IPC Server stopped")
  }

  // MARK: - Client Methods (CLI Tool)

  /// Send command to main app from CLI tool
  /// - Parameters:
  ///   - command: The command to execute
  ///   - timeout: Timeout in seconds
  /// - Returns: Response from the main app
  public func sendCommand(
    _ command: IPCCommand,
    timeout _: TimeInterval = CoreConstants.ipcTimeout
  ) async throws -> IPCResponse {
    try await withCheckedThrowingContinuation { continuation in
      // Check if main app is running first
      guard isMainAppRunning() else {
        continuation.resume(throwing: CoreError.mainAppNotRunning)
        return
      }

      let connection = NSXPCConnection(machServiceName: serviceName)
      connection.remoteObjectInterface = NSXPCInterface(with: IPCServiceProtocol.self)

      connection.interruptionHandler = {
        continuation.resume(throwing: CoreError.ipcConnectionFailed)
      }

      connection.invalidationHandler = {
        // Connection will be cleaned up automatically
      }

      connection.resume()

      guard let service = connection.remoteObjectProxy as? IPCServiceProtocol else {
        connection.invalidate()
        continuation.resume(throwing: CoreError.ipcConnectionFailed)
        return
      }

      service.executeCommand(command.rawValue) { [weak self] responseDict in
        defer { connection.invalidate() }

        guard let self else {
          continuation.resume(throwing: CoreError.ipcConnectionFailed)
          return
        }

        let response = parseResponse(from: responseDict)
        continuation.resume(returning: response)
      }
    }
  }

  /// Check if main app is running
  private func isMainAppRunning() -> Bool {
    let runningApps = NSWorkspace.shared.runningApplications
    return runningApps.contains { app in
      app.bundleIdentifier == CoreConstants.mainAppBundleID
    }
  }

  // MARK: - Helper Methods

  /// Parse response dictionary into IPCResponse
  private func parseResponse(from dict: [String: Any]) -> IPCResponse {
    let success = dict["success"] as? Bool ?? false
    let message = dict["message"] as? String ?? "Unknown response"
    let data = dict["data"] as? [String: String]

    return IPCResponse(success: success, message: message, data: data)
  }

  /// Convert IPCResponse to dictionary for XPC
  func responseToObject(_ response: IPCResponse) -> [String: Any] {
    var obj: [String: Any] = [
      "success": response.success,
      "message": response.message,
      "timestamp": response.timestamp.timeIntervalSince1970,
    ]

    if let data = response.data {
      obj["data"] = data
    }

    return obj
  }
}

// MARK: - XPC Listener Delegate

extension IPCManager: NSXPCListenerDelegate {
  public func listener(_: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
    newConnection.exportedInterface = NSXPCInterface(with: IPCServiceProtocol.self)
    newConnection.exportedObject = IPCServiceHandler()
    newConnection.resume()
    return true
  }
}

// MARK: - IPC Service Handler

/// Handles incoming IPC commands from CLI tool
public class IPCServiceHandler: NSObject, IPCServiceProtocol {
  public func executeCommand(_ command: String, withReply reply: @escaping ([String: Any]) -> Void) {
    guard let ipcCommand = IPCCommand(rawValue: command) else {
      let response = IPCResponse.error("Unknown command: \(command)")
      reply(IPCManager.shared.responseToObject(response))
      return
    }

    // Execute command on main queue
    DispatchQueue.main.async {
      let response = self.handleCommand(ipcCommand)
      reply(IPCManager.shared.responseToObject(response))
    }
  }

  /// Handle the actual command execution
  private func handleCommand(_ command: IPCCommand) -> IPCResponse {
    let lockCore = KeyboardLockCore.shared

    do {
      switch command {
      case .lock:
        try lockCore.lockKeyboard()
        return IPCResponse.success("Keyboard locked successfully")

      case .unlock:
        lockCore.unlockKeyboard()
        return IPCResponse.success("Keyboard unlocked successfully")

      case .toggle:
        lockCore.toggleLock()
        let statusMessage = lockCore.isLocked ? "locked" : "unlocked"
        return IPCResponse.success("Keyboard \(statusMessage) successfully")

      case .status:
        let status = LockStatus(
          isLocked: lockCore.isLocked,
          lockedAt: lockCore.lockedAt
        )
        return IPCResponse.success(
          "Keyboard is currently \(status.isLocked ? "locked" : "unlocked")",
          data: status.toDictionary()
        )
      }
    } catch let error as CoreError {
      return IPCResponse.error(error.localizedDescription)
    } catch {
      return IPCResponse.error("Unexpected error: \(error.localizedDescription)")
    }
  }
}
