import Client
import Foundation
import XCTest

final class LockNotificationControllerTests: XCTestCase {
  @MainActor
  func testLockedSignalPostsNotificationWithHotkeyAndDeadline() async {
    let service = FakeNotificationService()
    let observer = FakeLockStateObserver()
    let deadline = Date(timeIntervalSince1970: 1_900_000_000)
    let controller = LockNotificationController(
      notifications: service,
      lockStateObserver: observer,
      snapshotQuery: { Self.makeSnapshot(autoUnlockTargetDate: deadline) },
      unlock: {}
    )

    controller.start()
    // The subscriber emits the current state once after subscription, so this single signal
    // doubles as the "App launched while already locked" initial calibration.
    observer.emit(true)
    await controller.waitUntilIdle()

    let hotkey = KeyboardLockerSettings.default.unlockHotkey.displayString
    let expectedBody = "Press \(hotkey) or choose Unlock Now. Auto-unlocks at "
      + deadline.formatted(date: .omitted, time: .shortened) + "."
    XCTAssertEqual(service.events, [
      .installCategory,
      .requestAuthorization,
      .post(
        identifier: LockNotificationController.notificationIdentifier,
        category: LockNotificationController.categoryIdentifier,
        title: "Keyboard Locked",
        body: expectedBody
      ),
    ])
  }

  @MainActor
  func testManualLockBodyOmitsDeadline() async {
    let service = FakeNotificationService()
    let observer = FakeLockStateObserver()
    let controller = LockNotificationController(
      notifications: service,
      lockStateObserver: observer,
      snapshotQuery: { Self.makeSnapshot(autoUnlockTargetDate: nil) },
      unlock: {}
    )

    controller.start()
    observer.emit(true)
    await controller.waitUntilIdle()

    let hotkey = KeyboardLockerSettings.default.unlockHotkey.displayString
    XCTAssertEqual(service.postedBodies, ["Press \(hotkey) or choose Unlock Now."])
  }

  @MainActor
  func testUnlockedSignalRemovesNotification() async {
    let service = FakeNotificationService()
    let observer = FakeLockStateObserver()
    let controller = LockNotificationController(
      notifications: service,
      lockStateObserver: observer,
      snapshotQuery: { Self.makeSnapshot() },
      unlock: {}
    )

    controller.start()
    observer.emit(true)
    await controller.waitUntilIdle()
    observer.emit(false)
    await controller.waitUntilIdle()

    XCTAssertEqual(
      service.events.last,
      .remove(identifier: LockNotificationController.notificationIdentifier)
    )
  }

  @MainActor
  func testRapidLockUnlockNeverLeavesNotificationPosted() async {
    let service = FakeNotificationService()
    let observer = FakeLockStateObserver()
    let controller = LockNotificationController(
      notifications: service,
      lockStateObserver: observer,
      snapshotQuery: {
        try await Task.sleep(for: .milliseconds(50))
        return Self.makeSnapshot()
      },
      unlock: {}
    )

    controller.start()
    observer.emit(true)
    observer.emit(false)
    await controller.waitUntilIdle()

    XCTAssertEqual(
      service.events.last,
      .remove(identifier: LockNotificationController.notificationIdentifier)
    )
  }

  @MainActor
  func testRepeatedLockSignalsReuseTheSameIdentifier() async {
    let service = FakeNotificationService()
    let observer = FakeLockStateObserver()
    let controller = LockNotificationController(
      notifications: service,
      lockStateObserver: observer,
      snapshotQuery: { Self.makeSnapshot() },
      unlock: {}
    )

    controller.start()
    observer.emit(true)
    observer.emit(true)
    await controller.waitUntilIdle()

    XCTAssertEqual(service.postedIdentifiers, [
      LockNotificationController.notificationIdentifier,
      LockNotificationController.notificationIdentifier,
    ])
  }

  @MainActor
  func testSnapshotFailureStillPostsMinimalContent() async {
    let service = FakeNotificationService()
    let observer = FakeLockStateObserver()
    let controller = LockNotificationController(
      notifications: service,
      lockStateObserver: observer,
      snapshotQuery: { throw TestError.expected },
      unlock: {}
    )

    controller.start()
    observer.emit(true)
    await controller.waitUntilIdle()

    XCTAssertEqual(service.postedBodies, ["Choose Unlock Now to unlock."])
  }

