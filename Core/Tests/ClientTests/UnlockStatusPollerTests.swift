@testable import Client
import Foundation
import Testing

@Suite(.serialized)
struct UnlockStatusPollerTests {
  @Test
  func returnsImmediatelyWhenAlreadyUnlocked() async throws {
    let source = ScriptedStatusSource([.value(false)])
    let resetRecorder = ResetRecorder()
    let sleepRecorder = SleepRecorder()
    let poller = makePoller(
      source: source,
      resetRecorder: resetRecorder,
      sleepRecorder: sleepRecorder
    )

    try await poller.waitUntilUnlocked()

    let fetchCount = await source.fetchCount
    let sleepCount = await sleepRecorder.count
    #expect(fetchCount == 1)
    #expect(resetRecorder.count == 0)
    #expect(sleepCount == 0)
  }

  @Test
  func keepsPollingUntilAuthoritativeStateIsUnlocked() async throws {
    let source = ScriptedStatusSource([.value(true), .value(false)])
    let resetRecorder = ResetRecorder()
    let sleepRecorder = SleepRecorder()
    let poller = makePoller(
      source: source,
      resetRecorder: resetRecorder,
      sleepRecorder: sleepRecorder
    )

    try await poller.waitUntilUnlocked()

    let fetchCount = await source.fetchCount
    let sleepCount = await sleepRecorder.count
    #expect(fetchCount == 2)
    #expect(resetRecorder.count == 0)
    #expect(sleepCount == 1)
  }

  @Test
  func transientFailureResetsConnectionAndCanRecoverAsUnlocked() async throws {
    let source = ScriptedStatusSource([
      .failure(.first),
      .value(false),
    ])
    let resetRecorder = ResetRecorder()
    let sleepRecorder = SleepRecorder()
    let poller = makePoller(
      source: source,
      resetRecorder: resetRecorder,
      sleepRecorder: sleepRecorder
    )

    try await poller.waitUntilUnlocked()

    let fetchCount = await source.fetchCount
    let sleepCount = await sleepRecorder.count
    #expect(fetchCount == 2)
    #expect(resetRecorder.count == 1)
    #expect(sleepCount == 1)
  }

  @Test
  func successfulLockedReadClearsConsecutiveFailureCount() async throws {
    let source = ScriptedStatusSource([
      .failure(.first),
      .value(true),
      .failure(.second),
      .value(true),
      .failure(.third),
      .value(false),
    ])
    let resetRecorder = ResetRecorder()
    let sleepRecorder = SleepRecorder()
    let poller = makePoller(
      maximumConsecutiveFailures: 2,
      source: source,
      resetRecorder: resetRecorder,
      sleepRecorder: sleepRecorder
    )

    try await poller.waitUntilUnlocked()

    let fetchCount = await source.fetchCount
    let sleepCount = await sleepRecorder.count
    #expect(fetchCount == 6)
    #expect(resetRecorder.count == 3)
    #expect(sleepCount == 5)
  }

  @Test
  func throwsLastErrorAfterMaximumConsecutiveFailures() async {
    let source = ScriptedStatusSource([
      .failure(.first),
      .failure(.second),
      .failure(.third),
    ])
    let resetRecorder = ResetRecorder()
    let sleepRecorder = SleepRecorder()
    let poller = makePoller(
      source: source,
      resetRecorder: resetRecorder,
      sleepRecorder: sleepRecorder
    )

    do {
      try await poller.waitUntilUnlocked()
      Issue.record("Expected polling to fail")
    } catch {
      #expect(error as? TestFailure == .third)
    }

    let fetchCount = await source.fetchCount
    let sleepCount = await sleepRecorder.count
    #expect(fetchCount == 3)
    #expect(resetRecorder.count == 3)
    #expect(sleepCount == 2)
  }

  private func makePoller(
    maximumConsecutiveFailures: Int = 3,
    source: ScriptedStatusSource,
    resetRecorder: ResetRecorder,
    sleepRecorder: SleepRecorder
  ) -> UnlockStatusPoller {
    UnlockStatusPoller(
      pollInterval: .seconds(1),
      maximumConsecutiveFailures: maximumConsecutiveFailures,
      fetchStatus: {
        try await source.fetch()
      },
      resetConnection: {
        resetRecorder.record()
      },
      sleep: { _ in
        await sleepRecorder.record()
      }
    )
  }
}

private actor ScriptedStatusSource {
  enum Outcome: Sendable {
    case failure(TestFailure)
    case value(Bool)
  }

  private var outcomes: [Outcome]
  private(set) var fetchCount = 0

  init(_ outcomes: [Outcome]) {
    self.outcomes = outcomes
  }

  func fetch() throws -> Bool {
    fetchCount += 1
    guard !outcomes.isEmpty else {
      Issue.record("Status source exhausted")
      throw TestFailure.sourceExhausted
    }

    switch outcomes.removeFirst() {
    case let .failure(error):
      throw error
    case let .value(isLocked):
      return isLocked
    }
  }
}

private final class ResetRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var recordedCount = 0

  var count: Int {
    lock.withLock {
      recordedCount
    }
  }

  func record() {
    lock.withLock {
      recordedCount += 1
    }
  }
}

private actor SleepRecorder {
  private(set) var count = 0

  func record() {
    count += 1
  }
}

private enum TestFailure: Error, Equatable, Sendable {
  case first
  case second
  case sourceExhausted
  case third
}
