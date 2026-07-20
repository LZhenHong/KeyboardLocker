@testable import Client
import Foundation
import XCTest

final class IdempotentMutationRetrierTests: XCTestCase {
  func testSuccessfulMutationDoesNotResetOrRetry() async throws {
    let recorder = CallRecorder()
    let operation = ScriptedOperation(outcomes: [.success], recorder: recorder)

    try await perform(operation: operation, recorder: recorder)

    XCTAssertEqual(recorder.calls, [.attempt])
  }

  func testTimeoutResetsConnectionBeforeSingleRetry() async throws {
    let recorder = CallRecorder()
    let operation = ScriptedOperation(outcomes: [.timedOut, .success], recorder: recorder)

    try await perform(operation: operation, recorder: recorder)

    XCTAssertEqual(recorder.calls, [.attempt, .reset, .attempt])
  }

  func testSecondTimeoutBecomesUnknownWithoutAnotherRetry() async {
    let recorder = CallRecorder()
    let operation = ScriptedOperation(outcomes: [.timedOut, .timedOut], recorder: recorder)

    do {
      try await perform(operation: operation, recorder: recorder)
      XCTFail("Expected the second timeout to become an unknown outcome.")
    } catch XPCClientError.operationOutcomeUnknown {
      XCTAssertEqual(recorder.calls, [.attempt, .reset, .attempt])
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testNonTimeoutFailureDoesNotResetOrRetry() async {
    let recorder = CallRecorder()
    let operation = ScriptedOperation(outcomes: [.failure], recorder: recorder)

    do {
      try await perform(operation: operation, recorder: recorder)
      XCTFail("Expected the original failure to propagate.")
    } catch MutationTestError.expected {
      XCTAssertEqual(recorder.calls, [.attempt])
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testRetryPropagatesNonTimeoutFailure() async {
    let recorder = CallRecorder()
    let operation = ScriptedOperation(outcomes: [.timedOut, .failure], recorder: recorder)

    do {
      try await perform(operation: operation, recorder: recorder)
      XCTFail("Expected the retry failure to propagate.")
    } catch MutationTestError.expected {
      XCTAssertEqual(recorder.calls, [.attempt, .reset, .attempt])
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  private func perform(
    operation: ScriptedOperation,
    recorder: CallRecorder
  ) async throws {
    try await IdempotentMutationRetrier.perform(
      operation: {
        try await operation.perform()
      },
      resetConnection: {
        recorder.record(.reset)
      }
    )
  }
}

private actor ScriptedOperation {
  private var outcomes: [MutationOutcome]
  private let recorder: CallRecorder

  init(outcomes: [MutationOutcome], recorder: CallRecorder) {
    self.outcomes = outcomes
    self.recorder = recorder
  }

  func perform() throws {
    recorder.record(.attempt)
    guard !outcomes.isEmpty else {
      XCTFail("The operation ran more times than expected.")
      return
    }

    switch outcomes.removeFirst() {
    case .failure:
      throw MutationTestError.expected
    case .success:
      return
    case .timedOut:
      throw XPCClientError.timedOut
    }
  }
}

private enum MutationOutcome: Sendable {
  case failure
  case success
  case timedOut
}

private enum MutationTestError: Error {
  case expected
}

private final class CallRecorder: @unchecked Sendable {
  enum Call: Equatable {
    case attempt
    case reset
  }

  private let lock = NSLock()
  private var recordedCalls: [Call] = []

  var calls: [Call] {
    lock.lock()
    defer { lock.unlock() }
    return recordedCalls
  }

  func record(_ call: Call) {
    lock.lock()
    recordedCalls.append(call)
    lock.unlock()
  }
}
