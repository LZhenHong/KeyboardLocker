import AppKit
import Foundation

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
  private var isServerRunning = false

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
    isServerRunning = true

    print("🚀 IPC Server started on service: \(serviceName)")
  }

  /// Stop IPC server
  public func stopServer() {
    listener?.invalidate()
    listener = nil
    isServerRunning = false
    print("🛑 IPC Server stopped")
  }

  // MARK: - Client Methods (CLI Tool)

  /// Send command to main app from CLI tool
  /// - Parameters:
  ///   - command: The command to execute
  ///   - timeout: Timeout in seconds
  ///   - completion: Completion handler with response
  public func sendCommand(
    _ command: IPCCommand,
    timeout _: TimeInterval = CoreConstants.ipcTimeout,
    completion: @escaping (Result<IPCResponse, Error>) -> Void
  ) {
    // Check if main app is running first
    guard isMainAppRunning() else {
      completion(.failure(CoreError.mainAppNotRunning))
      return
    }

    let connection = NSXPCConnection(machServiceName: serviceName, options: [])
    connection.remoteObjectInterface = NSXPCInterface(with: IPCServiceProtocol.self)

    connection.interruptionHandler = {
      completion(.failure(CoreError.ipcConnectionFailed))
    }

    connection.invalidationHandler = {
      // Connection will be cleaned up automatically
    }

    connection.resume()

    guard let service = connection.remoteObjectProxy as? IPCServiceProtocol else {
      connection.invalidate()
      completion(.failure(CoreError.ipcConnectionFailed))
      return
    }

    service.executeCommand(command.rawValue) { responseDict in
      DispatchQueue.main.async {
        connection.invalidate()

        let response = self.parseResponse(from: responseDict)
        completion(.success(response))
      }
    }
  }

  /// Simplified async/await version for modern Swift
  @available(macOS 10.15, *)
  public func sendCommand(_ command: IPCCommand, timeout: TimeInterval = CoreConstants.ipcTimeout)
    async throws -> IPCResponse
  {
    return try await withCheckedThrowingContinuation { continuation in
      sendCommand(command, timeout: timeout) { result in
        continuation.resume(with: result)
      }
    }
  }

  /// Check if main app is running
  public func isMainAppRunning() -> Bool {
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
  func responseToDict(_ response: IPCResponse) -> [String: Any] {
    var dict: [String: Any] = [
      "success": response.success,
      "message": response.message,
      "timestamp": response.timestamp.timeIntervalSince1970,
    ]

    if let data = response.data {
      dict["data"] = data
    }

    return dict
  }
}

// MARK: - XPC Listener Delegate

extension IPCManager: NSXPCListenerDelegate {
  public func listener(_: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection)
    -> Bool
  {
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
      reply(IPCManager.shared.responseToDict(response))
      return
    }

    // Execute command on main queue
    DispatchQueue.main.async {
      let response = self.handleCommand(ipcCommand)
      reply(IPCManager.shared.responseToDict(response))
    }
  }

  /// Handle the actual command execution
  private func handleCommand(_ command: IPCCommand) -> IPCResponse {
    let lockCore = KeyboardLockCore.shared

    do {
      switch command {
      case .lock:
        if try lockCore.lockKeyboard() {
          return IPCResponse.success("Keyboard locked successfully")
        } else {
          return IPCResponse.error("Keyboard is already locked")
        }

      case .unlock:
        if lockCore.unlockKeyboard() {
          return IPCResponse.success("Keyboard unlocked successfully")
        } else {
          return IPCResponse.error("Keyboard is not locked")
        }

      case .toggle:
        let newStatus = try lockCore.toggleLock()
        let statusMessage = newStatus ? "locked" : "unlocked"
        return IPCResponse.success("Keyboard \(statusMessage) successfully")

      case .status:
        let status = lockCore.lockStatus
        return IPCResponse.success(
          "Keyboard is currently \(status.isLocked ? "locked" : "unlocked")",
          data: status.toDictionary()
        )

      case .quit:
        // Schedule app termination after sending response
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
          NSApplication.shared.terminate(nil)
        }
        return IPCResponse.success("Quitting application")
      }

    } catch let error as CoreError {
      return IPCResponse.error(error.localizedDescription)
    } catch {
      return IPCResponse.error("Unexpected error: \(error.localizedDescription)")
    }
  }
}

// MARK: - Extensions

public extension IPCManager {
  /// Convenience method to get status
  func getStatus(completion: @escaping (Result<LockStatus, Error>) -> Void) {
    sendCommand(.status) { result in
      switch result {
      case let .success(response):
        if response.success, let data = response.data {
          let isLocked = data["locked"] == "true"
          let autoLockEnabled = data["autoLockEnabled"] == "true"
          let autoLockInterval = Int(data["autoLockInterval"] ?? "0") ?? 0

          var lockedAt: Date?
          if let lockedAtString = data["lockedAt"] {
            let formatter = ISO8601DateFormatter()
            lockedAt = formatter.date(from: lockedAtString)
          }

          let status = LockStatus(
            isLocked: isLocked,
            lockedAt: lockedAt,
            autoLockEnabled: autoLockEnabled,
            autoLockInterval: autoLockInterval
          )
          completion(.success(status))
        } else {
          completion(.failure(CoreError.invalidCommand))
        }

      case let .failure(error):
        completion(.failure(error))
      }
    }
  }
}
