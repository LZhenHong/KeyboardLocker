import Client
import Foundation

enum KlockStatusOutput: Equatable {
  case humanReadable
  case json
  case snapshot

  func render(isLocked: Bool) -> String {
    switch self {
    case .humanReadable:
      isLocked ? "Locked" : "Unlocked"

    case .json:
      "{\"locked\":\(isLocked ? "true" : "false")}"

    case .snapshot:
      preconditionFailure("snapshot output renders from the full LockStatusSnapshot")
    }
  }

  /// The `--snapshot` payload is a separate, richer contract: `--json` stays byte-stable.
  /// Keys are emitted in alphabetical order and dates as ISO-8601 in GMT (absent dates are
  /// `null`) so automation can compare output verbatim.
  static func render(snapshot: LockStatusSnapshot) -> String {
    let object: [String: Any] = [
      "autoUnlockTargetDate": snapshot.autoUnlockTargetDate.map(iso8601String) ?? NSNull(),
      "locked": snapshot.isLocked,
      "startedAt": snapshot.startedAt.map(iso8601String) ?? NSNull(),
      "unlockHotkey": snapshot.settings.unlockHotkey.displayString,
    ]
    // Only strings, a Boolean, and NSNull reach this point, so serialization cannot fail.
    let data = try! JSONSerialization.data(
      withJSONObject: object,
      options: [.sortedKeys, .withoutEscapingSlashes]
    )
    return String(decoding: data, as: UTF8.self)
  }

  private static func iso8601String(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    formatter.timeZone = TimeZone(identifier: "GMT")
    return formatter.string(from: date)
  }
}
