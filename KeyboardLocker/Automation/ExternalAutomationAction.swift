import Foundation

nonisolated enum ExternalAutomationAction: Equatable, Sendable {
  case lock
  case unlock
  case status
}

nonisolated enum ExternalAutomationRequest: Equatable, Sendable {
  case action(ExternalAutomationAction)
  case failure(ExternalAutomationFailure)
}

nonisolated enum ExternalAutomationSource: String, Equatable, Sendable {
  case service = "Service"
  case urlScheme = "URL"
}

nonisolated enum NSErrorMessageFormatter {
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

nonisolated struct ExternalAutomationFailure: Equatable, Sendable {
  let message: String

  init(message: String) {
    self.message = message
  }

  init(error: Error) {
    self.init(message: NSErrorMessageFormatter.message(for: error))
  }
}
