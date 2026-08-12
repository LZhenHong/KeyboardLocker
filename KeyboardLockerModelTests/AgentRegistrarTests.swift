import ServiceManagement
import Testing

@Suite(.serialized)
struct AgentRegistrarTests {
  @Test
  @MainActor
  func notFoundWithValidBundledAssetsAttemptsRegistration() {
    let service = FakeAgentRegistrationService(
      status: .notFound,
      statusAfterRegistration: .enabled
    )

    let state = AgentRegistrar.ensureEnabled(
      service: service,
      validateBundledRegistration: {}
    )

    #expect(state == .enabled)
    #expect(service.registrationCallCount == 1)
  }

  @Test
  @MainActor
  func notFoundWithMissingBundledAssetsDoesNotAttemptRegistration() {
    let service = FakeAgentRegistrationService(
      status: .notFound,
      statusAfterRegistration: .enabled
    )

    let state = AgentRegistrar.ensureEnabled(
      service: service,
      validateBundledRegistration: {
        throw AgentRegistrar.Failure.notFound
      }
    )

    #expect(state == .unavailable(.notFound))
    #expect(service.registrationCallCount == 0)
  }

  @Test
  @MainActor
  func notFoundRegistrationFailurePreservesUnderlyingError() {
    let service = FakeAgentRegistrationService(
      status: .notFound,
      statusAfterRegistration: .notFound,
      registrationError: RegistrationError.failed
    )

    let state = AgentRegistrar.ensureEnabled(
      service: service,
      validateBundledRegistration: {}
    )

    #expect(
      state ==
        .unavailable(.registrationFailed("Registration failed for testing."))
    )
    #expect(service.registrationCallCount == 1)
  }

  @Test
  @MainActor
  func unregisterRemovesEnabledService() async throws {
    let service = FakeAgentRegistrationService(
      status: .enabled,
      statusAfterRegistration: .enabled,
      statusAfterUnregistration: .notRegistered
    )

    try await AgentRegistrar.unregister(service: service)

    #expect(service.status == .notRegistered)
    #expect(service.unregistrationCallCount == 1)
  }

  @Test
  @MainActor
  func unregisterIsIdempotentWhenServiceIsNotFound() async throws {
    let service = FakeAgentRegistrationService(
      status: .notFound,
      statusAfterRegistration: .enabled
    )

    try await AgentRegistrar.unregister(service: service)

    #expect(service.status == .notFound)
    #expect(service.unregistrationCallCount == 0)
  }

  @Test
  @MainActor
  func unregisterPreservesUnderlyingError() async {
    let service = FakeAgentRegistrationService(
      status: .enabled,
      statusAfterRegistration: .enabled,
      unregistrationError: RegistrationError.failed
    )

    do {
      try await AgentRegistrar.unregister(service: service)
      Issue.record("Expected unregister to throw.")
    } catch {
      #expect(error.localizedDescription == "Registration failed for testing.")
    }
    #expect(service.unregistrationCallCount == 1)
  }
}

@MainActor
private final class FakeAgentRegistrationService: AgentRegistrationServing {
  private(set) var registrationCallCount = 0
  private(set) var unregistrationCallCount = 0
  private(set) var status: SMAppService.Status

  private let registrationError: Error?
  private let statusAfterRegistration: SMAppService.Status
  private let statusAfterUnregistration: SMAppService.Status
  private let unregistrationError: Error?

  init(
    status: SMAppService.Status,
    statusAfterRegistration: SMAppService.Status,
    registrationError: Error? = nil,
    statusAfterUnregistration: SMAppService.Status = .notRegistered,
    unregistrationError: Error? = nil
  ) {
    self.status = status
    self.statusAfterRegistration = statusAfterRegistration
    self.registrationError = registrationError
    self.statusAfterUnregistration = statusAfterUnregistration
    self.unregistrationError = unregistrationError
  }

  func register() throws {
    registrationCallCount += 1
    if let registrationError {
      throw registrationError
    }
    status = statusAfterRegistration
  }

  func unregister() async throws {
    unregistrationCallCount += 1
    if let unregistrationError {
      throw unregistrationError
    }
    status = statusAfterUnregistration
  }
}

private enum RegistrationError: LocalizedError {
  case failed

  var errorDescription: String? {
    "Registration failed for testing."
  }
}
