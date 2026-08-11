import Client
import Foundation
import XCTest

final class ServiceCompatibilityTests: XCTestCase {
  func testBuildVersionsUseNumericComponentOrdering() throws {
    let older = try XCTUnwrap(ServiceBuildVersion("1.9"))
    let newer = try XCTUnwrap(ServiceBuildVersion("1.10"))
    let equivalent = try XCTUnwrap(ServiceBuildVersion("01.010.0"))

    XCTAssertLessThan(older, newer)
    XCTAssertEqual(newer, equivalent)
  }

  func testBuildVersionRejectsNonNumericComponents() {
    XCTAssertNil(ServiceBuildVersion(""))
    XCTAssertNil(ServiceBuildVersion("1.beta"))
    XCTAssertNil(ServiceBuildVersion("1..2"))
  }

  func testMatchingDescriptorIsCompatible() throws {
    let requirements = makeRequirements()
    let descriptor = makeDescriptor(
      capabilities: requirements.requiredCapabilities.union([
        ServiceCapability(rawValue: "future-capability"),
      ])
    )

    XCTAssertTrue(descriptor.compatibilityIssues(against: requirements).isEmpty)
    XCTAssertNoThrow(try descriptor.validateCompatibility(against: requirements))
  }

  func testNewerProtocolMinorIsCompatible() {
    let requirements = makeRequirements(
      minimumProtocolVersion: ServiceProtocolVersion(major: 1, minor: 2)
    )
    let descriptor = makeDescriptor(
      protocolVersion: ServiceProtocolVersion(major: 1, minor: 3)
    )

    XCTAssertTrue(descriptor.compatibilityIssues(against: requirements).isEmpty)
  }

  func testDifferentProtocolMajorIsIncompatible() {
    let requirements = makeRequirements(
      minimumProtocolVersion: ServiceProtocolVersion(major: 2, minor: 0)
    )
    let descriptor = makeDescriptor(
      protocolVersion: ServiceProtocolVersion(major: 1, minor: 99)
    )

    XCTAssertEqual(
      descriptor.compatibilityIssues(against: requirements),
      [.protocolMajorMismatch(expected: 2, actual: 1)]
    )
  }

  func testOlderProtocolMinorIsIncompatible() {
    let requirements = makeRequirements(
      minimumProtocolVersion: ServiceProtocolVersion(major: 1, minor: 2)
    )
    let descriptor = makeDescriptor(
      protocolVersion: ServiceProtocolVersion(major: 1, minor: 1)
    )

    XCTAssertEqual(
      descriptor.compatibilityIssues(against: requirements),
      [.protocolMinorTooOld(required: 2, actual: 1)]
    )
  }

  func testMissingCapabilitiesAreReportedInStableOrder() {
    let requirements = makeRequirements(requiredCapabilities: [
      .currentSettings,
      .lockControl,
      .prepareForReplacement,
    ])
    let descriptor = makeDescriptor(capabilities: [.lockControl])

    XCTAssertEqual(
      descriptor.compatibilityIssues(against: requirements),
      [.missingCapabilities([.currentSettings, .prepareForReplacement])]
    )
  }

  func testCurrentContractRequiresCommittedReplacementDrain() {
    XCTAssertTrue(
      ServiceContract.requiredCapabilities.contains(.committedReplacementDrain)
    )
    XCTAssertGreaterThanOrEqual(ServiceContract.protocolVersion.minor, 1)
  }

  func testCurrentContractRequiresErrorReportingSettingsSelector() {
    XCTAssertTrue(
      ServiceContract.requiredCapabilities.contains(.currentSettingsWithError)
    )
    XCTAssertGreaterThanOrEqual(ServiceContract.protocolVersion.minor, 2)
  }

  func testCurrentContractRequiresInteractiveLockSelector() {
    XCTAssertTrue(
      ServiceContract.requiredCapabilities.contains(.interactiveLock)
    )
    XCTAssertGreaterThanOrEqual(ServiceContract.protocolVersion.minor, 3)
  }

  func testCurrentContractRequiresLockStatusSnapshotSelector() {
    XCTAssertTrue(
      ServiceContract.requiredCapabilities.contains(.lockStatusSnapshot)
    )
    XCTAssertGreaterThanOrEqual(ServiceContract.protocolVersion.minor, 4)
  }

  func testCurrentContractRequiresFocusFilterLockSelector() {
    XCTAssertTrue(
      ServiceContract.requiredCapabilities.contains(.focusFilterLock)
    )
    XCTAssertGreaterThanOrEqual(ServiceContract.protocolVersion.minor, 5)
  }

  func testCurrentContractRequiresLockToggleSelector() {
    XCTAssertTrue(
      ServiceContract.requiredCapabilities.contains(.lockToggle)
    )
    XCTAssertGreaterThanOrEqual(ServiceContract.protocolVersion.minor, 6)
  }

  func testAgentWithoutCommittedDrainIsNotCurrentContractCompatible() {
    let requirements = makeRequirements()
    let descriptor = makeDescriptor(
      capabilities: requirements.requiredCapabilities.subtracting([
        .committedReplacementDrain,
      ])
    )

    XCTAssertEqual(
      descriptor.compatibilityIssues(against: requirements),
      [.missingCapabilities([.committedReplacementDrain])]
    )
  }

