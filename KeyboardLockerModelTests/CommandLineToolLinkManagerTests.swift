import Foundation
import Testing

@Suite(.serialized)
final class CommandLineToolLinkManagerTests {
  private let temporaryDirectory: URL

  init() throws {
    temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: temporaryDirectory,
      withIntermediateDirectories: true
    )
  }

  deinit {
    try? FileManager.default.removeItem(at: temporaryDirectory)
  }

  @Test
  @MainActor
  func installAndUninstallManageOnlySymbolicLink() throws {
    let source = try makeExecutable(named: "klock")
    let binDirectory = temporaryDirectory.appendingPathComponent("bin", isDirectory: true)
    let destination = binDirectory.appendingPathComponent("klock")
    let manager = makeManager(
      source: source,
      destination: destination,
      pathDirectories: [binDirectory]
    )

    #expect(
      manager.state ==
        .notInstalled(destination: destination, requiresPathSetup: false)
    )

    #expect(try manager.install() == .installed(destination: destination))
    #expect(manager.canRemoveLink(at: destination))
    #expect(
      try FileManager.default.destinationOfSymbolicLink(atPath: destination.path) ==
        source.path
    )

    #expect(
      try manager.uninstall() ==
        .notInstalled(destination: destination, requiresPathSetup: false)
    )
    #expect(!FileManager.default.fileExists(atPath: destination.path))
    #expect(FileManager.default.fileExists(atPath: source.path))
  }

  @Test
  @MainActor
  func installIsIdempotentForOwnedSymbolicLink() throws {
    let source = try makeExecutable(named: "klock")
    let binDirectory = temporaryDirectory.appendingPathComponent("bin", isDirectory: true)
    let destination = binDirectory.appendingPathComponent("klock")
    let manager = makeManager(
      source: source,
      destination: destination,
      pathDirectories: [binDirectory]
    )

    _ = try manager.install()
    #expect(try manager.install() == .installed(destination: destination))
  }

  @Test
  @MainActor
  func ownedSymbolicLinkCanBeRemovedWhenBundledExecutableDisappears() throws {
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

    #expect(manager.state == .installed(destination: destination))
    #expect(
      try manager.uninstall() ==
        .sourceUnavailable(source)
    )
    #expect(throws: (any Error).self) {
      try FileManager.default.destinationOfSymbolicLink(atPath: destination.path)
    }
  }

  @Test
  @MainActor
  func foreignItemIsReportedAndNeverOverwritten() throws {
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

    #expect(manager.state == .conflict(destination: destination))
    let error = #expect(throws: CommandLineToolLinkManager.InstallationError.self) {
      try manager.install()
    }
    guard let error else { return }
    guard case .destinationConflict = error else {
      Issue.record("Expected a destination conflict, found \(error).")
      return
    }
    #expect(try Data(contentsOf: destination) == Data("foreign".utf8))
  }

  @Test
  @MainActor
  func missingPathDirectoryIsReportedWithoutEditingShellConfiguration() throws {
    let source = try makeExecutable(named: "klock")
    let binDirectory = temporaryDirectory.appendingPathComponent("bin", isDirectory: true)
    let destination = binDirectory.appendingPathComponent("klock")
    let manager = makeManager(
      source: source,
      destination: destination,
      pathDirectories: []
    )

    #expect(
      manager.state ==
        .notInstalled(destination: destination, requiresPathSetup: true)
    )
    #expect(manager.pathSetupCommand(for: destination).contains("export PATH="))
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
