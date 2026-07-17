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
}

@MainActor
private final class FakeAgentRegistrationService: AgentRegistrationServing {
  private(set) var registrationCallCount = 0
  private(set) var status: SMAppService.Status

  private let registrationError: Error?
  private let statusAfterRegistration: SMAppService.Status

  init(
    status: SMAppService.Status,
    statusAfterRegistration: SMAppService.Status,
    registrationError: Error? = nil
  ) {
    self.status = status
    self.statusAfterRegistration = statusAfterRegistration
    self.registrationError = registrationError
  }

  func register() throws {
    registrationCallCount += 1
    if let registrationError {
      throw registrationError
    }
    status = statusAfterRegistration
  }
}

private enum RegistrationError: LocalizedError {
  case failed

  var errorDescription: String? {
    "Registration failed for testing."
  }
}
