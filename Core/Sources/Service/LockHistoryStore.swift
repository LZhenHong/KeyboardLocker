import Foundation
import os

/// The persistence surface `LockHistoryRecorder` writes through. Seamed so `ServiceTests` can
/// substitute a recording fake instead of driving `UserDefaults.standard`.
protocol LockHistoryPersisting {
  func load() -> [LockHistoryEntry]
  func save(_ entries: [LockHistoryEntry]) throws
}

extension LockHistoryStore: LockHistoryPersisting {}

/// Persists lock history to `UserDefaults`.
///
/// Lives in `Service` for the same reason as the settings store: the Agent is the single owner
/// of history, and no wrapper may keep its own copy.
final class LockHistoryStore {
  private static let logger = Logger(
    subsystem: SharedConstants.machServiceName,
    category: "LockHistoryStore"
  )

  private let userDefaults: UserDefaults
  private let storageKey: String
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  init(
    userDefaults: UserDefaults = .standard,
    storageKey: String = "keyboardlocker.lock-history"
  ) {
    self.userDefaults = userDefaults
    self.storageKey = storageKey
  }

  /// Loads the persisted entries, or an empty list when none exist.
  ///
  /// A present-but-undecodable payload means the stored bytes no longer match the schema.
  /// History is presentation-only, so the Agent continues with an empty list — but the
  /// corruption is always logged instead of being silently swallowed.
  func load() -> [LockHistoryEntry] {
    guard let data = userDefaults.data(forKey: storageKey) else {
      return []
    }
    do {
      return try decoder.decode([LockHistoryEntry].self, from: data)
    } catch {
      Self.logger.error(
        "Stored lock history is undecodable; starting empty: \(error.localizedDescription)"
      )
      return []
    }
  }

  func save(_ entries: [LockHistoryEntry]) throws {
    let data = try encoder.encode(entries)
    userDefaults.set(data, forKey: storageKey)
  }
}
