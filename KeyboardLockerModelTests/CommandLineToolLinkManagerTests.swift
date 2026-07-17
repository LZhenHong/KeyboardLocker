import Foundation
import XCTest

final class CommandLineToolLinkManagerTests: XCTestCase {
  private var temporaryDirectory: URL!

  override func setUpWithError() throws {
    temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: temporaryDirectory,
      withIntermediateDirectories: true
    )
  }

  override func tearDownWithError() throws {
    if let temporaryDirectory {
      try? FileManager.default.removeItem(at: temporaryDirectory)
    }
    temporaryDirectory = nil
  }

  @MainActor
  func testInstallAndUninstallManageOnlySymbolicLink() throws {
    let source = try makeExecutable(named: "klock")
    let binDirectory = temporaryDirectory.appendingPathComponent("bin", isDirectory: true)
    let destination = binDirectory.appendingPathComponent("klock")
    let manager = makeManager(
      source: source,
      destination: destination,
      pathDirectories: [binDirectory]
    )

    XCTAssertEqual(
      manager.state,
      .notInstalled(destination: destination, requiresPathSetup: false)
    )

    XCTAssertEqual(try manager.install(), .installed(destination: destination))
    XCTAssertTrue(manager.canRemoveLink(at: destination))
    XCTAssertEqual(
      try FileManager.default.destinationOfSymbolicLink(atPath: destination.path),
      source.path
    )

    XCTAssertEqual(
      try manager.uninstall(),
      .notInstalled(destination: destination, requiresPathSetup: false)
    )
    XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
  }

  @MainActor
  func testInstallIsIdempotentForOwnedSymbolicLink() throws {
    let source = try makeExecutable(named: "klock")
    let binDirectory = temporaryDirectory.appendingPathComponent("bin", isDirectory: true)
    let destination = binDirectory.appendingPathComponent("klock")
    let manager = makeManager(
      source: source,
      destination: destination,
      pathDirectories: [binDirectory]
    )

    _ = try manager.install()
    XCTAssertEqual(try manager.install(), .installed(destination: destination))
  }

  @MainActor
  func testOwnedSymbolicLinkCanBeRemovedWhenBundledExecutableDisappears() throws {
    let source = try makeExecutable(named: "klock")
    let binDirectory = temporaryDirectory.appendingPathComponent("bin", isDirectory: true)
    let destination = binDirectory.appendingPathComponent("klock")
    let manager = makeManager(
      source: source,
      destination: destination,
      pathDirectories: [binDirectory]
    )

    _ = try manager.install()
    try FileManager.default.removeItem(at: source)

    XCTAssertEqual(manager.state, .installed(destination: destination))
    XCTAssertEqual(
      try manager.uninstall(),
      .sourceUnavailable(source)
    )
    XCTAssertThrowsError(
      try FileManager.default.destinationOfSymbolicLink(atPath: destination.path)
    )
  }

  @MainActor
  func testForeignItemIsReportedAndNeverOverwritten() throws {
    let source = try makeExecutable(named: "klock")
    let binDirectory = temporaryDirectory.appendingPathComponent("bin", isDirectory: true)
    try FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)
    let destination = binDirectory.appendingPathComponent("klock")
    try Data("foreign".utf8).write(to: destination)
    let manager = makeManager(
      source: source,
      destination: destination,
      pathDirectories: [binDirectory]
    )

    XCTAssertEqual(manager.state, .conflict(destination: destination))
    XCTAssertThrowsError(try manager.install()) { error in
      guard let installationError = error as? CommandLineToolLinkManager.InstallationError,
            case .destinationConflict = installationError
      else {
        return XCTFail("Expected a destination conflict, found \(error).")
      }
    }
    XCTAssertEqual(try Data(contentsOf: destination), Data("foreign".utf8))
  }

  @MainActor
  func testMissingPathDirectoryIsReportedWithoutEditingShellConfiguration() throws {
    let source = try makeExecutable(named: "klock")
    let binDirectory = temporaryDirectory.appendingPathComponent("bin", isDirectory: true)
    let destination = binDirectory.appendingPathComponent("klock")
    let manager = makeManager(
      source: source,
      destination: destination,
      pathDirectories: []
    )

    XCTAssertEqual(
      manager.state,
      .notInstalled(destination: destination, requiresPathSetup: true)
    )
    XCTAssertTrue(manager.pathSetupCommand(for: destination).contains("export PATH="))
  }

  @MainActor
  private func makeManager(
    source: URL,
    destination: URL,
    pathDirectories: [URL]
  ) -> CommandLineToolLinkManager {
    CommandLineToolLinkManager(
      sourceURL: source,
      preferredDestination: destination,
      pathDirectories: pathDirectories
    )
  }

  private func makeExecutable(named name: String) throws -> URL {
    let executable = temporaryDirectory.appendingPathComponent(name)
    try Data("test".utf8).write(to: executable)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755],
      ofItemAtPath: executable.path
    )
    return executable
  }
}
