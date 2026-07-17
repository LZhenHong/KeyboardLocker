import Foundation

enum KlockStatusOutput: Equatable {
  case humanReadable
  case json

  func render(isLocked: Bool) -> String {
    switch self {
    case .humanReadable:
      isLocked ? "Locked" : "Unlocked"

    case .json:
      "{\"locked\":\(isLocked ? "true" : "false")}"
    }
  }
}
