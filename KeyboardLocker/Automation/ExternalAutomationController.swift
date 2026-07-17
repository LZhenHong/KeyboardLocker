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
          do {
            switch action {
            case .lock:
              try await client.lock()
            case .unlock:
              try await client.unlock()
            case .status:
              let isLocked = try await client.status()
              presenter.presentStatus(
                isLocked: isLocked,
                source: source
              )
            }
          } catch {
            failures.append(ExternalAutomationFailure(error: error))
          }
        }
      }

      if !failures.isEmpty {
        presenter.presentFailures(failures, source: source)
      }
    }
  }

  func waitUntilIdle() async {
    await tail?.value
  }
}
