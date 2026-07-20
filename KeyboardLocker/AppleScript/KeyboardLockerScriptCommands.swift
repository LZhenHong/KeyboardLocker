import Client
import Foundation

nonisolated class AsyncKeyboardLockerScriptCommand: NSScriptCommand {
  override final nonisolated func performDefaultImplementation() -> Any? {
    suspendExecution()
    let commandReference = SuspendedScriptCommandReference(self)

    // Cocoa scripting requires the handler to return before a suspended command is resumed.
    DispatchQueue.main.async {
      Task { @MainActor in
        let command = commandReference.value
        do {
          let result = try await type(of: command).perform(using: LiveAgentClient())
          command.resumeExecution(withResult: result)
        } catch {
          command.scriptErrorNumber = AppleScriptErrorPresentation.errorNumber(for: error)
          command.scriptErrorString = AppleScriptErrorPresentation.message(for: error)
          command.resumeExecution(withResult: nil)
        }
      }
    }

    return nil
  }

  @MainActor
  class func perform(using _: any AgentLockActionServing) async throws -> Any? {
    preconditionFailure("Subclasses must implement their Agent operation.")
  }
}

/// Cocoa permits a suspended command to resume on another thread. This box only carries the
/// retained command into a main-actor task, where all post-suspension access occurs.
private final nonisolated class SuspendedScriptCommandReference: @unchecked Sendable {
  let value: AsyncKeyboardLockerScriptCommand

  init(_ value: AsyncKeyboardLockerScriptCommand) {
    self.value = value
  }
}

@objc(LockKeyboardScriptCommand)
final nonisolated class LockKeyboardScriptCommand: AsyncKeyboardLockerScriptCommand {
  @MainActor
  override class func perform(using client: any AgentLockActionServing) async throws -> Any? {
    try await client.lock()
    return nil
  }
}

@objc(UnlockKeyboardScriptCommand)
final nonisolated class UnlockKeyboardScriptCommand: AsyncKeyboardLockerScriptCommand {
  @MainActor
  override class func perform(using client: any AgentLockActionServing) async throws -> Any? {
    try await client.unlock()
    return nil
  }
}

@objc(GetKeyboardLockStatusScriptCommand)
final nonisolated class GetKeyboardLockStatusScriptCommand: AsyncKeyboardLockerScriptCommand {
  @MainActor
  override class func perform(using client: any AgentLockActionServing) async throws -> Any? {
    try await NSNumber(value: client.status())
  }
}

@MainActor
enum AppleScriptErrorPresentation {
  static func errorNumber(for error: Error) -> Int {
    if let clientError = error as? XPCClientError,
       case .timedOut = clientError {
      return Int(errAETimeout)
    }
    return Int(errAEEventFailed)
  }

  static func message(for error: Error) -> String {
    let error = error as NSError
    guard let recoverySuggestion = error.localizedRecoverySuggestion,
          !recoverySuggestion.isEmpty
    else {
      return error.localizedDescription
    }
    return "\(error.localizedDescription) \(recoverySuggestion)"
  }
}
