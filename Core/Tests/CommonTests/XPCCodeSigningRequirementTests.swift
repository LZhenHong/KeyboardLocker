@testable import Common
import Security
import XCTest

final class XPCCodeSigningRequirementTests: XCTestCase {
  func testAuthorizedClientIdentifiersAreExactAndNamespaced() {
    XCTAssertEqual(
      SharedConstants.authorizedClientBundleIdentifiers,
      [
        "io.lzhlovesjyq.keyboardlocker",
        "io.lzhlovesjyq.keyboardlocker.klock",
        "io.lzhlovesjyq.keyboardlocker.widgets",
      ]
    )
    XCTAssertEqual(
      SharedConstants.agentBundleIdentifier,
      "io.lzhlovesjyq.keyboardlocker.agent"
    )
  }

  func testRequirementUsesExactTeamAndIdentifiersInStableOrder() throws {
    let requirement = try XPCCodeSigningRequirement.make(
      teamIdentifier: "A1B2C3D4E5",
      identifiers: [
        "io.example.tool",
        "io.example.app",
      ]
    )

    XCTAssertEqual(
      requirement,
      """
      anchor apple generic and certificate leaf[subject.OU] = "A1B2C3D4E5" and \
      (identifier "io.example.app" or identifier "io.example.tool")
      """
    )

    var compiledRequirement: SecRequirement?
    XCTAssertEqual(
      SecRequirementCreateWithString(
        requirement as CFString,
        SecCSFlags(),
        &compiledRequirement
      ),
      errSecSuccess
    )
    XCTAssertNotNil(compiledRequirement)
  }

  func testRequirementRejectsInvalidTeamIdentifiers() {
    XCTAssertThrowsError(
      try XPCCodeSigningRequirement.make(
        teamIdentifier: "too-short",
        identifiers: ["io.example.app"]
      )
    )
    XCTAssertThrowsError(
      try XPCCodeSigningRequirement.make(
        teamIdentifier: "a1b2c3d4e5",
        identifiers: ["io.example.app"]
      )
    )
  }

  func testRequirementRejectsMissingOrUnsafeSigningIdentifiers() {
    XCTAssertThrowsError(
      try XPCCodeSigningRequirement.make(
        teamIdentifier: "A1B2C3D4E5",
        identifiers: []
      )
    )
    XCTAssertThrowsError(
      try XPCCodeSigningRequirement.make(
        teamIdentifier: "A1B2C3D4E5",
        identifiers: [#"io.example."injected"#]
      )
    )
  }
}
