import Client
import Foundation
import Testing

@Suite(.serialized)
struct ServiceCompatibilityTests {
  @Test
  func buildVersionsUseNumericComponentOrdering() throws {
    let older = try #require(ServiceBuildVersion("1.9"))
    let newer = try #require(ServiceBuildVersion("1.10"))
    let equivalent = try #require(ServiceBuildVersion("01.010.0"))

    #expect(older < newer)
    #expect(newer == equivalent)
  }

  @Test
  func buildVersionRejectsNonNumericComponents() {
    #expect(ServiceBuildVersion("") == nil)
    #expect(ServiceBuildVersion("1.beta") == nil)
    #expect(ServiceBuildVersion("1..2") == nil)
  }

  @Test
  func matchingDescriptorIsCompatible() throws {
    let requirements = makeRequirements()
    let descriptor = makeDescriptor(
      capabilities: requirements.requiredCapabilities.union([
        ServiceCapability(rawValue: "future-capability"),
      ])
    )

    #expect(descriptor.compatibilityIssues(against: requirements).isEmpty)
    try descriptor.validateCompatibility(against: requirements)
  }

  @Test
  func newerProtocolMinorIsCompatible() {
    let requirements = makeRequirements(
      minimumProtocolVersion: ServiceProtocolVersion(major: 1, minor: 2)
    )
    let descriptor = makeDescriptor(
      protocolVersion: ServiceProtocolVersion(major: 1, minor: 3)
    )

    #expect(descriptor.compatibilityIssues(against: requirements).isEmpty)
  }

