import Common
import Foundation
@testable import Service
import Testing

@MainActor
@Suite(.serialized)
final class LockHistoryRecorderTests {
  @Test
  func recordAppendsAndPersists() throws {
    let store = FakeHistoryStore()
    let recorder = LockHistoryRecorder(store: store)
    let entry = makeEntry(offset: 0)

    recorder.record(entry)

    #expect(recorder.entries == [entry])
    #expect(try #require(store.savedSnapshots.last) == [entry])
  }

  @Test
  func recordTrimsOldestBeyondTheRetentionLimit() {
    let store = FakeHistoryStore()
    let recorder = LockHistoryRecorder(store: store)

    for index in 0 ..< LockHistory.retentionLimit + 5 {
      recorder.record(makeEntry(offset: TimeInterval(index)))
    }

    #expect(recorder.entries.count == LockHistory.retentionLimit)
    // The five oldest generations were dropped, oldest-first order preserved.
    #expect(recorder.entries.first == makeEntry(offset: 5))
    // Every record attempted a persist.
    #expect(store.savedSnapshots.count == LockHistory.retentionLimit + 5)
  }

  @Test
  func persistenceFailureKeepsTheInMemoryEntry() {
    let store = FakeHistoryStore()
    store.saveError = TestError.saveFailed
    let recorder = LockHistoryRecorder(store: store)
    let entry = makeEntry(offset: 0)

    // A failed write must never propagate into the unlock path that produced the entry.
    recorder.record(entry)

    #expect(recorder.entries == [entry])
  }

  @Test
  func initLoadsPersistedEntries() {
    let persisted = [makeEntry(offset: 0), makeEntry(offset: 100)]
    let store = FakeHistoryStore()
    store.loaded = persisted

    let recorder = LockHistoryRecorder(store: store)

    #expect(recorder.entries == persisted)
  }

  private func makeEntry(offset: TimeInterval) -> LockHistoryEntry {
    let start = Date(timeIntervalSinceReferenceDate: 10_000 + offset)
    return LockHistoryEntry(
      startedAt: start,
      endedAt: start.addingTimeInterval(60),
      reason: .explicit
    )
  }
}

private enum TestError: Error {
  case saveFailed
}

private final class FakeHistoryStore: LockHistoryPersisting {
  var loaded: [LockHistoryEntry] = []
  var saveError: Error?
  private(set) var savedSnapshots: [[LockHistoryEntry]?] = []

  func load() -> [LockHistoryEntry] {
    loaded
  }

  func save(_ entries: [LockHistoryEntry]) throws {
    if let saveError {
      savedSnapshots.append(nil)
      throw saveError
    }
    savedSnapshots.append(entries)
  }
}
