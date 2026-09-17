import Foundation

/// Why the most recent lock generation ended, paired with the authoritative time it ended.
///
/// The record survives later locks, so a currently locked keyboard can still report how the
/// previous one ended; it is nil until this Agent generation observes its first unlock.
/// Wrappers use it for presentation and diagnostics only — it never gates what any entry point
/// may do next.
public struct UnlockRecord: Codable, Equatable, Sendable {
  /// Forward-tolerant wire union — intentionally not an enum, for the same reason as
  /// `ServiceCapability`: a reason introduced by a newer Agent must decode losslessly on an
  /// older client instead of failing the whole snapshot payload.
  public struct Reason: Codable, Equatable, Hashable, RawRepresentable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
      self.rawValue = rawValue
    }

    public init(from decoder: any Decoder) throws {
      let container = try decoder.singleValueContainer()
      rawValue = try container.decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
      var container = encoder.singleValueContainer()
      try container.encode(rawValue)
    }

    /// A wrapper, the notification's Unlock Now action, or agent replacement requested it.
    public static let explicit = Self(rawValue: "explicit")
    /// The configured unlock hotkey or the interactive Ctrl+C gesture ended the lock.
    public static let gesture = Self(rawValue: "gesture")
    /// The auto-unlock timer reached its deadline.
    public static let autoUnlock = Self(rawValue: "autoUnlock")
    /// Focus deactivation conditionally released the lock generation it created.
    public static let focusFilter = Self(rawValue: "focusFilter")
    /// The event tap could not be re-enabled, so the lock failed open.
    public static let eventTapFailure = Self(rawValue: "eventTapFailure")
    /// The user typed the configured unlock phrase on the locked keyboard.
    public static let phrase = Self(rawValue: "phrase")
  }

  public let reason: Reason
  public let date: Date

  public init(reason: Reason, date: Date) {
    self.reason = reason
    self.date = date
  }
}

public extension UnlockRecord.Reason {
  /// Short English phrase for popover and diagnostics presentation.
  var displayName: String {
    switch self {
    case .explicit:
      "Manual"
    case .gesture:
      "Hotkey"
    case .autoUnlock:
      "Auto-unlock"
    case .focusFilter:
      "Focus"
    case .eventTapFailure:
      "Tap failure"
    case .phrase:
      "Phrase"
    default:
      // A reason from a newer Agent stays presentable instead of failing the decode.
      "Unknown"
    }
  }
}

/// One authoritative, point-in-time view of the global keyboard lock.
///
/// Wrappers may cache this value for presentation, but the Agent remains the source of truth.
/// Format 1 may only gain backward-compatible fields; incompatible semantics require a new XPC
/// capability instead of reinterpreting this payload.
public struct LockStatusSnapshot: Codable, Equatable, Sendable {
  public static let currentFormatVersion = 1

  public let formatVersion: Int
  public let capturedAt: Date
  public let isLocked: Bool
  public let startedAt: Date?
  public let autoUnlockTargetDate: Date?
  public let settings: KeyboardLockerSettings
  /// Additive format-1 field: payloads written before `UnlockRecord` existed omit the key and
  /// decode as nil.
  public let lastUnlock: UnlockRecord?

  public init(
    formatVersion: Int = Self.currentFormatVersion,
    capturedAt: Date,
    isLocked: Bool,
    startedAt: Date?,
    autoUnlockTargetDate: Date?,
    settings: KeyboardLockerSettings,
    lastUnlock: UnlockRecord? = nil
  ) {
    self.formatVersion = formatVersion
    self.capturedAt = capturedAt
    self.isLocked = isLocked
    self.startedAt = startedAt
    self.autoUnlockTargetDate = autoUnlockTargetDate
    self.settings = settings
    self.lastUnlock = lastUnlock
  }

  fileprivate var hasConsistentLockState: Bool {
    if isLocked {
      return startedAt != nil
    }
    return startedAt == nil && autoUnlockTargetDate == nil
  }
}

public enum LockStatusSnapshotCodingError: Error, Equatable, LocalizedError {
  case invalidPayload
  case missingPayload
  case payloadTooLarge
  case unsupportedFormat(Int)

  public var errorDescription: String? {
    switch self {
    case .invalidPayload:
      "The KeyboardLocker agent returned an invalid lock status snapshot."
    case .missingPayload:
      "The KeyboardLocker agent returned no lock status snapshot."
    case .payloadTooLarge:
      "The KeyboardLocker agent returned an oversized lock status snapshot."
    case let .unsupportedFormat(version):
      "The KeyboardLocker agent returned unsupported lock status format \(version)."
    }
  }
}

// MARK: - XPC Serialization

public extension LockStatusSnapshot {
  static let maximumEncodedSize = 32 * 1024

  func encodedForXPC() throws -> Data {
    guard formatVersion == Self.currentFormatVersion, hasConsistentLockState else {
      throw LockStatusSnapshotCodingError.invalidPayload
    }

    let data = try JSONEncoder().encode(self)
    guard data.count <= Self.maximumEncodedSize else {
      throw LockStatusSnapshotCodingError.payloadTooLarge
    }
    return data
  }

  static func decodedFromXPC(_ data: Data?) throws -> LockStatusSnapshot {
    guard let data else {
      throw LockStatusSnapshotCodingError.missingPayload
    }
    guard data.count <= maximumEncodedSize else {
      throw LockStatusSnapshotCodingError.payloadTooLarge
    }

    let snapshot: LockStatusSnapshot
    do {
      snapshot = try JSONDecoder().decode(LockStatusSnapshot.self, from: data)
    } catch {
      throw LockStatusSnapshotCodingError.invalidPayload
    }

    guard snapshot.formatVersion == currentFormatVersion else {
      throw LockStatusSnapshotCodingError.unsupportedFormat(snapshot.formatVersion)
    }
    guard snapshot.hasConsistentLockState else {
      throw LockStatusSnapshotCodingError.invalidPayload
    }
    return snapshot
  }
}
