import Foundation
import Testing

@Suite(.serialized)
struct SafetyCheckExperienceStoreTests {
  @Test
  func completionPersistsOnlyAfterBeingMarked() throws {
    let suiteName = "SafetyCheckExperienceStoreTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer {
      defaults.removePersistentDomain(forName: suiteName)
    }
    let store = SafetyCheckExperienceStore(
      userDefaults: defaults,
      completionKey: "completed"
    )

    #expect(!store.hasCompletedSafetyCheck)

    store.markCompleted()

    #expect(store.hasCompletedSafetyCheck)
  }
}
