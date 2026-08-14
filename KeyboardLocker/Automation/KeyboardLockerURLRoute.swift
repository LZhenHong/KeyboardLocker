import Foundation

nonisolated struct KeyboardLockerURLRoute: Equatable, Sendable {
  static let scheme = "keyboardlocker"

  let action: ExternalAutomationAction

  init(url: URL) throws {
    guard let components = URLComponents(
      url: url,
      resolvingAgainstBaseURL: false
    ),
      components.scheme?.caseInsensitiveCompare(Self.scheme) == .orderedSame,
      components.user == nil,
      components.password == nil,
      components.port == nil,
      components.percentEncodedPath.isEmpty,
      components.percentEncodedQuery == nil,
      components.percentEncodedFragment == nil,
      let host = components.percentEncodedHost?.lowercased()
    else {
      throw KeyboardLockerURLRouteError.invalidURL
    }

    action = switch host {
    case "lock":
      .lock
    case "unlock":
      .unlock
    case "status":
      .status
    default:
      throw KeyboardLockerURLRouteError.invalidURL
    }
  }

  static func requests(for urls: [URL]) -> [ExternalAutomationRequest] {
    urls.map { url in
      do {
        return try .action(Self(url: url).action)
      } catch {
        return .failure(ExternalAutomationFailure(error: error))
      }
    }
  }
}

nonisolated enum KeyboardLockerURLRouteError: LocalizedError, Equatable, Sendable {
  case invalidURL

  var errorDescription: String? {
    "KeyboardLocker rejected an invalid automation URL."
  }

  var recoverySuggestion: String? {
    "Use keyboardlocker://lock, keyboardlocker://unlock, or keyboardlocker://status without additional URL components."
  }
}
