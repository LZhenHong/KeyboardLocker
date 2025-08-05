import Core
import SwiftUI

/// Main app entry point using modern SwiftUI App protocol with AppDelegate
@main
struct KeyboardLockerApp: App {
  // Application dependencies container
  private let dependencies = appDependencies

  // Use AppDelegate for URL handling
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  init() {
    // Initialize IPC server for external communication
    IPCManager.shared.startServer()

    // Setup global exception handling for stability
    setupExceptionHandling()
  }

  var body: some Scene {
    // Modern MenuBarExtra for native menu bar integration
    MenuBarExtra(LocalizationKey.appMenuTitle.localized, systemImage: "lock.shield") {
      ContentView()
        .environmentObject(dependencies.keyboardLockManager)
        .environmentObject(dependencies.permissionManager)
        .onAppear {
          appDelegate.configure(dependencies.keyboardLockManager, dependencies.urlHandler)
        }
    }
    .menuBarExtraStyle(.window)
    .handlesExternalEvents(matching: ["keyboardlocker"])
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
}
