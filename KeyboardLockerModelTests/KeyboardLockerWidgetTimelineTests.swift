import Client
import Foundation
import XCTest

final class KeyboardLockerWidgetTimelineTests: XCTestCase {
  private let now = Date(timeIntervalSinceReferenceDate: 10000)

  func testRegularRefreshUsesBudgetFriendlyFallbackInterval() {
    XCTAssertEqual(
      KeyboardLockerWidgetSnapshotLoader.regularRefreshInterval,
      15 * 60
    )
  }

  func testLoaderPublishesAuthoritativeSnapshot() async {
    let snapshot = LockStatusSnapshot(
      capturedAt: now,
      isLocked: true,
      startedAt: now.addingTimeInterval(-10),
      autoUnlockTargetDate: now.addingTimeInterval(50),
      settings: .default
    )
    let loader = KeyboardLockerWidgetSnapshotLoader {
      snapshot
    }

    let entry = await loader.entry(at: now)

    XCTAssertEqual(entry, KeyboardLockerWidgetEntry(date: now, state: .available(snapshot)))
  }

  func testLoaderPublishesExplicitUnavailableState() async {
    let loader = KeyboardLockerWidgetSnapshotLoader {
      throw XPCClientError.serviceUnavailable
    }

    let entry = await loader.entry(at: now)

    guard case let .unavailable(message) = entry.state else {
      return XCTFail("Expected an unavailable entry.")
    }
    XCTAssertTrue(message.contains("The KeyboardLocker agent is not reachable."))
    XCTAssertTrue(message.contains("Open KeyboardLocker once"))
  }

  func testRefreshReconcilesImmediatelyAfterEarlierAutoUnlockDeadline() {
    let deadline = now.addingTimeInterval(20)
    let snapshot = LockStatusSnapshot(
      capturedAt: now,
      isLocked: true,
      startedAt: now.addingTimeInterval(-10),
      autoUnlockTargetDate: deadline,
      settings: .default
    )
    let entry = KeyboardLockerWidgetEntry(date: now, state: .available(snapshot))
    let loader = KeyboardLockerWidgetSnapshotLoader {
      snapshot
    }

    XCTAssertEqual(
      loader.nextRefreshDate(after: entry, now: now),
      deadline.addingTimeInterval(1)
    )
  }

  func testRefreshUsesRegularIntervalWithoutEarlierDeadline() {
    let snapshot = LockStatusSnapshot(
      capturedAt: now,
      isLocked: false,
      startedAt: nil,
      autoUnlockTargetDate: nil,
      settings: .default
    )
    let entry = KeyboardLockerWidgetEntry(date: now, state: .available(snapshot))
    let loader = KeyboardLockerWidgetSnapshotLoader {
      snapshot
    }

    XCTAssertEqual(
      loader.nextRefreshDate(after: entry, now: now),
      now.addingTimeInterval(KeyboardLockerWidgetSnapshotLoader.regularRefreshInterval)
    )
  }
}
