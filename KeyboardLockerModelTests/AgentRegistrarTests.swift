import ServiceManagement
import XCTest

final class AgentRegistrarTests: XCTestCase {
  @MainActor
  func testNotFoundWithValidBundledAssetsAttemptsRegistration() {
    let service = FakeAgentRegistrationService(
      status: .notFound,
      statusAfterRegistration: .enabled
    )

    let state = AgentRegistrar.ensureEnabled(
      service: service,
      validateBundledRegistration: {}
    )

    XCTAssertEqual(state, .enabled)
    XCTAssertEqual(service.registrationCallCount, 1)
  }

  @MainActor
  func testNotFoundWithMissingBundledAssetsDoesNotAttemptRegistration() {
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

    XCTAssertEqual(state, .unavailable(.notFound))
    XCTAssertEqual(service.registrationCallCount, 0)
  }

  @MainActor
  func testNotFoundRegistrationFailurePreservesUnderlyingError() {
    let service = FakeAgentRegistrationService(
      status: .notFound,
      statusAfterRegistration: .notFound,
      registrationError: RegistrationError.failed
    )

    let state = AgentRegistrar.ensureEnabled(
      service: service,
      validateBundledRegistration: {}
    )

    XCTAssertEqual(
      state,
      .unavailable(.registrationFailed("Registration failed for testing."))
    )
    XCTAssertEqual(service.registrationCallCount, 1)
  }

  @MainActor
  func testUnregisterRemovesEnabledService() async throws {
    let service = FakeAgentRegistrationService(
      status: .enabled,
      statusAfterRegistration: .enabled,
      statusAfterUnregistration: .notRegistered
    )

    try await AgentRegistrar.unregister(service: service)

    XCTAssertEqual(service.status, .notRegistered)
    XCTAssertEqual(service.unregistrationCallCount, 1)
  }

  @MainActor
  func testUnregisterIsIdempotentWhenServiceIsNotFound() async throws {
    let service = FakeAgentRegistrationService(
      status: .notFound,
      statusAfterRegistration: .enabled
    )

    try await AgentRegistrar.unregister(service: service)

    XCTAssertEqual(service.status, .notFound)
    XCTAssertEqual(service.unregistrationCallCount, 0)
  }

  @MainActor
  func testUnregisterPreservesUnderlyingError() async {
    let service = FakeAgentRegistrationService(
      status: .enabled,
      statusAfterRegistration: .enabled,
      unregistrationError: RegistrationError.failed
    )

    do {
      try await AgentRegistrar.unregister(service: service)
      XCTFail("Expected unregister to throw.")
    } catch {
      XCTAssertEqual(error.localizedDescription, "Registration failed for testing.")
    }
    XCTAssertEqual(service.unregistrationCallCount, 1)
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
