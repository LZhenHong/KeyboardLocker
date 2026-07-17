import Foundation

nonisolated enum ExternalAutomationAction: Equatable, Sendable {
  case lock
  case unlock
  case status
}

nonisolated enum ExternalAutomationSource: String, Equatable, Sendable {
  case service = "Service"
  case urlScheme = "URL"
}

nonisolated struct ExternalAutomationFailure: Equatable, Sendable {
  let message: String

  init(message: String) {
    self.message = message
  }

  init(error: Error) {
    let error = error as NSError
    guard let recoverySuggestion = error.localizedRecoverySuggestion,
          !recoverySuggestion.isEmpty
    else {
      self.init(message: error.localizedDescription)
      return
    }

    self.init(message: "\(error.localizedDescription) \(recoverySuggestion)")
  }
}
