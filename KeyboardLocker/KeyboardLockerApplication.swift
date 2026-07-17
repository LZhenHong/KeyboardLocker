import AppKit

@main
enum KeyboardLockerApplication {
  @MainActor
  static func main() {
    let application = NSApplication.shared
    let delegate = KeyboardLockerApplicationDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.accessory)

    // `NSApplication.delegate` is weak. Keep the process-wide owner alive while the event loop
    // runs so the status item and coordinator remain reachable.
    withExtendedLifetime(delegate) {
      application.run()
    }
  }
}

@MainActor
private final class KeyboardLockerApplicationDelegate: NSObject, NSApplicationDelegate {
  private var statusMenuController: StatusMenuController?

  func applicationDidFinishLaunching(_: Notification) {
    statusMenuController = StatusMenuController(coordinator: AppCoordinator())
  }
}
