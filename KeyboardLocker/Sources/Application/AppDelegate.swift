import AppKit
import Core
import SwiftUI

/// Custom AppDelegate for handling URL schemes and application lifecycle
class AppDelegate: NSObject, NSApplicationDelegate {
  var urlHandler: URLCommandHandler?
  var keyboardLockManager: KeyboardLockManager?

  func configure(_ manager: KeyboardLockManager, _ handler: URLCommandHandler) {
    keyboardLockManager = manager
    urlHandler = handler
  }

  func applicationWillFinishLaunching(_: Notification) {
    IPCManager.shared.startServer()
  }

  func applicationDidFinishLaunching(_: Notification) {
    setupExceptionHandling()
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

  // MARK: - Exception Handling

  /// Setup NSException handler for crash recovery
  private func setupExceptionHandling() {
    NSSetUncaughtExceptionHandler { exception in
      print("Uncaught exception: \(exception)")
      print("Stack trace: \(exception.callStackSymbols)")

      // Attempt to unlock keyboard before crash - safety measure
      DispatchQueue.main.async {
        // Force unlock using Core directly (emergency safety)
        KeyboardLockCore.shared.unlockKeyboard()

        // Give time for cleanup before exit
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
          exit(1) // Graceful exit
        }
      }
    }
  }

  // MARK: - URL Handling

  /// Handle URL schemes through AppDelegate
  /// - Parameters:
  ///   - application: The application instance
  ///   - urls: Array of URLs to handle
  func application(_: NSApplication, open urls: [URL]) {
    urls.forEach(handleIncomingURL(_:))
  }

  /// Process individual URL requests
  /// - Parameter url: The URL to process
  private func handleIncomingURL(_ url: URL) {
    print("📱 Received URL: \(url)")

    guard let urlHandler else {
      print("❌ URLHandler not configured")
      return
    }

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
