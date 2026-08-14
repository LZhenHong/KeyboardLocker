import Client
import Foundation
import Testing

@Suite(.serialized)
struct KeyboardLockerWidgetTimelineTests {
  private let now = Date(timeIntervalSinceReferenceDate: 10000)

  @Test
  func regularRefreshUsesBudgetFriendlyFallbackInterval() {
    #expect(
      KeyboardLockerWidgetSnapshotLoader.regularRefreshInterval ==
        15 * 60
    )
  }

  @Test
  func loaderPublishesAuthoritativeSnapshot() async {
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

    #expect(entry == KeyboardLockerWidgetEntry(date: now, state: .available(snapshot)))
  }

  @Test
  func loaderPublishesExplicitUnavailableState() async {
    let loader = KeyboardLockerWidgetSnapshotLoader {
      throw XPCClientError.serviceUnavailable
    }

    let entry = await loader.entry(at: now)

    guard case let .unavailable(message) = entry.state else {
      Issue.record("Expected an unavailable entry.")
      return
    }
    #expect(message.contains("The KeyboardLocker agent is not reachable."))
    #expect(message.contains("Open KeyboardLocker once"))
  }

  @Test
  func refreshReconcilesImmediatelyAfterEarlierAutoUnlockDeadline() {
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

    #expect(
      loader.nextRefreshDate(after: entry, now: now) ==
        deadline.addingTimeInterval(1)
    )
  }

  @Test
  func refreshUsesRegularIntervalWithoutEarlierDeadline() {
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

    #expect(
      loader.nextRefreshDate(after: entry, now: now) ==
        now.addingTimeInterval(KeyboardLockerWidgetSnapshotLoader.regularRefreshInterval)
    )
  }
}
