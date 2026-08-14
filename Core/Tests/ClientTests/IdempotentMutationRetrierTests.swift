@testable import Client
import Foundation
import Testing

@Suite(.serialized)
struct IdempotentMutationRetrierTests {
  @Test
  func successfulMutationDoesNotResetOrRetry() async throws {
    let recorder = CallRecorder()
    let operation = ScriptedOperation(outcomes: [.success], recorder: recorder)

    try await perform(operation: operation, recorder: recorder)

    #expect(recorder.calls == [.attempt])
  }

  @Test
  func timeoutResetsConnectionBeforeSingleRetry() async throws {
    let recorder = CallRecorder()
    let operation = ScriptedOperation(outcomes: [.timedOut, .success], recorder: recorder)

    try await perform(operation: operation, recorder: recorder)

    #expect(recorder.calls == [.attempt, .reset, .attempt])
  }

  @Test
  func lostReplyResetsConnectionBeforeSingleRetry() async throws {
    let recorder = CallRecorder()
    let operation = ScriptedOperation(outcomes: [.lostReply, .success], recorder: recorder)

    try await perform(operation: operation, recorder: recorder)

    #expect(recorder.calls == [.attempt, .reset, .attempt])
  }

  @Test
  func mixedAmbiguousFailuresBecomeUnknownAfterOneRetry() async {
    let recorder = CallRecorder()
    let operation = ScriptedOperation(outcomes: [.timedOut, .lostReply], recorder: recorder)

    do {
      try await perform(operation: operation, recorder: recorder)
      Issue.record("Expected the second lost reply to become an unknown outcome.")
    } catch XPCClientError.operationOutcomeUnknown {
      #expect(recorder.calls == [.attempt, .reset, .attempt])
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func secondTimeoutBecomesUnknownWithoutAnotherRetry() async {
    let recorder = CallRecorder()
    let operation = ScriptedOperation(outcomes: [.timedOut, .timedOut], recorder: recorder)

    do {
      try await perform(operation: operation, recorder: recorder)
      Issue.record("Expected the second timeout to become an unknown outcome.")
    } catch XPCClientError.operationOutcomeUnknown {
      #expect(recorder.calls == [.attempt, .reset, .attempt])
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func nonTimeoutFailureDoesNotResetOrRetry() async {
    let recorder = CallRecorder()
    let operation = ScriptedOperation(outcomes: [.failure], recorder: recorder)

    do {
      try await perform(operation: operation, recorder: recorder)
      Issue.record("Expected the original failure to propagate.")
    } catch MutationTestError.expected {
      #expect(recorder.calls == [.attempt])
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func retryPropagatesNonTimeoutFailure() async {
    let recorder = CallRecorder()
    let operation = ScriptedOperation(outcomes: [.timedOut, .failure], recorder: recorder)

    do {
      try await perform(operation: operation, recorder: recorder)
      Issue.record("Expected the retry failure to propagate.")
    } catch MutationTestError.expected {
      #expect(recorder.calls == [.attempt, .reset, .attempt])
    } catch {
      Issue.record("Unexpected error: \(error)")
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
      Issue.record("The operation ran more times than expected.")
      return
    }

    switch outcomes.removeFirst() {
    case .failure:
      throw MutationTestError.expected
    case .lostReply:
      throw LostReplyError()
    case .success:
      return
    case .timedOut:
      throw XPCClientError.timedOut
    }
  }
}

private enum MutationOutcome: Sendable {
  case failure
  case lostReply
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
