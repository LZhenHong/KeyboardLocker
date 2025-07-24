import SwiftUI

/// Main app entry point using modern SwiftUI App protocol
@main
struct KeyboardLockerApp: App {
  @StateObject private var keyboardLockManager = KeyboardLockManager()
  @StateObject private var permissionManager = PermissionManager()
  @StateObject private var urlHandler = URLCommandHandler()

  init() {
    // Setup global exception handling for stability
    setupExceptionHandling()
  }

  var body: some Scene {
    // Modern MenuBarExtra for native menu bar integration
    MenuBarExtra("Keyboard Locker", systemImage: "lock.shield") {
      ContentView()
        .environmentObject(keyboardLockManager)
        .environmentObject(permissionManager)
        .environmentObject(urlHandler)
        .onAppear {
          // Set up URL handler with keyboard lock manager reference
          urlHandler.setKeyboardLockManager(keyboardLockManager)
          setupApplicationLifecycleHandlers()
        }
        .onOpenURL { url in
          handleIncomingURL(url)
        }
    }
    .menuBarExtraStyle(.window)
  }

  // MARK: - URL Handling

  /// Handle incoming URL requests
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

  // MARK: - Exception Handling

  /// Setup NSException handler for crash recovery
  private func setupExceptionHandling() {
    NSSetUncaughtExceptionHandler { exception in
      print("Uncaught exception: \(exception)")
      print("Stack trace: \(exception.callStackSymbols)")

      // Attempt to unlock keyboard before crash - safety measure
      DispatchQueue.main.async {
        // Force unlock by creating a temporary manager
        let tempManager = KeyboardLockManager()
        tempManager.unlockKeyboard()

        // Give time for cleanup before exit
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
          exit(1) // Graceful exit
        }
      }
    }
  }

  private func setupApplicationLifecycleHandlers() {
    // Handle application termination
    NotificationCenter.default.addObserver(
      forName: NSApplication.willTerminateNotification,
      object: nil,
      queue: .main
    ) { _ in
      print("Application will terminate - cleaning up")
      // Ensure keyboard is unlocked before termination
      self.keyboardLockManager.unlockKeyboard()
    }

    // Handle application becoming inactive (e.g., logout, restart)
    NotificationCenter.default.addObserver(
      forName: NSApplication.willResignActiveNotification,
      object: nil,
      queue: .main
    ) { _ in
      print("Application will resign active - ensuring keyboard is unlocked")
      self.keyboardLockManager.unlockKeyboard()
    }
  }
}
