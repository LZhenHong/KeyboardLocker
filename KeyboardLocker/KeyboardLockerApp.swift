import Core
import SwiftUI

/// Main app entry point using modern SwiftUI App protocol with AppDelegate
@main
struct KeyboardLockerApp: App {
  // Use dependency factory to create managers with proper dependency injection
  @StateObject private var keyboardLockManager: KeyboardLockManager
  @StateObject private var permissionManager = DependencyFactory.shared.makePermissionManager()

  // Use AppDelegate for URL handling
  @NSApplicationDelegateAdaptor(KeyboardLockerAppDelegate.self) var appDelegate

  init() {
    // Create keyboard lock manager safely without force casting
    let manager = DependencyFactory.shared.makeKeyboardLockManager()
    if let concreteManager = manager as? KeyboardLockManager {
      _keyboardLockManager = StateObject(wrappedValue: concreteManager)
    } else {
      // Fallback: create a new instance directly
      _keyboardLockManager = StateObject(wrappedValue: KeyboardLockManager())
    }

    // Setup global exception handling for stability
    setupExceptionHandling()

    // Initialize IPC server for external communication
    IPCManager.shared.startServer()
  }

  var body: some Scene {
    // Modern MenuBarExtra for native menu bar integration
    MenuBarExtra("Keyboard Locker", systemImage: "lock.shield") {
      ContentView()
        .environmentObject(keyboardLockManager)
        .environmentObject(permissionManager)
        .onAppear {
          // Set up URL handler with keyboard lock manager reference
          URLCommandHandler.shared.setKeyboardLockManager(keyboardLockManager)
          // Inject dependencies into AppDelegate
          appDelegate.keyboardLockManager = keyboardLockManager
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
}
