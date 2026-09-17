import Foundation

/// One completed lock generation, recorded by the Agent at the moment it ended.
///
/// History is presentation and diagnostics only: like `UnlockRecord`, it never gates what any
/// entry point may do next. A generation cut short by Agent exit is not recorded — the process
/// died before there was an unlock to describe.
public struct LockHistoryEntry: Codable, Equatable, Sendable {
  public let startedAt: Date
  public let endedAt: Date
  /// How the generation ended. Forward-tolerant like `UnlockRecord.Reason` itself: a reason
  /// introduced by a newer Agent decodes losslessly on older clients.
  public let reason: UnlockRecord.Reason

  public init(startedAt: Date, endedAt: Date, reason: UnlockRecord.Reason) {
    self.startedAt = startedAt
    self.endedAt = endedAt
    self.reason = reason
  }

  /// Wall-clock length of the lock generation. Can be negative only through clock
  /// manipulation; consumers presenting durations clamp it instead of trusting the value.
  public var duration: TimeInterval {
    endedAt.timeIntervalSince(startedAt)
  }
}

/// Bounded, Agent-owned list of the most recent lock generations.
///
/// The Agent is the single source of truth (same ownership rule as settings): wrappers read it
/// through the capability-gated `lockHistory` selector and may cache it for presentation, but
/// never write or trim it. Aggregates — counts, durations, reason breakdowns — are derived by
/// consumers from these authoritative records, the same rule the snapshot applies to countdowns.
/// Format 1 may only gain backward-compatible fields.
public struct LockHistory: Codable, Equatable, Sendable {
  public static let currentFormatVersion = 1

  /// How many generations the Agent's recorder retains, oldest dropped first. Declared here so
  /// the Agent's trim policy and a wrapper's "keeps the N most recent locks" copy share one
  /// source of truth.
  public static let retentionLimit = 200

  public let formatVersion: Int
  /// Completed generations, oldest first. Bounded by the Agent's recorder; the encode path
  /// enforces the wire size cap regardless.
  public let entries: [LockHistoryEntry]

  public init(
    formatVersion: Int = Self.currentFormatVersion,
    entries: [LockHistoryEntry]
  ) {
    self.formatVersion = formatVersion
    self.entries = entries
  }
}

public enum LockHistoryCodingError: Error, Equatable, LocalizedError {
  case invalidPayload
  case missingPayload
  case payloadTooLarge
  case unsupportedFormat(Int)

  public var errorDescription: String? {
    switch self {
    case .invalidPayload:
      "The agent returned an invalid lock history."
    case .missingPayload:
      "The agent returned no lock history."
    case .payloadTooLarge:
      "The agent returned an oversized lock history."
    case let .unsupportedFormat(version):
      "The agent returned unsupported lock history format \(version)."
    }
  }
}

// MARK: - XPC Serialization

public extension LockHistory {
  static let maximumEncodedSize = 32 * 1024

  func encodedForXPC() throws -> Data {
    guard formatVersion == Self.currentFormatVersion else {
      throw LockHistoryCodingError.invalidPayload
    }

    let data = try JSONEncoder().encode(self)
    guard data.count <= Self.maximumEncodedSize else {
      throw LockHistoryCodingError.payloadTooLarge
    }
    return data
  }

  static func decodedFromXPC(_ data: Data?) throws -> LockHistory {
    guard let data else {
      throw LockHistoryCodingError.missingPayload
    }
    guard data.count <= maximumEncodedSize else {
      throw LockHistoryCodingError.payloadTooLarge
    }

    let history: LockHistory
    do {
      history = try JSONDecoder().decode(LockHistory.self, from: data)
    } catch {
      throw LockHistoryCodingError.invalidPayload
    }

    guard history.formatVersion == currentFormatVersion else {
      throw LockHistoryCodingError.unsupportedFormat(history.formatVersion)
    }
    return history
  }
}
