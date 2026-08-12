@testable import Client
import Foundation
import Testing

@Suite(.serialized)
struct LockStateSubscriberTests {
  @Test
  func subscriptionCalibratesImmediatelyAfterInstallingObservers() async throws {
    let fetcher = ControlledStateFetcher()
    try await confirmation("Received initial authoritative state") { receivedInitialState in
      let recorder = StateRecorder {
        receivedInitialState()
      }

      let token = LockStateSubscriber.subscribe(
        fetchState: { try await fetcher.fetch() }
      ) { isLocked in
        recorder.record(isLocked)
      }

      await fetcher.waitUntilStarted(1)
      try await fetcher.resolveFetch(0, with: true)
      await recorder.waitUntilCount(1)

      #expect(recorder.values == [true])
      withExtendedLifetime(token) {}
    }
  }

  @Test
  func initialCalibrationMatchingSeedIsNotRedelivered() async throws {
    let fetcher = ControlledStateFetcher()
    try await confirmation("Did not redeliver seeded state", expectedCount: 0) { receivedState in
      let recorder = StateRecorder {
        receivedState()
      }

      let token = LockStateSubscriber.subscribe(
        initialState: true,
        fetchState: { try await fetcher.fetch() }
      ) { isLocked in
        recorder.record(isLocked)
      }

      await fetcher.waitUntilStarted(1)
      try await fetcher.resolveFetch(0, with: true)
      try? await Task.sleep(for: .milliseconds(100))

      #expect(recorder.values.isEmpty)
      withExtendedLifetime(token) {}
    }
  }

  @Test
  func initialCalibrationDifferingFromSeedIsDelivered() async throws {
    let fetcher = ControlledStateFetcher()
    try await confirmation("Received state differing from seed") { receivedState in
      let recorder = StateRecorder {
        receivedState()
      }

      let token = LockStateSubscriber.subscribe(
        initialState: false,
        fetchState: { try await fetcher.fetch() }
      ) { isLocked in
        recorder.record(isLocked)
      }

      await fetcher.waitUntilStarted(1)
      try await fetcher.resolveFetch(0, with: true)
      await recorder.waitUntilCount(1)

      #expect(recorder.values == [true])
      withExtendedLifetime(token) {}
    }
  }

  @Test
  func releasingTokenSuppressesPendingCalibrationDelivery() async throws {
    let fetcher = ControlledStateFetcher()
    try await confirmation("Did not receive state after cancellation", expectedCount: 0) { receivedState in
      let recorder = StateRecorder {
        receivedState()
      }

      var token: ObserverToken? = LockStateSubscriber.subscribe(
        fetchState: { try await fetcher.fetch() }
      ) { isLocked in
        recorder.record(isLocked)
      }

      await fetcher.waitUntilStarted(1)
      token = nil
      try await fetcher.resolveFetch(0, with: true)
      try? await Task.sleep(for: .milliseconds(100))

      let fetchMetrics = await fetcher.metrics
      #expect(token == nil)
      #expect(recorder.values.isEmpty)
      #expect(fetchMetrics.startedCount == 1)
    }
  }

  @Test
  func signalsDuringFetchAreSerializedAndCoalescedIntoOneFollowUp() async throws {
    let fetcher = ControlledStateFetcher()
    try await confirmation("Received reconciled states", expectedCount: 2) { receivedStates in
      let recorder = StateRecorder {
        receivedStates()
      }
      let reconciler = StateReconciler(
        fetchState: { try await fetcher.fetch() }
      ) { isLocked in
        recorder.record(isLocked)
      }

      reconciler.signal()
      await fetcher.waitUntilStarted(1)

      reconciler.signal()
      reconciler.signal()
      reconciler.signal()
      await Task.yield()

      var fetchMetrics = await fetcher.metrics
      #expect(fetchMetrics.startedCount == 1)
      #expect(fetchMetrics.maximumConcurrentFetches == 1)

      try await fetcher.resolveFetch(0, with: false)
      await fetcher.waitUntilStarted(2)

      fetchMetrics = await fetcher.metrics
      #expect(fetchMetrics.startedCount == 2)
      #expect(fetchMetrics.maximumConcurrentFetches == 1)

      try await fetcher.resolveFetch(1, with: true)
      await recorder.waitUntilCount(2)
      await Task.yield()

      fetchMetrics = await fetcher.metrics
      #expect(recorder.values == [false, true])
      #expect(fetchMetrics.startedCount == 2)
      #expect(fetchMetrics.maximumConcurrentFetches == 1)
    }
  }

