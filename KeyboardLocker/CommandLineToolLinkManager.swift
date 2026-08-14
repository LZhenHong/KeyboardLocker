import Foundation

/// Manages a discoverability link for the bundled, signed `klock` executable.
///
/// The executable remains inside the App bundle so updates and XPC signing identity stay aligned.
/// This type only owns a symlink in a user-writable command directory; it never copies the binary,
/// edits shell profiles, or elevates privileges.
@MainActor
final class CommandLineToolLinkManager {
  enum State: Equatable {
    case conflict(destination: URL)
    case installed(destination: URL)
    case notInstalled(destination: URL, requiresPathSetup: Bool)
    case sourceUnavailable(URL)
  }

  enum InstallationError: Error, Equatable, LocalizedError {
    case destinationConflict(String)
    case destinationNotWritable(String)
    case sourceUnavailable(String)

    var errorDescription: String? {
      switch self {
      case let .destinationConflict(path):
        "A different item already exists at \(path). KeyboardLocker did not replace it."
      case let .destinationNotWritable(path):
        "KeyboardLocker cannot write to the command directory at \(path)."
      case let .sourceUnavailable(path):
        "The bundled klock executable is missing or not executable at \(path)."
      }
    }
  }

  private static let executableName = "klock"

  private let fileManager: FileManager
  private let managedDestinations: [URL]
  private let pathDirectoryPaths: Set<String>
  private let preferredDestination: URL
  private let sourceURL: URL

  convenience init(
    bundleURL: URL = Bundle.main.bundleURL,
    fileManager: FileManager = .default,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) {
    let homeDirectory = fileManager.homeDirectoryForCurrentUser
    let localBin = homeDirectory
      .appendingPathComponent(".local", isDirectory: true)
      .appendingPathComponent("bin", isDirectory: true)
    let homebrewBins = [
      URL(fileURLWithPath: "/opt/homebrew/bin", isDirectory: true),
      URL(fileURLWithPath: "/usr/local/bin", isDirectory: true),
    ]
    let knownDirectories = [localBin] + homebrewBins
    let pathDirectories = Self.pathDirectories(from: environment)

    let preferredDirectory = pathDirectories.first { candidate in
      knownDirectories.contains(where: { Self.pathsMatch($0, candidate) })
        && Self.canInstall(
          in: candidate,
          localBin: localBin,
          fileManager: fileManager
        )
    } ?? homebrewBins.first { candidate in
      let brew = candidate.appendingPathComponent("brew", isDirectory: false)
      return fileManager.isExecutableFile(atPath: brew.path)
        && fileManager.isWritableFile(atPath: candidate.path)
    } ?? localBin

    let destinations = ([preferredDirectory] + knownDirectories)
      .reduce(into: [URL]()) { result, directory in
        let destination = directory.appendingPathComponent(Self.executableName)
        guard !result.contains(where: { Self.pathsMatch($0, destination) }) else {
          return
        }
        result.append(destination)
      }

    self.init(
      sourceURL: bundleURL
        .appendingPathComponent("Contents", isDirectory: true)
        .appendingPathComponent("MacOS", isDirectory: true)
        .appendingPathComponent(Self.executableName, isDirectory: false),
      preferredDestination: preferredDirectory
        .appendingPathComponent(Self.executableName, isDirectory: false),
      managedDestinations: destinations,
      pathDirectories: pathDirectories,
      fileManager: fileManager
    )
  }

  init(
    sourceURL: URL,
    preferredDestination: URL,
    managedDestinations: [URL]? = nil,
    pathDirectories: [URL],
    fileManager: FileManager = .default
  ) {
    self.sourceURL = sourceURL.standardizedFileURL
    self.preferredDestination = preferredDestination.standardizedFileURL
    self.managedDestinations = (managedDestinations ?? [preferredDestination])
      .map(\.standardizedFileURL)
    pathDirectoryPaths = Set(pathDirectories.map(\.standardizedFileURL.path))
    self.fileManager = fileManager
  }