  func testAgentWithoutErrorReportingSettingsIsNotCurrentContractCompatible() {
    let requirements = makeRequirements()
    let descriptor = makeDescriptor(
      capabilities: requirements.requiredCapabilities.subtracting([
        .currentSettingsWithError,
      ])
    )

    XCTAssertEqual(
      descriptor.compatibilityIssues(against: requirements),
      [.missingCapabilities([.currentSettingsWithError])]
    )
  }

  func testAgentWithoutInteractiveLockIsNotCurrentContractCompatible() {
    let requirements = makeRequirements()
    let descriptor = makeDescriptor(
      capabilities: requirements.requiredCapabilities.subtracting([
        .interactiveLock,
      ])
    )

    XCTAssertEqual(
      descriptor.compatibilityIssues(against: requirements),
      [.missingCapabilities([.interactiveLock])]
    )
  }

  func testAgentWithoutLockStatusSnapshotIsNotCurrentContractCompatible() {
    let requirements = makeRequirements()
    let descriptor = makeDescriptor(
      capabilities: requirements.requiredCapabilities.subtracting([
        .lockStatusSnapshot,
      ])
    )

    XCTAssertEqual(
      descriptor.compatibilityIssues(against: requirements),
      [.missingCapabilities([.lockStatusSnapshot])]
    )
  }

  func testAgentWithoutFocusFilterLockIsNotCurrentContractCompatible() {
    let requirements = makeRequirements()
    let descriptor = makeDescriptor(
      capabilities: requirements.requiredCapabilities.subtracting([
        .focusFilterLock,
      ])
    )

    XCTAssertEqual(
      descriptor.compatibilityIssues(against: requirements),
      [.missingCapabilities([.focusFilterLock])]
    )
  }

  func testBuildMismatchRequiresReplacement() {
    let requirements = makeRequirements(agentBuild: "42")
    let descriptor = makeDescriptor(agentBuild: "41")

    XCTAssertEqual(
      descriptor.compatibilityIssues(against: requirements),
      [.agentBuildMismatch(expected: "42", actual: "41")]
    )
  }

  func testDescriptorRoundTripPreservesUnknownCapabilities() throws {
    let descriptor = makeDescriptor(capabilities: [
      .lockControl,
      ServiceCapability(rawValue: "capability-added-by-a-newer-agent"),
    ], replacementPhase: .prepared)

    let decoded = try ServiceDescriptor.decodedFromXPC(descriptor.encodedForXPC())

    XCTAssertEqual(decoded, descriptor)
  }

  func testDescriptorDecodesLegacyPayloadWithoutAdditiveField() throws {
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

    XCTAssertEqual(descriptor.agentInstanceID, instanceID)
    XCTAssertFalse(descriptor.replacementPending)
    XCTAssertEqual(descriptor.replacementPhase, .inactive)
  }

  func testDescriptorIgnoresFutureFields() throws {
    let descriptor = makeDescriptor()
    var object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: descriptor.encodedForXPC()) as? [String: Any]
    )
    object["fieldAddedByFutureMinorVersion"] = ["value": 42]
    let futurePayload = try JSONSerialization.data(withJSONObject: object)

    XCTAssertEqual(
      try ServiceDescriptor.decodedFromXPC(futurePayload),
      descriptor
    )
  }

  func testDescriptorMapsPendingLegacyPayloadToUnknownPhase() throws {
    let descriptor = makeDescriptor()
    var object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: descriptor.encodedForXPC()) as? [String: Any]
    )
    object["replacementPending"] = true
    object.removeValue(forKey: "replacementPhase")
    let legacyPayload = try JSONSerialization.data(withJSONObject: object)

    let decoded = try ServiceDescriptor.decodedFromXPC(legacyPayload)

    XCTAssertTrue(decoded.replacementPending)
    XCTAssertEqual(decoded.replacementPhase, .unknown)
  }

  func testDescriptorPreservesFutureReplacementPhase() throws {
    let futurePhase = ServiceReplacementPhase(rawValue: "future-phase")
    let descriptor = makeDescriptor(replacementPhase: futurePhase)

    let decoded = try ServiceDescriptor.decodedFromXPC(descriptor.encodedForXPC())

    XCTAssertEqual(decoded.replacementPhase, futurePhase)
    XCTAssertTrue(decoded.replacementPending)
  }

  func testDescriptorRejectsMissingRequiredBootstrapField() throws {
    let descriptor = makeDescriptor()
    var object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: descriptor.encodedForXPC()) as? [String: Any]
    )
    object.removeValue(forKey: "protocolVersion")
    let invalidPayload = try JSONSerialization.data(withJSONObject: object)

    XCTAssertThrowsError(try ServiceDescriptor.decodedFromXPC(invalidPayload))
  }

  func testReplacementTicketRoundTrip() throws {
    let ticket = ServiceReplacementTicket(
      id: UUID(),
      agentInstanceID: UUID()
    )

    XCTAssertEqual(
      try ServiceReplacementTicket.decodedFromXPC(ticket.encodedForXPC()),
      ticket
    )
  }

  func testReplacementStatusRoundTrip() throws {
    let status = ServiceReplacementStatus(phase: .committed)

    XCTAssertEqual(
      try ServiceReplacementStatus.decodedFromXPC(status.encodedForXPC()),
      status
    )
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