  @Test
  func differentProtocolMajorIsIncompatible() {
    let requirements = makeRequirements(
      minimumProtocolVersion: ServiceProtocolVersion(major: 2, minor: 0)
    )
    let descriptor = makeDescriptor(
      protocolVersion: ServiceProtocolVersion(major: 1, minor: 99)
    )

    #expect(descriptor.compatibilityIssues(against: requirements) == [
      .protocolMajorMismatch(expected: 2, actual: 1),
    ])
  }

  @Test
  func olderProtocolMinorIsIncompatible() {
    let requirements = makeRequirements(
      minimumProtocolVersion: ServiceProtocolVersion(major: 1, minor: 2)
    )
    let descriptor = makeDescriptor(
      protocolVersion: ServiceProtocolVersion(major: 1, minor: 1)
    )

    #expect(descriptor.compatibilityIssues(against: requirements) == [
      .protocolMinorTooOld(required: 2, actual: 1),
    ])
  }

  @Test
  func missingCapabilitiesAreReportedInStableOrder() {
    let requirements = makeRequirements(requiredCapabilities: [
      .currentSettings,
      .lockControl,
      .prepareForReplacement,
    ])
    let descriptor = makeDescriptor(capabilities: [.lockControl])

    #expect(descriptor.compatibilityIssues(against: requirements) == [
      .missingCapabilities([.currentSettings, .prepareForReplacement]),
    ])
  }

  @Test
  func currentContractRequiresCommittedReplacementDrain() {
    #expect(ServiceContract.requiredCapabilities.contains(.committedReplacementDrain))
    #expect(ServiceContract.protocolVersion.minor >= 1)
  }

  @Test
  func currentContractRequiresErrorReportingSettingsSelector() {
    #expect(ServiceContract.requiredCapabilities.contains(.currentSettingsWithError))
    #expect(ServiceContract.protocolVersion.minor >= 2)
  }

  @Test
  func currentContractRequiresInteractiveLockSelector() {
    #expect(ServiceContract.requiredCapabilities.contains(.interactiveLock))
    #expect(ServiceContract.protocolVersion.minor >= 3)
  }

  @Test
  func currentContractRequiresLockStatusSnapshotSelector() {
    #expect(ServiceContract.requiredCapabilities.contains(.lockStatusSnapshot))
    #expect(ServiceContract.protocolVersion.minor >= 4)
  }

  @Test
  func currentContractRequiresFocusFilterLockSelector() {
    #expect(ServiceContract.requiredCapabilities.contains(.focusFilterLock))
    #expect(ServiceContract.protocolVersion.minor >= 5)
  }

  @Test
  func currentContractRequiresLockToggleSelector() {
    #expect(ServiceContract.requiredCapabilities.contains(.lockToggle))
    #expect(ServiceContract.protocolVersion.minor >= 6)
  }

  @Test
  func currentContractRequiresSafetyCheckSelector() {
    #expect(ServiceContract.requiredCapabilities.contains(.safetyCheckLock))
    #expect(ServiceContract.protocolVersion.minor >= 7)
  }

  @Test
  func agentWithoutCommittedDrainIsNotCurrentContractCompatible() {
    let requirements = makeRequirements()
    let descriptor = makeDescriptor(
      capabilities: requirements.requiredCapabilities.subtracting([
        .committedReplacementDrain,
      ])
    )

    #expect(descriptor.compatibilityIssues(against: requirements) == [
      .missingCapabilities([.committedReplacementDrain]),
    ])
  }

  @Test
  func agentWithoutErrorReportingSettingsIsNotCurrentContractCompatible() {
    let requirements = makeRequirements()
    let descriptor = makeDescriptor(
      capabilities: requirements.requiredCapabilities.subtracting([
        .currentSettingsWithError,
      ])
    )

    #expect(descriptor.compatibilityIssues(against: requirements) == [
      .missingCapabilities([.currentSettingsWithError]),
    ])
  }

  @Test
  func agentWithoutInteractiveLockIsNotCurrentContractCompatible() {
    let requirements = makeRequirements()
    let descriptor = makeDescriptor(
      capabilities: requirements.requiredCapabilities.subtracting([
        .interactiveLock,
      ])
    )

    #expect(descriptor.compatibilityIssues(against: requirements) == [
      .missingCapabilities([.interactiveLock]),
    ])
  }

  @Test
  func agentWithoutLockStatusSnapshotIsNotCurrentContractCompatible() {
    let requirements = makeRequirements()
    let descriptor = makeDescriptor(
      capabilities: requirements.requiredCapabilities.subtracting([
        .lockStatusSnapshot,
      ])
    )

    #expect(descriptor.compatibilityIssues(against: requirements) == [
      .missingCapabilities([.lockStatusSnapshot]),
    ])
  }

  @Test
  func agentWithoutFocusFilterLockIsNotCurrentContractCompatible() {
    let requirements = makeRequirements()
    let descriptor = makeDescriptor(
      capabilities: requirements.requiredCapabilities.subtracting([
        .focusFilterLock,
      ])
    )

    #expect(descriptor.compatibilityIssues(against: requirements) == [
      .missingCapabilities([.focusFilterLock]),
    ])
  }

  @Test
  func buildMismatchRequiresReplacement() {
    let requirements = makeRequirements(agentBuild: "42")
    let descriptor = makeDescriptor(agentBuild: "41")

    #expect(descriptor.compatibilityIssues(against: requirements) == [
      .agentBuildMismatch(expected: "42", actual: "41"),
    ])
  }

  @Test
  func descriptorRoundTripPreservesUnknownCapabilities() throws {
    let descriptor = makeDescriptor(capabilities: [
      .lockControl,
      ServiceCapability(rawValue: "capability-added-by-a-newer-agent"),
    ], replacementPhase: .prepared)

    let decoded = try ServiceDescriptor.decodedFromXPC(descriptor.encodedForXPC())

    #expect(decoded == descriptor)
  }

  @Test
  func descriptorDecodesLegacyPayloadWithoutAdditiveField() throws {
    let instanceID = UUID()
    let payload = """
    {
      "protocolVersion": {"major": 1, "minor": 0},
      "capabilities": ["lock-control"],
      "agentBundleIdentifier": "\(SharedConstants.agentBundleIdentifier)",
      "agentVersion": "1.0",
      "agentBuild": "1",
      "agentInstanceID": "\(instanceID.uuidString)"
    }
    """.data(using: .utf8)

    let descriptor = try ServiceDescriptor.decodedFromXPC(payload)

    #expect(descriptor.agentInstanceID == instanceID)
    #expect(!descriptor.replacementPending)
    #expect(descriptor.replacementPhase == .inactive)
  }

  @Test
  func descriptorIgnoresFutureFields() throws {
    let descriptor = makeDescriptor()
    var object = try #require(
      JSONSerialization.jsonObject(with: descriptor.encodedForXPC()) as? [String: Any]
    )
    object["fieldAddedByFutureMinorVersion"] = ["value": 42]
    let futurePayload = try JSONSerialization.data(withJSONObject: object)

    #expect(try ServiceDescriptor.decodedFromXPC(futurePayload) == descriptor)
  }

  @Test
  func descriptorMapsPendingLegacyPayloadToUnknownPhase() throws {
    let descriptor = makeDescriptor()
    var object = try #require(
      JSONSerialization.jsonObject(with: descriptor.encodedForXPC()) as? [String: Any]
    )
    object["replacementPending"] = true
    object.removeValue(forKey: "replacementPhase")
    let legacyPayload = try JSONSerialization.data(withJSONObject: object)

    let decoded = try ServiceDescriptor.decodedFromXPC(legacyPayload)

    #expect(decoded.replacementPending)
    #expect(decoded.replacementPhase == .unknown)
  }

  @Test
  func descriptorPreservesFutureReplacementPhase() throws {
    let futurePhase = ServiceReplacementPhase(rawValue: "future-phase")
    let descriptor = makeDescriptor(replacementPhase: futurePhase)

    let decoded = try ServiceDescriptor.decodedFromXPC(descriptor.encodedForXPC())

    #expect(decoded.replacementPhase == futurePhase)
    #expect(decoded.replacementPending)
  }

  @Test
  func descriptorRejectsMissingRequiredBootstrapField() throws {
    let descriptor = makeDescriptor()
    var object = try #require(
      JSONSerialization.jsonObject(with: descriptor.encodedForXPC()) as? [String: Any]
    )
    object.removeValue(forKey: "protocolVersion")
    let invalidPayload = try JSONSerialization.data(withJSONObject: object)

    #expect(throws: (any Error).self) {
      try ServiceDescriptor.decodedFromXPC(invalidPayload)
    }
  }

  @Test
  func replacementTicketRoundTrip() throws {
    let ticket = ServiceReplacementTicket(
      id: UUID(),
      agentInstanceID: UUID()
    )

    #expect(try ServiceReplacementTicket.decodedFromXPC(ticket.encodedForXPC()) == ticket)
  }

  @Test
  func replacementStatusRoundTrip() throws {
    let status = ServiceReplacementStatus(phase: .committed)

    #expect(try ServiceReplacementStatus.decodedFromXPC(status.encodedForXPC()) == status)
  }

  private func makeRequirements(
    minimumProtocolVersion: ServiceProtocolVersion = ServiceContract.protocolVersion,
    requiredCapabilities: Set<ServiceCapability> = ServiceContract.requiredCapabilities,
    agentBundleIdentifier: String = SharedConstants.agentBundleIdentifier,
    agentVersion: String = "1.0",
    agentBuild: String = "1"
  ) -> ServiceCompatibilityRequirements {
    ServiceCompatibilityRequirements(
      minimumProtocolVersion: minimumProtocolVersion,
      requiredCapabilities: requiredCapabilities,
      agentBundleIdentifier: agentBundleIdentifier,
      agentVersion: agentVersion,
      agentBuild: agentBuild
    )
  }

  private func makeDescriptor(
    protocolVersion: ServiceProtocolVersion = ServiceContract.protocolVersion,
    capabilities: Set<ServiceCapability> = ServiceContract.requiredCapabilities,
    agentBundleIdentifier: String = SharedConstants.agentBundleIdentifier,
    agentVersion: String = "1.0",
    agentBuild: String = "1",
    agentInstanceID: UUID = UUID(),
    replacementPhase: ServiceReplacementPhase = .inactive
  ) -> ServiceDescriptor {
    ServiceDescriptor(
      protocolVersion: protocolVersion,
      capabilities: capabilities,
      agentBundleIdentifier: agentBundleIdentifier,
      agentVersion: agentVersion,
      agentBuild: agentBuild,
      agentInstanceID: agentInstanceID,
      replacementPending: replacementPhase != .inactive,
      replacementPhase: replacementPhase
    )
  }
}
