@testable import Client
import Foundation
import XCTest

final class UnlockWaiterTests: XCTestCase {
  func testNotificationUnlockCancelsInFlightPolling() async throws {
    let (stateChanges, stateContinuation) = AsyncStream.makeStream(of: Bool.self)
    let polling = ControlledPollingOperation()
    let waiter = makeWaiter(
      stateChanges: stateChanges,
      polling: polling
    )

    let waitTask = Task {
      try await waiter.waitUntilUnlocked()
    }
    await polling.waitUntilStarted()

    stateContinuation.yield(false)
    try await waitTask.value

    XCTAssertEqual(polling.cancellationCount, 1)
    stateContinuation.finish()
  }

  func testPollingUnlockCancelsObservation() async throws {
    let (stateChanges, stateContinuation) = AsyncStream.makeStream(of: Bool.self)
    let polling = ControlledPollingOperation()
    let waiter = makeWaiter(
      stateChanges: stateChanges,
      polling: polling
    )

    let waitTask = Task {
      try await waiter.waitUntilUnlocked()
    }
    await polling.waitUntilStarted()

    polling.succeed()
    try await waitTask.value

    XCTAssertEqual(polling.cancellationCount, 0)
    stateContinuation.finish()
  }

  func testEndedObservationKeepsWaitingForPollingFallback() async throws {
    let (stateChanges, stateContinuation) = AsyncStream.makeStream(of: Bool.self)
    let polling = ControlledPollingOperation()
    let waiter = makeWaiter(
      stateChanges: stateChanges,
      polling: polling
    )

    let waitTask = Task {
      try await waiter.waitUntilUnlocked()
    }
    await polling.waitUntilStarted()

    stateContinuation.finish()
    polling.succeed()

    try await waitTask.value
    XCTAssertEqual(polling.cancellationCount, 0)
  }

  func testPollingFailureIsPropagated() async {
    let (stateChanges, stateContinuation) = AsyncStream.makeStream(of: Bool.self)
    let polling = ControlledPollingOperation()
    let waiter = makeWaiter(
      stateChanges: stateChanges,
      polling: polling
    )

    let waitTask = Task {
      try await waiter.waitUntilUnlocked()
    }
    await polling.waitUntilStarted()
    polling.fail(with: TestFailure.pollFailed)

    do {
      try await waitTask.value
      XCTFail("Expected polling failure")
    } catch {
      XCTAssertEqual(error as? TestFailure, .pollFailed)
    }

    XCTAssertEqual(polling.cancellationCount, 0)
    stateContinuation.finish()
  }

  func testCancellingWaitCancelsInFlightPolling() async {
    let (stateChanges, stateContinuation) = AsyncStream.makeStream(of: Bool.self)
    let polling = ControlledPollingOperation()
    let waiter = makeWaiter(
      stateChanges: stateChanges,
      polling: polling
    )

    let waitTask = Task {
      try await waiter.waitUntilUnlocked()
    }
    await polling.waitUntilStarted()
    waitTask.cancel()

    do {
      try await waitTask.value
      XCTFail("Expected cancellation")
    } catch {
      XCTAssertTrue(error is CancellationError)
    }

    XCTAssertEqual(polling.cancellationCount, 1)
    stateContinuation.finish()
  }

  private func makeWaiter(
    stateChanges: AsyncStream<Bool>,
    polling: ControlledPollingOperation
  ) -> UnlockWaiter {
    UnlockWaiter(
      stateChanges: stateChanges,
      pollUntilUnlocked: {
        try await polling.run()
      },
      cancelPolling: {
        polling.cancel()
      }
    )
  }
}

private final class ControlledPollingOperation: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<Void, Error>?
  private var didStart = false
  private var startWaiters: [CheckedContinuation<Void, Never>] = []
  private var recordedCancellationCount = 0

  var cancellationCount: Int {
    lock.withLock {
      recordedCancellationCount
    }
  }

  func run() async throws {
    try await withCheckedThrowingContinuation { continuation in
      let readyWaiters: [CheckedContinuation<Void, Never>] = lock.withLock {
        precondition(self.continuation == nil)
        self.continuation = continuation
        didStart = true
        defer { startWaiters.removeAll() }
        return startWaiters
      }
      readyWaiters.forEach { $0.resume() }
    }
  }

  func waitUntilStarted() async {
    await withCheckedContinuation { continuation in
      let isAlreadyStarted = lock.withLock {
        guard !didStart else {
          return true
        }

        startWaiters.append(continuation)
        return false
      }

      if isAlreadyStarted {
        continuation.resume()
      }
    }
  }

  func succeed() {
    takeContinuation()?.resume()
  }

  func fail(with error: Error) {
    takeContinuation()?.resume(throwing: error)
  }

  func cancel() {
    let pendingContinuation: CheckedContinuation<Void, Error>? = lock.withLock {
      recordedCancellationCount += 1
      defer { continuation = nil }
      return continuation
    }
    pendingContinuation?.resume(throwing: CancellationError())
  }

  private func takeContinuation() -> CheckedContinuation<Void, Error>? {
    lock.withLock {
      defer { continuation = nil }
      return continuation
    }
  }
}

private enum TestFailure: Error, Equatable {
  case pollFailed
}