  @MainActor
  func testDeniedAuthorizationSkipsPosting() async {
    let service = FakeNotificationService()
    service.canPostResult = false
    let observer = FakeLockStateObserver()
    let controller = LockNotificationController(
      notifications: service,
      lockStateObserver: observer,
      snapshotQuery: { Self.makeSnapshot() },
      unlock: {}
    )

    controller.start()
    observer.emit(true)
    await controller.waitUntilIdle()

    XCTAssertEqual(service.events, [.installCategory, .requestAuthorization])
  }

  @MainActor
  func testUnlockNowActionPerformsIdempotentUnlock() async {
    let service = FakeNotificationService()
    let observer = FakeLockStateObserver()
    let unlockRecorder = UnlockRecorder()
    let controller = LockNotificationController(
      notifications: service,
      lockStateObserver: observer,
      snapshotQuery: { Self.makeSnapshot() },
      unlock: { unlockRecorder.record() }
    )

    controller.start()
    XCTAssertNotNil(service.actionHandler)
    controller.handleAction(LockNotificationController.unlockActionIdentifier)
    await controller.waitUntilIdle()

    XCTAssertEqual(unlockRecorder.count, 1)
  }

  @MainActor
  func testUnlockFailureLeavesPresentationUntouched() async {
    let service = FakeNotificationService()
    let observer = FakeLockStateObserver()
    let controller = LockNotificationController(
      notifications: service,
      lockStateObserver: observer,
      snapshotQuery: { Self.makeSnapshot() },
      unlock: { throw TestError.expected }
    )

    controller.start()
    observer.emit(true)
    await controller.waitUntilIdle()
    let eventsBeforeAction = service.events

    controller.handleAction(LockNotificationController.unlockActionIdentifier)
    await controller.waitUntilIdle()

    XCTAssertEqual(service.events, eventsBeforeAction)
  }

  @MainActor
  func testUnknownActionIsIgnored() async {
    let service = FakeNotificationService()
    let observer = FakeLockStateObserver()
    let unlockRecorder = UnlockRecorder()
    let controller = LockNotificationController(
      notifications: service,
      lockStateObserver: observer,
      snapshotQuery: { Self.makeSnapshot() },
      unlock: { unlockRecorder.record() }
    )

    controller.start()
    controller.handleAction("SOME_OTHER_ACTION")
    await controller.waitUntilIdle()

    XCTAssertEqual(unlockRecorder.count, 0)
    XCTAssertEqual(service.events, [.installCategory, .requestAuthorization])
  }

  private static func makeSnapshot(
    autoUnlockTargetDate: Date? = Date(timeIntervalSince1970: 1_900_000_000)
  ) -> LockStatusSnapshot {
    LockStatusSnapshot(
      capturedAt: Date(timeIntervalSince1970: 1_899_999_000),
      isLocked: true,
      startedAt: Date(timeIntervalSince1970: 1_899_999_000),
      autoUnlockTargetDate: autoUnlockTargetDate,
      settings: .default
    )
  }
}

private enum TestError: Error {
  case expected
}

@MainActor
private final class FakeNotificationService: LockNotificationServing {
  enum Event: Equatable {
    case installCategory
    case requestAuthorization
    case post(identifier: String, category: String, title: String, body: String)
    case remove(identifier: String)
  }

  private(set) var events: [Event] = []
  var actionHandler: (@Sendable (String) -> Void)?
  var authorizationGranted = true
  var canPostResult = true

  var postedIdentifiers: [String] {
    events.compactMap { event in
      guard case let .post(identifier, _, _, _) = event else {
        return nil
      }
      return identifier
    }
  }

  var postedBodies: [String] {
    events.compactMap { event in
      guard case let .post(_, _, _, body) = event else {
        return nil
      }
      return body
    }
  }

  func installUnlockActionCategory() {
    events.append(.installCategory)
  }

  func requestAuthorization() async -> Bool {
    events.append(.requestAuthorization)
    return authorizationGranted
  }

  func canPost() async -> Bool {
    canPostResult
  }

  func postLocked(identifier: String, categoryIdentifier: String, title: String, body: String) {
    events.append(.post(identifier: identifier, category: categoryIdentifier, title: title, body: body))
  }

  func removeLocked(identifier: String) {
    events.append(.remove(identifier: identifier))
  }
}

@MainActor
private final class FakeLockStateObserver: AgentLockStateObserving {
  private var handler: ((Bool) -> Void)?

  func subscribe(
    initialState _: Bool?,
    _ handler: @escaping (Bool) -> Void
  ) -> ObserverToken {
    self.handler = handler
    return ObserverToken {}
  }

  func emit(_ isLocked: Bool) {
    handler?(isLocked)
  }
}

private final class UnlockRecorder: @unchecked Sendable {
  private(set) var count = 0

  func record() {
    count += 1
  }
}
