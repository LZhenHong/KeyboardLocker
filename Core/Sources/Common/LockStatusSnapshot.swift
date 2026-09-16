import Foundation

/// Why the most recent lock generation ended, paired with the authoritative time it ended.
///
/// The record survives later locks, so a currently locked keyboard can still report how the
/// previous one ended; it is nil until this Agent generation observes its first unlock.
/// Wrappers use it for presentation and diagnostics only — it never gates what any entry point
/// may do next.
public struct UnlockRecord: Codable, Equatable, Sendable {
  public enum Reason: String, Codable, Sendable {
    /// A wrapper, the notification's Unlock Now action, or agent replacement requested it.
    case explicit
    /// The configured unlock hotkey or the interactive Ctrl+C gesture ended the lock.
    case gesture
    /// The auto-unlock timer reached its deadline.
    case autoUnlock
    /// Focus deactivation conditionally released the lock generation it created.
    case focusFilter
    /// The event tap could not be re-enabled, so the lock failed open.
    case eventTapFailure
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
