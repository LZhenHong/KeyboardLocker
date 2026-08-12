import Common
import Foundation
@testable import Service
import Testing

@MainActor
@Suite(.serialized)
final class LockStatusNotifierTests {
  private let notifications: FakeLockStatusNotifications
  private var snapshot: LockStatusSnapshot
  private var unlockCalls: Int

  init() {
    notifications = FakeLockStatusNotifications()
    snapshot = Self.makeSnapshot(isLocked: false)
    unlockCalls = 0
  }

  @Test
  func startInstallsCategoryAndClearsStaleNotification() async {
    let notifier = makeNotifier()

    notifier.start()
    await notifier.waitUntilIdle()

    #expect(notifications.installedCategoryCount == 1)
    #expect(notifications.removedIdentifiers == [LockStatusNotifier.notificationIdentifier])
  }

  @Test
  func lockTransitionPostsNotificationWithHotkeyAndDeadline() async throws {
    snapshot = Self.makeSnapshot(
      isLocked: true,
      autoUnlockTargetDate: Date(timeIntervalSinceReferenceDate: 1060)
    )
    let notifier = makeNotifier()

    notifier.lockStateDidChange()
    await notifier.waitUntilIdle()

    #expect(notifications.authorizationRequests == 1)
    #expect(notifications.posts.count == 1)
    let post = try #require(notifications.posts.first)
    #expect(post.identifier == LockStatusNotifier.notificationIdentifier)
    #expect(post.categoryIdentifier == LockStatusNotifier.categoryIdentifier)
    #expect(post.title == "Keyboard Locked")
    #expect(post.body.contains("⌃⌘L"), "body: \(post.body)")
    #expect(post.body.contains("Unlock Now"), "body: \(post.body)")
    #expect(post.body.contains("Auto-unlocks at"), "body: \(post.body)")
    #expect(notifications.removedIdentifiers.isEmpty)
  }

  @Test
  func lockTransitionWithoutDeadlineOmitsAutoUnlockLine() async throws {
    snapshot = Self.makeSnapshot(isLocked: true, autoUnlockTargetDate: nil)
    let notifier = makeNotifier()

    notifier.lockStateDidChange()
    await notifier.waitUntilIdle()

    let post = try #require(notifications.posts.first)
    #expect(!post.body.contains("Auto-unlocks"), "body: \(post.body)")
  }

  @Test
  func unlockTransitionRemovesNotificationWithoutRequestingAuthorization() async {
    snapshot = Self.makeSnapshot(isLocked: false)
    let notifier = makeNotifier()

    notifier.lockStateDidChange()
    await notifier.waitUntilIdle()

    #expect(notifications.removedIdentifiers == [LockStatusNotifier.notificationIdentifier])
    #expect(notifications.authorizationRequests == 0)
    #expect(notifications.posts.isEmpty)
  }

  @Test
  func deniedAuthorizationSkipsPostSilently() async {
    notifications.authorizationGranted = false
    snapshot = Self.makeSnapshot(isLocked: true)
    let notifier = makeNotifier()

    notifier.lockStateDidChange()
    await notifier.waitUntilIdle()

    #expect(notifications.authorizationRequests == 1)
    #expect(notifications.posts.isEmpty)
  }

  @Test
  func unlockActionRunsLocalUnlock() async {
    _ = makeNotifier()

    notifications.actionHandler?(LockStatusNotifier.unlockActionIdentifier)
    await waitForCondition { self.unlockCalls == 1 }

    #expect(unlockCalls == 1)
  }

  @Test
  func unrelatedActionIsIgnored() async {
    _ = makeNotifier()

    notifications.actionHandler?("some-other-action")
    await waitForCondition { false }

    #expect(unlockCalls == 0)
  }

  /// A rapid lock/unlock flip must serialize post before remove; the remove cannot overtake
  /// the in-flight post and leave a stale notification behind.
  @Test
  func quickFlipSerializesPostThenRemove() async {
    let notifier = makeNotifier()

    snapshot = Self.makeSnapshot(isLocked: true)
    notifier.lockStateDidChange()
    snapshot = Self.makeSnapshot(isLocked: false)
    notifier.lockStateDidChange()
    await notifier.waitUntilIdle()

    #expect(notifications.events == [
      .post,
      .remove(LockStatusNotifier.notificationIdentifier),
    ])
  }

  // MARK: - Helpers

  private func makeNotifier() -> LockStatusNotifier {
    LockStatusNotifier(
      notifications: notifications,
      snapshot: { [self] in snapshot },
      unlock: { [self] in unlockCalls += 1 }
    )
  }

  private static func makeSnapshot(
    isLocked: Bool,
    autoUnlockTargetDate: Date? = nil
  ) -> LockStatusSnapshot {
    LockStatusSnapshot(
      capturedAt: Date(timeIntervalSinceReferenceDate: 1000),
      isLocked: isLocked,
      startedAt: isLocked ? Date(timeIntervalSinceReferenceDate: 1000) : nil,
      autoUnlockTargetDate: autoUnlockTargetDate,
      settings: .default
    )
  }

  /// The action handler hops through a `Task` onto the main actor, so tests poll with a
  /// generous ceiling: the hop lands in microseconds on a healthy machine, and only a truly
  /// broken hop burns the full budget before failing.
  private func waitForCondition(
    timeout: TimeInterval = 1,
    _ condition: @MainActor () -> Bool
  ) async {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition(), Date() < deadline {
      await Task.yield()
    }
  }
}

@MainActor
private final class FakeLockStatusNotifications: LockStatusNotifying {
  enum Event: Equatable {
    case post
    case remove(String)
  }

  var actionHandler: (@Sendable (String) -> Void)?
  var authorizationGranted = true

  private(set) var installedCategoryCount = 0
  private(set) var authorizationRequests = 0
  private(set) var posts: [(identifier: String, categoryIdentifier: String, title: String, body: String)] = []
  private(set) var removedIdentifiers: [String] = []
  private(set) var events: [Event] = []

  func installUnlockActionCategory() {
    installedCategoryCount += 1
  }

  func requestAlertAuthorization() async -> Bool {
    authorizationRequests += 1
    return authorizationGranted
  }

  func postLocked(identifier: String, categoryIdentifier: String, title: String, body: String) {
    posts.append((identifier, categoryIdentifier, title, body))
    events.append(.post)
  }

  func removeLocked(identifier: String) {
    removedIdentifiers.append(identifier)
    events.append(.remove(identifier))
  }
}
