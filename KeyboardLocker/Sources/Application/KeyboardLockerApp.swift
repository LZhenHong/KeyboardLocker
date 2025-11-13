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
    MenuBarExtra {
      ContentView()
        .environmentObject(dependencies.coreConfiguration)
        .environmentObject(dependencies.keyboardLockManager)
        .environmentObject(dependencies.permissionManager)
        .onAppear {
          appDelegate.configure(dependencies.keyboardLockManager, dependencies.urlHandler)
        }
    } label: {
      MenuBarLabelView(keyboardLockManager: dependencies.keyboardLockManager)
    }
    .menuBarExtraStyle(.window)
    .handlesExternalEvents(matching: ["keyboardlocker"])
  }
}

private struct MenuBarLabelView: View {
  @ObservedObject var keyboardLockManager: KeyboardLockManager

  private var statusBarIcon: String {
    keyboardLockManager.isLocked ? "lock.fill" : "lock.open.fill"
  }

  var body: some View {
    Label {
      Text(localized: LocalizationKey.appMenuTitle)
    } icon: {
      Image(systemName: statusBarIcon)
    }
  }
}