  @Test
  func consecutiveEqualAuthoritativeStatesAreDeduplicated() async throws {
    let fetcher = ControlledStateFetcher()
    try await confirmation("Received distinct states", expectedCount: 2) { receivedStates in
      let recorder = StateRecorder {
        receivedStates()
      }
      let reconciler = StateReconciler(
        fetchState: { try await fetcher.fetch() }
      ) { isLocked in
        recorder.record(isLocked)
      }

      reconciler.signal()
      await fetcher.waitUntilStarted(1)
      try await fetcher.resolveFetch(0, with: true)
      await recorder.waitUntilCount(1)

      reconciler.signal()
      await fetcher.waitUntilStarted(2)
      try await fetcher.resolveFetch(1, with: true)
      await fetcher.waitUntilCompleted(2)

      reconciler.signal()
      await fetcher.waitUntilStarted(3)
      try await fetcher.resolveFetch(2, with: false)
      await recorder.waitUntilCount(2)

      #expect(recorder.values == [true, false])
    }
  }
}

private actor ControlledStateFetcher {
  private var continuations: [CheckedContinuation<Bool, Error>?] = []
  private var startWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
  private var completionWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
  private(set) var startedCount = 0
  private(set) var completedCount = 0
  private(set) var concurrentFetches = 0
  private(set) var maximumConcurrentFetches = 0

  var metrics: (startedCount: Int, maximumConcurrentFetches: Int) {
    (startedCount, maximumConcurrentFetches)
  }

  func fetch() async throws -> Bool {
    startedCount += 1
    concurrentFetches += 1
    maximumConcurrentFetches = max(maximumConcurrentFetches, concurrentFetches)

    let readyStartWaiters = startWaiters.filter { $0.count <= startedCount }
    startWaiters.removeAll { $0.count <= startedCount }
    readyStartWaiters.forEach { $0.continuation.resume() }

    return try await withCheckedThrowingContinuation { continuation in
      continuations.append(continuation)
    }
  }

  func resolveFetch(_ index: Int, with value: Bool) throws {
    guard continuations.indices.contains(index),
          let continuation = continuations[index]
    else {
      throw ControlledStateFetcherError.noPendingFetch(index)
    }

    continuations[index] = nil
    concurrentFetches -= 1
    completedCount += 1
    continuation.resume(returning: value)

    let readyCompletionWaiters = completionWaiters.filter { $0.count <= completedCount }
    completionWaiters.removeAll { $0.count <= completedCount }
    readyCompletionWaiters.forEach { $0.continuation.resume() }
  }

  func waitUntilStarted(_ count: Int) async {
    guard startedCount < count else {
      return
    }

    await withCheckedContinuation { continuation in
      startWaiters.append((count, continuation))
    }
  }

  func waitUntilCompleted(_ count: Int) async {
    guard completedCount < count else {
      return
    }

    await withCheckedContinuation { continuation in
      completionWaiters.append((count, continuation))
    }
  }
}

private enum ControlledStateFetcherError: Error {
  case noPendingFetch(Int)
}

private final class StateRecorder: @unchecked Sendable {
  private typealias CountWaiter = (
    count: Int,
    continuation: CheckedContinuation<Void, Never>
  )

  private let lock = NSLock()
  private let onRecord: () -> Void
  private var recordedValues: [Bool] = []
  private var countWaiters: [CountWaiter] = []

  init(onRecord: @escaping () -> Void = {}) {
    self.onRecord = onRecord
  }

  var values: [Bool] {
    lock.withLock {
      recordedValues
    }
  }

  func record(_ value: Bool) {
    let readyWaiters: [CountWaiter] = lock.withLock {
      recordedValues.append(value)
      let ready = countWaiters.filter { $0.count <= recordedValues.count }
      countWaiters.removeAll { $0.count <= recordedValues.count }
      return ready
    }
    readyWaiters.forEach { $0.continuation.resume() }
    onRecord()
  }

  func waitUntilCount(_ count: Int) async {
    await withCheckedContinuation { continuation in
      let isAlreadySatisfied = lock.withLock {
        guard recordedValues.count < count else {
          return true
        }

        countWaiters.append((count, continuation))
        return false
      }

      if isAlreadySatisfied {
        continuation.resume()
      }
    }
  }
}
