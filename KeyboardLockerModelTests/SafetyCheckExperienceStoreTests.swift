import Foundation
import XCTest

final class SafetyCheckExperienceStoreTests: XCTestCase {
  func testCompletionPersistsOnlyAfterBeingMarked() throws {
    let suiteName = "SafetyCheckExperienceStoreTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer {
      defaults.removePersistentDomain(forName: suiteName)
    }
    let store = SafetyCheckExperienceStore(
      userDefaults: defaults,
      completionKey: "completed"
    )

    XCTAssertFalse(store.hasCompletedSafetyCheck)

    store.markCompleted()

    XCTAssertTrue(store.hasCompletedSafetyCheck)
  }
}
