@testable import Client
import Foundation
import XCTest

final class XPCClientErrorTests: XCTestCase {
  func testProxyErrorsNormalizeToServiceUnavailable() {
    let transportError = NSError(
      domain: NSCocoaErrorDomain,
      code: CocoaError.xpcConnectionInvalid.rawValue
    )

    guard case XPCClientError.serviceUnavailable = XPCClient.normalizedProxyError(transportError)
    else {
      return XCTFail("Expected the proxy error to normalize to serviceUnavailable.")
    }
  }

  func testServiceUnavailableExplainsFirstUseRecovery() throws {
    let suggestion = try XCTUnwrap(XPCClientError.serviceUnavailable.recoverySuggestion)

    XCTAssertTrue(suggestion.contains("Open KeyboardLocker once"))
    XCTAssertTrue(suggestion.contains("Show Details"))
  }

  func testTimeoutExplainsRetryRecovery() throws {
    let suggestion = try XCTUnwrap(XPCClientError.timedOut.recoverySuggestion)

    XCTAssertTrue(suggestion.contains("Retry"))
    XCTAssertTrue(suggestion.contains("Show Details"))
  }

  func testMissingCapabilityExplainsAgentUpdateRecovery() throws {
    let suggestion = try XCTUnwrap(
      XPCClientError.missingCapability(.interactiveLock).recoverySuggestion
    )

    XCTAssertTrue(suggestion.contains("update its background agent"))
  }

  func testUnknownMutationOutcomeExplainsStateRecovery() throws {
    let suggestion = try XCTUnwrap(
      XPCClientError.operationOutcomeUnknown.recoverySuggestion
    )

    XCTAssertTrue(suggestion.contains("Inspect the current state"))
    XCTAssertTrue(suggestion.contains("repeat the intended lock or unlock action"))
  }

  func testFeatureNegotiationRejectsProtocolMajorBeforeCapabilities() {
    let descriptor = makeDescriptor(
      protocolVersion: ServiceProtocolVersion(major: 2, minor: 99),
      capabilities: []
    )

    XCTAssertThrowsError(
      try XPCFeatureNegotiation.validate(
        descriptor: descriptor,
        requiring: [.lockToggle]
      )
    ) { error in
      XCTAssertEqual(
        error as? ServiceCompatibilityIssue,
        .protocolMajorMismatch(expected: 1, actual: 2)
      )
    }
  }

  func testFeatureNegotiationEnforcesSelectorIntroductionMinor() {
    let introductionMinorByCapability: [ServiceCapability: Int] = [
      .accessibilityPrompt: 0,
      .accessibilityStatus: 0,
      .committedReplacementDrain: 1,
      .currentSettings: 1,
      .currentSettingsWithError: 2,
      .focusFilterLock: 5,
      .interactiveLock: 3,
      .lockControl: 0,
      .lockStatusSnapshot: 4,
      .lockToggle: 6,
      .prepareForReplacement: 0,
    ]

    for (capability, introductionMinor) in introductionMinorByCapability {
      guard introductionMinor > 0 else {
        continue
      }
      let descriptor = makeDescriptor(
        protocolVersion: ServiceProtocolVersion(
          major: ServiceContract.protocolVersion.major,
          minor: introductionMinor - 1
        ),
        capabilities: [capability]
      )

      XCTAssertThrowsError(
        try XPCFeatureNegotiation.validate(
          descriptor: descriptor,
          requiring: [capability]
        ),
        "Expected \(capability.rawValue) to require protocol minor \(introductionMinor)."
      ) { error in
        XCTAssertEqual(
          error as? ServiceCompatibilityIssue,
          .protocolMinorTooOld(required: introductionMinor, actual: introductionMinor - 1)
        )
      }
    }
  }

  func testFeatureNegotiationAcceptsDeclaredCapabilityAtIntroductionMinor() {
    let descriptor = makeDescriptor(
      protocolVersion: ServiceProtocolVersion(
        major: ServiceContract.protocolVersion.major,
        minor: 3
      ),
      capabilities: [.interactiveLock]
    )

    XCTAssertNoThrow(
      try XPCFeatureNegotiation.validate(
        descriptor: descriptor,
        requiring: [.interactiveLock]
      )
    )
  }

  func testFeatureNegotiationChecksCapabilityAfterCompatibleVersion() {
    let descriptor = makeDescriptor(
      protocolVersion: ServiceContract.protocolVersion,
      capabilities: []
    )

    XCTAssertThrowsError(
      try XPCFeatureNegotiation.validate(
        descriptor: descriptor,
        requiring: [.interactiveLock]
      )
    ) { error in
      guard case XPCClientError.missingCapability(.interactiveLock) = error else {
        return XCTFail("Expected missing interactive-lock capability, got \(error).")
      }
    }
  }

  private func makeDescriptor(
    protocolVersion: ServiceProtocolVersion,
    capabilities: Set<ServiceCapability>
  ) -> ServiceDescriptor {
    ServiceDescriptor(
      protocolVersion: protocolVersion,
      capabilities: capabilities,
      agentBundleIdentifier: SharedConstants.agentBundleIdentifier,
      agentVersion: "1.0",
      agentBuild: "1",
      agentInstanceID: UUID()
    )
  }
}
