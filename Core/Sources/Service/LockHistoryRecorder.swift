import Foundation
import os

/// Agent-side owner of the bounded lock history.
///
/// Fed by the engine's lock-history hook on every completed generation. Persistence failures
/// are logged and swallowed on purpose: history is presentation-only, and a full disk or a
/// corrupt write must never break the unlock path that produced the entry.
@MainActor
final class LockHistoryRecorder {
  /// How many generations are retained, oldest dropped first. Bounded so the persisted payload
  /// and the wire payload stay small no matter how long the Agent runs.
  static let maximumEntries = LockHistory.retentionLimit

  private static let logger = Logger(
    subsystem: SharedConstants.machServiceName,
    category: "LockHistoryRecorder"
  )

  private let store: any LockHistoryPersisting
  private(set) var entries: [LockHistoryEntry]

  init(store: any LockHistoryPersisting) {
    self.store = store
    entries = store.load()
  }

  func record(_ entry: LockHistoryEntry) {
    entries.append(entry)
    if entries.count > Self.maximumEntries {
      entries.removeFirst(entries.count - Self.maximumEntries)
    }
    do {
      try store.save(entries)
    } catch {
      Self.logger.error("Could not persist lock history: \(error.localizedDescription)")
    }
  }
}
