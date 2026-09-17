import Common
import Foundation
@testable import Service
import Testing

@Suite(.serialized)
final class LockHistoryStoreTests {
  private let suiteName: String
  private let defaults: UserDefaults

  init() {
    suiteName = "LockHistoryStoreTests.\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suiteName)!
  }

  private func withCleanDefaults(_ body: () throws -> Void) rethrows {
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }
    try body()
  }

  @Test
  func freshStoreLoadsEmptyHistory() {
    withCleanDefaults {
      let store = LockHistoryStore(userDefaults: defaults, storageKey: "history")
      #expect(store.load() == [])
    }
  }

  @Test
  func savedEntriesLoadBack() throws {
    try withCleanDefaults {
      let entries = [
        LockHistoryEntry(
          startedAt: Date(timeIntervalSinceReferenceDate: 10_000),
          endedAt: Date(timeIntervalSinceReferenceDate: 10_090),
          reason: .gesture
        ),
        LockHistoryEntry(
          startedAt: Date(timeIntervalSinceReferenceDate: 10_200),
          endedAt: Date(timeIntervalSinceReferenceDate: 10_260),
          reason: .autoUnlock
        ),
      ]
      let store = LockHistoryStore(userDefaults: defaults, storageKey: "history")

      try store.save(entries)

      let reloaded = LockHistoryStore(userDefaults: defaults, storageKey: "history")
      #expect(reloaded.load() == entries)
    }
  }

  @Test
  func corruptPayloadLoadsEmptyInsteadOfCrashing() {
    withCleanDefaults {
      defaults.set(Data("not-json".utf8), forKey: "history")

      let store = LockHistoryStore(userDefaults: defaults, storageKey: "history")
      #expect(store.load() == [])
    }
  }
}
