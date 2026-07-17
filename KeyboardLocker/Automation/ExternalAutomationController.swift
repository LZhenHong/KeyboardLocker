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
    submit([action], source: source)
  }

  func submit(
    _ actions: [ExternalAutomationAction],
    source: ExternalAutomationSource
  ) {
    guard !actions.isEmpty else {
      return
    }

    let previous = tail
    let client = client
    let presenter = presenter
    tail = Task { @MainActor in
      await previous?.value

      var failures: [ExternalAutomationFailure] = []
      for action in actions {
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

      if !failures.isEmpty {
        presenter.presentFailures(failures, source: source)
      }
    }
  }

  func waitUntilIdle() async {
    await tail?.value
  }
}
