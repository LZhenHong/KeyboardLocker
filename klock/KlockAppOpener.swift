import Client
import Foundation

/// Launches the containing KeyboardLocker app so it can register the background Agent with
/// `SMAppService`. Only the App bundle can perform that registration: the launchd plist must
/// live in the main bundle, and `klock`'s main bundle is not KeyboardLocker.app.
enum KlockAppOpener {
  enum OpenerError: LocalizedError {
    case appNotFound
    case launchFailed(String)

    var errorDescription: String? {
      switch self {
      case .appNotFound:
        "KeyboardLocker.app could not be located from this klock executable or by Launch Services."
      case let .launchFailed(details):
        "KeyboardLocker could not be launched. \(details)"
      }
    }

    var recoverySuggestion: String? {
      "Open KeyboardLocker manually once to register its background agent, then retry."
    }
  }

  /// klock ships at `Contents/MacOS/klock` inside the signed App bundle and PATH entries are
  /// symlinks to it, so the resolved executable path identifies the exact App copy to launch.
  /// That matters when a dev build and an installed copy share the same bundle identifier.
  static func openContainingApp() throws {
    if let appURL = containingAppURL() {
      try runOpen(arguments: [appURL.path])
      return
    }
    try runOpen(arguments: ["-b", SharedConstants.appBundleIdentifier])
  }

  private static func containingAppURL() -> URL? {
    var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
    var size = UInt32(buffer.count)
    guard _NSGetExecutablePath(&buffer, &size) == 0 else {
      return nil
    }

    var url = URL(fileURLWithPath: String(cString: buffer))
      .standardizedFileURL
      .resolvingSymlinksInPath()
    while url.pathExtension != "app", url.pathComponents.count > 1 {
      url.deleteLastPathComponent()
    }
    return url.pathExtension == "app" ? url : nil
  }

  private static func runOpen(arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = arguments
    do {
      try process.run()
    } catch {
      throw OpenerError.launchFailed(error.localizedDescription)
    }
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw OpenerError.launchFailed(
        "`open \(arguments.joined(separator: " "))` exited with status \(process.terminationStatus)."
      )
    }
  }
}