  var state: State {
    if let installedDestination = managedDestinations.first(where: pointsToBundledExecutable) {
      return .installed(destination: installedDestination)
    }

    guard fileManager.isExecutableFile(atPath: sourceURL.path) else {
      return .sourceUnavailable(sourceURL)
    }

    if itemExistsIncludingBrokenSymlink(at: preferredDestination) {
      return .conflict(destination: preferredDestination)
    }

    let directory = preferredDestination.deletingLastPathComponent().standardizedFileURL
    return .notInstalled(
      destination: preferredDestination,
      requiresPathSetup: !pathDirectoryPaths.contains(directory.path)
    )
  }

  @discardableResult
  func install() throws -> State {
    switch state {
    case .installed:
      return state

    case let .conflict(destination):
      throw InstallationError.destinationConflict(displayPath(destination))

    case let .sourceUnavailable(source):
      throw InstallationError.sourceUnavailable(displayPath(source))

    case let .notInstalled(destination, _):
      let directory = destination.deletingLastPathComponent()
      do {
        try fileManager.createDirectory(
          at: directory,
          withIntermediateDirectories: true
        )
      } catch {
        throw InstallationError.destinationNotWritable(displayPath(directory))
      }
      guard fileManager.isWritableFile(atPath: directory.path) else {
        throw InstallationError.destinationNotWritable(displayPath(directory))
      }
      do {
        try fileManager.createSymbolicLink(at: destination, withDestinationURL: sourceURL)
      } catch {
        if itemExistsIncludingBrokenSymlink(at: destination) {
          throw InstallationError.destinationConflict(displayPath(destination))
        }
        throw error
      }
      return state
    }
  }

  @discardableResult
  func uninstall() throws -> State {
    switch state {
    case let .installed(destination):
      try fileManager.removeItem(at: destination)
      return state

    case .notInstalled:
      return state

    case let .conflict(destination):
      throw InstallationError.destinationConflict(displayPath(destination))

    case let .sourceUnavailable(source):
      throw InstallationError.sourceUnavailable(displayPath(source))
    }
  }

  func displayPath(_ url: URL) -> String {
    let path = url.standardizedFileURL.path
    let homePath = fileManager.homeDirectoryForCurrentUser.standardizedFileURL.path
    guard path == homePath || path.hasPrefix("\(homePath)/") else {
      return path
    }
    return "~\(path.dropFirst(homePath.count))"
  }

  func pathSetupCommand(for destination: URL) -> String {
    let directory = destination.deletingLastPathComponent()
    let displayDirectory = displayPath(directory)
    let shellDirectory = displayDirectory.hasPrefix("~/")
      ? "$HOME/\(displayDirectory.dropFirst(2))"
      : displayDirectory
    return "export PATH=\"\(shellDirectory):$PATH\""
  }

  func canRemoveLink(at destination: URL) -> Bool {
    fileManager.isWritableFile(
      atPath: destination.deletingLastPathComponent().path
    )
  }

  private func pointsToBundledExecutable(_ destination: URL) -> Bool {
    guard let target = symbolicLinkTarget(at: destination) else {
      return false
    }
    return Self.pathsMatch(target.resolvingSymlinksInPath(), sourceURL.resolvingSymlinksInPath())
  }

  private func symbolicLinkTarget(at destination: URL) -> URL? {
    guard let targetPath = try? fileManager.destinationOfSymbolicLink(atPath: destination.path) else {
      return nil
    }
    if targetPath.hasPrefix("/") {
      return URL(fileURLWithPath: targetPath).standardizedFileURL
    }
    return destination.deletingLastPathComponent()
      .appendingPathComponent(targetPath)
      .standardizedFileURL
  }

  private func itemExistsIncludingBrokenSymlink(at url: URL) -> Bool {
    symbolicLinkTarget(at: url) != nil || fileManager.fileExists(atPath: url.path)
  }

  private static func pathDirectories(from environment: [String: String]) -> [URL] {
    (environment["PATH"] ?? "")
      .split(separator: ":")
      .map(String.init)
      .filter { $0.hasPrefix("/") }
      .map { URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL }
  }

  private static func canInstall(
    in directory: URL,
    localBin: URL,
    fileManager: FileManager
  ) -> Bool {
    if pathsMatch(directory, localBin) {
      return true
    }
    return fileManager.fileExists(atPath: directory.path)
      && fileManager.isWritableFile(atPath: directory.path)
  }

  private static func pathsMatch(_ lhs: URL, _ rhs: URL) -> Bool {
    lhs.standardizedFileURL.path == rhs.standardizedFileURL.path
  }
}
