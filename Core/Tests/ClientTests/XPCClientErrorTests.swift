@testable import Client
import Foundation
import Testing

@Suite(.serialized)
struct XPCClientErrorTests {
  @Test
  func proxyErrorsNormalizeToServiceUnavailable() {
    let transportError = NSError(
      domain: NSCocoaErrorDomain,
      code: CocoaError.xpcConnectionInvalid.rawValue
    )

    guard case XPCClientError.serviceUnavailable = XPCClient.normalizedProxyError(transportError)
    else {
      Issue.record("Expected the proxy error to normalize to serviceUnavailable.")
      return
    }
  }

  @Test
  func serviceUnavailableExplainsFirstUseRecovery() throws {
    let suggestion = try #require(XPCClientError.serviceUnavailable.recoverySuggestion)

    #expect(suggestion.contains("Open KeyboardLocker once"))
    #expect(suggestion.contains("Show Details"))
  }

  @Test
  func timeoutExplainsRetryRecovery() throws {
    let suggestion = try #require(XPCClientError.timedOut.recoverySuggestion)

    #expect(suggestion.contains("Retry"))
    #expect(suggestion.contains("Show Details"))
  }

  @Test
  func missingCapabilityExplainsAgentUpdateRecovery() throws {
    let suggestion = try #require(
      XPCClientError.missingCapability(.interactiveLock).recoverySuggestion
    )

    #expect(suggestion.contains("update its background agent"))
  }

  @Test
  func unknownMutationOutcomeExplainsStateRecovery() throws {
    let suggestion = try #require(
      XPCClientError.operationOutcomeUnknown.recoverySuggestion
    )

    #expect(suggestion.contains("Inspect the current state"))
    #expect(suggestion.contains("repeat the intended lock or unlock action"))
  }

  @Test
  func featureNegotiationRejectsProtocolMajorBeforeCapabilities() {
    let descriptor = makeDescriptor(
      protocolVersion: ServiceProtocolVersion(major: 2, minor: 99),
      capabilities: []
    )

    #expect(throws: ServiceCompatibilityIssue.protocolMajorMismatch(expected: 1, actual: 2)) {
      try XPCFeatureNegotiation.validate(
        descriptor: descriptor,
        requiring: [.lockToggle]
      )
    }
  }

  @Test
  func featureNegotiationEnforcesSelectorIntroductionMinor() {
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
      .safetyCheckLock: 7,
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

      #expect(
        throws: ServiceCompatibilityIssue.protocolMinorTooOld(
          required: introductionMinor,
          actual: introductionMinor - 1
        ),
        "Expected \(capability.rawValue) to require protocol minor \(introductionMinor)."
      ) {
        try XPCFeatureNegotiation.validate(
          descriptor: descriptor,
          requiring: [capability]
        )
      }
    }
  }

  @Test
  func featureNegotiationAcceptsDeclaredCapabilityAtIntroductionMinor() throws {
    let descriptor = makeDescriptor(
      protocolVersion: ServiceProtocolVersion(
        major: ServiceContract.protocolVersion.major,
        minor: 3
      ),
      capabilities: [.interactiveLock]
    )

    try XPCFeatureNegotiation.validate(
      descriptor: descriptor,
      requiring: [.interactiveLock]
    )
  }

  @Test
  func featureNegotiationChecksCapabilityAfterCompatibleVersion() {
    let descriptor = makeDescriptor(
      protocolVersion: ServiceContract.protocolVersion,
      capabilities: []
    )

    do {
      try XPCFeatureNegotiation.validate(
        descriptor: descriptor,
        requiring: [.interactiveLock]
      )
      Issue.record("Expected missing interactive-lock capability.")
    } catch XPCClientError.missingCapability(.interactiveLock) {
      // Expected.
    } catch {
      Issue.record("Expected missing interactive-lock capability, got \(error).")
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
