import AppKit
import Core
import SwiftUI

/// Custom AppDelegate for handling URL schemes and application lifecycle
class KeyboardLockerAppDelegate: NSObject, NSApplicationDelegate {
  var urlHandler: URLCommandHandler = .shared
  var keyboardLockManager: KeyboardLockManaging?

  func applicationDidFinishLaunching(_: Notification) {
    print("Application did finish launching")
  }

  func applicationWillTerminate(_: Notification) {
    print("Application will terminate - cleaning up")
    // Stop IPC server
    IPCManager.shared.stopServer()
    // Ensure keyboard is unlocked before termination
    keyboardLockManager?.unlockKeyboard()
  }

  func applicationWillResignActive(_: Notification) {
    print("Application will resign active - ensuring keyboard is unlocked")
    keyboardLockManager?.unlockKeyboard()
  }

  // MARK: - URL Handling

  /// Handle URL schemes through AppDelegate
  /// - Parameters:
  ///   - application: The application instance
  ///   - urls: Array of URLs to handle
  func application(_: NSApplication, open urls: [URL]) {
    for url in urls {
      handleIncomingURL(url)
    }
  }

  /// Process individual URL requests
  /// - Parameter url: The URL to process
  private func handleIncomingURL(_ url: URL) {
    print("📱 Received URL: \(url)")

    let response = urlHandler.handleURL(url)
    urlHandler.showUserFeedback(for: response)

    // Log the result
    if response.isSuccess {
      print("✅ URL command executed successfully: \(response.message)")
    } else {
      print("❌ URL command failed: \(response.message)")
    }
  }
}
