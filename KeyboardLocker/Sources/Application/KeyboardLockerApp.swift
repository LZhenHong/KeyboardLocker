import Core
import SwiftUI

/// Main app entry point using modern SwiftUI App protocol with AppDelegate
@main
struct KeyboardLockerApp: App {
  // Application dependencies container
  private let dependencies = AppDependencies()

  // Use AppDelegate for URL handling
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

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
}
