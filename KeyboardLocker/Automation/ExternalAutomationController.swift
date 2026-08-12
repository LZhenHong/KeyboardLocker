import Foundation

@MainActor
protocol ExternalAutomationPresenting: Sendable {
  func presentStatus(isLocked: Bool, source: ExternalAutomationSource)
  func presentFailures(
    _ failures: [ExternalAutomationFailure],
    source: ExternalAutomationSource
  )
}

@MainActor
final class ExternalAutomationController {
  private let client: any AgentLockActionServing
  private let presenter: any ExternalAutomationPresenting
  private var tail: Task<Void, Never>?

  init(
    client: any AgentLockActionServing,
    presenter: any ExternalAutomationPresenting
  ) {
    self.client = client
    self.presenter = presenter
  }

  convenience init() {
    self.init(
      client: LiveAgentClient(),
      presenter: AppKitExternalAutomationPresenter()
    )
  }

  func submit(
    _ action: ExternalAutomationAction,
    source: ExternalAutomationSource
  ) {
    submit([.action(action)], source: source)
  }

  func submit(
    _ actions: [ExternalAutomationAction],
    source: ExternalAutomationSource
  ) {
    submit(actions.map(ExternalAutomationRequest.action), source: source)
  }

  func submit(
    _ requests: [ExternalAutomationRequest],
    source: ExternalAutomationSource
  ) {
    guard !requests.isEmpty else {
      return
    }

    let previous = tail
    let client = client
    let presenter = presenter
    tail = Task { @MainActor in
      await previous?.value

      var failures: [ExternalAutomationFailure] = []
      for request in requests {
        switch request {
        case let .failure(failure):
          failures.append(failure)
        case let .action(action):
          if let failure = await Self.execute(
            action,
            client: client,
            presenter: presenter,
            source: source
          ) {
            failures.append(failure)
          }
        }
      }

      if !failures.isEmpty {
        presenter.presentFailures(failures, source: source)
      }
    }
  }

  /// Submits one action through the same serial chain and reports the outcome to the caller.
  /// Sources with a synchronous result channel (Services) use this to surface failures
  /// themselves; the in-app failure alert is still presented.
  func submitAndWait(
    _ action: ExternalAutomationAction,
    source: ExternalAutomationSource
  ) async -> ExternalAutomationFailure? {
    let previous = tail
    let client = client
    let presenter = presenter
    let task = Task { @MainActor in
      await previous?.value

      let failure = await Self.execute(
        action,
        client: client,
        presenter: presenter,
        source: source
      )
      if let failure {
        presenter.presentFailures([failure], source: source)
      }
      return failure
    }
    tail = Task { @MainActor in
      _ = await task.value
    }
    return await task.value
  }

  private static func execute(
    _ action: ExternalAutomationAction,
    client: any AgentLockActionServing,
    presenter: any ExternalAutomationPresenting,
    source: ExternalAutomationSource
  ) async -> ExternalAutomationFailure? {
    do {
      switch action {
      case .lock:
        try await client.lock()
      case .unlock:
        try await client.unlock()
      case .status:
        let isLocked = try await client.status()
        presenter.presentStatus(isLocked: isLocked, source: source)
      }
      return nil
    } catch {
      return ExternalAutomationFailure(error: error)
    }
  }

  func waitUntilIdle() async {
    await tail?.value
  }
}
