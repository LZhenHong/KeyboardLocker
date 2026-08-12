@testable import Common
import Foundation
import Security
import Testing

/// Evaluates XPC peer requirements against real on-disk code signatures.
///
/// `XPCCodeSigningRequirementTests` covers requirement-string construction only; these tests
/// prove the fail-closed direction end to end. Using static evaluation (no process execution),
/// code that is not signed by our team — a foreign Apple signature, an ad-hoc signature, or no
/// signature at all — must be rejected by the same Security framework check the Agent's
/// listener performs. A plain `anchor apple` control requirement proves the harness evaluates
/// correctly, so failures are requirement mismatches rather than evaluation errors.
@Suite(.serialized)
struct XPCCodeSigningRequirementEvaluationTests {
  // MARK: - Team requirement vs. real signatures

  @Test
  func appleSignedSystemToolFailsTeamRequirementButPassesAnchorApple() throws {
    let tool = try makeSystemToolCopy()
    defer { try? FileManager.default.removeItem(at: tool.deletingLastPathComponent()) }

    let requirement = try makeTeamRequirement()

    // Control: the copy keeps the embedded Apple signature, so the anchor check passes.
    #expect(evaluate("anchor apple", against: tool) == errSecSuccess)
    // Rejected: valid Apple signature, but not our Team ID or identifier.
    #expect(evaluate(requirement, against: tool) == errSecCSReqFailed)
  }

  @Test
  func adHocSignedToolFailsTeamRequirement() throws {
    let tool = try makeSystemToolCopy()
    defer { try? FileManager.default.removeItem(at: tool.deletingLastPathComponent()) }
    try runCodesign(["--force", "--sign", "-", tool.path])

    let requirement = try makeTeamRequirement()

    // Control: ad-hoc signatures never anchor to Apple.
    #expect(evaluate("anchor apple", against: tool) == errSecCSReqFailed)
    // Rejected: an ad-hoc signature carries no Apple Team ID.
    #expect(evaluate(requirement, against: tool) == errSecCSReqFailed)
  }

  @Test
  func unsignedToolFailsTeamRequirement() throws {
    let tool = try makeSystemToolCopy()
    defer { try? FileManager.default.removeItem(at: tool.deletingLastPathComponent()) }
    try runCodesign(["--remove-signature", tool.path])

    let requirement = try makeTeamRequirement()

    // Rejected: unsigned code fails before any requirement clause is even considered.
    #expect(evaluate("anchor apple", against: tool) == errSecCSUnsigned)
    #expect(evaluate(requirement, against: tool) == errSecCSUnsigned)
  }

  // MARK: - Fixtures

  /// Copies the Apple-signed system tool into a fresh per-test directory so tests may mutate
  /// its signature freely. The caller removes the directory with `defer`.
  private func makeSystemToolCopy() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    let copy = directory.appendingPathComponent("ls")
    try FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/ls"), to: copy)
    return copy
  }

  private func makeTeamRequirement() throws -> String {
    try XPCCodeSigningRequirement.make(
      teamIdentifier: "A1B2C3D4E5",
      identifiers: ["io.example.tool"]
    )
  }

  private func runCodesign(_ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
    process.arguments = arguments
    let standardError = Pipe()
    process.standardError = standardError
    try process.run()
    // Drain before reaping so a full pipe can never deadlock the child.
    let output = String(
      data: standardError.fileHandleForReading.readDataToEndOfFile(),
      encoding: .utf8
    ) ?? ""
    process.waitUntilExit()
    #expect(
      process.terminationStatus == 0,
      "codesign \(arguments.joined(separator: " ")) failed: \(output)"
    )
  }

  /// Runs the same static requirement evaluation the Agent's listener performs.
  private func evaluate(_ requirement: String, against url: URL) -> OSStatus {
    var staticCode: SecStaticCode?
    let createStatus = SecStaticCodeCreateWithPath(url as CFURL, SecCSFlags(), &staticCode)
    guard createStatus == errSecSuccess, let staticCode else {
      return createStatus
    }

    var compiledRequirement: SecRequirement?
    let compileStatus = SecRequirementCreateWithString(
      requirement as CFString,
      SecCSFlags(),
      &compiledRequirement
    )
    guard compileStatus == errSecSuccess, let compiledRequirement else {
      return compileStatus
    }

    return SecStaticCodeCheckValidity(staticCode, SecCSFlags(), compiledRequirement)
  }
}
