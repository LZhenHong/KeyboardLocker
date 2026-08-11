@testable import Common
import Security
import Service
import XCTest

/// The listener's client requirement must fail closed on any host that cannot prove our
/// Team ID, and must name every authorized client whenever construction is possible.
final class XPCAccessControlTests: XCTestCase {
  func testAuthorizedClientRequirementFailsClosedWithoutAppleTeamSignature() {
    do {
      let requirement = try XPCAccessControl.authorizedClientRequirement()

      // Reachable only from a team-signed test host: construction succeeds, and the
      // requirement must still name every authorized client and compile. Both branches are
      // acceptable because each proves a distinct half of the contract — a signed host builds
      // the exact requirement, an unsigned host can build none.
      for identifier in SharedConstants.authorizedClientBundleIdentifiers {
        XCTAssertTrue(requirement.contains(#"identifier "\#(identifier)""#))
      }
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
    } catch let error as XPCCodeSigningRequirementError {
      // `swift test` binaries are ad-hoc signed, so the process has no Apple Team ID and the
      // requirement must fail closed rather than emit something an unauthorized client could
      // satisfy.
      guard case .missingTeamIdentifier = error else {
        return XCTFail("Expected missingTeamIdentifier, got \(error)")
      }
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }
}
