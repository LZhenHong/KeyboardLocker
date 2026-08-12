@testable import Common
import Security
import Testing

@Suite(.serialized)
struct XPCCodeSigningRequirementTests {
  @Test
  func authorizedClientIdentifiersAreExactAndNamespaced() {
    #expect(SharedConstants.authorizedClientBundleIdentifiers == [
      "io.lzhlovesjyq.keyboardlocker",
      "io.lzhlovesjyq.keyboardlocker.focus-intents",
      "io.lzhlovesjyq.keyboardlocker.klock",
      "io.lzhlovesjyq.keyboardlocker.widgets",
    ])
    #expect(SharedConstants.agentBundleIdentifier == "io.lzhlovesjyq.keyboardlocker.agent")
  }

  @Test
  func requirementUsesExactTeamAndIdentifiersInStableOrder() throws {
    let requirement = try XPCCodeSigningRequirement.make(
      teamIdentifier: "A1B2C3D4E5",
      identifiers: [
        "io.example.tool",
        "io.example.app",
      ]
    )

    #expect(requirement == """
      anchor apple generic and certificate leaf[subject.OU] = "A1B2C3D4E5" and \
      (identifier "io.example.app" or identifier "io.example.tool")
      """
    )

    var compiledRequirement: SecRequirement?
    #expect(
      SecRequirementCreateWithString(
        requirement as CFString,
        SecCSFlags(),
        &compiledRequirement
      ) == errSecSuccess
    )
    #expect(compiledRequirement != nil)
  }

  @Test
  func requirementRejectsInvalidTeamIdentifiers() {
    #expect(throws: (any Error).self) {
      try XPCCodeSigningRequirement.make(
        teamIdentifier: "too-short",
        identifiers: ["io.example.app"]
      )
    }
    #expect(throws: (any Error).self) {
      try XPCCodeSigningRequirement.make(
        teamIdentifier: "a1b2c3d4e5",
        identifiers: ["io.example.app"]
      )
    }
  }

  @Test
  func requirementRejectsMissingOrUnsafeSigningIdentifiers() {
    #expect(throws: (any Error).self) {
      try XPCCodeSigningRequirement.make(
        teamIdentifier: "A1B2C3D4E5",
        identifiers: []
      )
    }
    #expect(throws: (any Error).self) {
      try XPCCodeSigningRequirement.make(
        teamIdentifier: "A1B2C3D4E5",
        identifiers: [#"io.example."injected"#]
      )
    }
  }
}
