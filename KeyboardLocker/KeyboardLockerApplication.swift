import AppKit
import Client
import Foundation

@main
enum KeyboardLockerApplication {
  @MainActor
  static func main() {
    #if DEBUG
    if runDevelopmentCommandIfRequested() {
      return
    }
    #endif

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

  #if DEBUG
  @MainActor
  private static func runDevelopmentCommandIfRequested() -> Bool {
    guard CommandLine.arguments.dropFirst().elementsEqual(["--reset-agent-registration"]) else {
      return false
    }

    Task { @MainActor in
      await exit(resetAgentRegistration())
    }
    RunLoop.main.run()
    return true
  }

  @MainActor
  private static func resetAgentRegistration() async -> Int32 {
    if AgentRegistrar.isAgentEnabled {
      do {
        try await XPCClient.shared.unlock()
      } catch {
        writeStandardError(
          """
          Warning: Could not unlock the agent before reset: \(error.localizedDescription) \
          Continuing with the explicit reset; stopping the agent releases its event tap.
          """
        )
      }
    }

    XPCClient.shared.resetConnection()

    do {
      try await AgentRegistrar.unregister()
      print("KeyboardLocker agent registration reset.")
      return EXIT_SUCCESS
    } catch {
      writeStandardError("Error: Could not reset agent registration: \(error.localizedDescription)")
      return EXIT_FAILURE
    }
  }

  private static func writeStandardError(_ message: String) {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
  }
  #endif
}

@MainActor
private final class KeyboardLockerApplicationDelegate: NSObject, NSApplicationDelegate {
  private let automationController: ExternalAutomationController
  private let servicesProvider: KeyboardLockerServicesProvider
  private let lockNotificationController: LockNotificationController
  private var statusMenuController: StatusMenuController?

  override init() {
    let automationController = ExternalAutomationController()
    self.automationController = automationController
    servicesProvider = KeyboardLockerServicesProvider { action in
      Task { @MainActor in
        automationController.submit(action, source: .service)
      }
    }
    // Constructed before launch completes so its UNUserNotificationCenter delegate catches an
    // Unlock Now response that relaunched the App.
    let client = LiveAgentClient()
    lockNotificationController = LockNotificationController(
      notifications: LiveLockNotificationService(),
      lockStateObserver: LiveAgentLockStateObserver(),
      snapshotQuery: { try await XPCClient.shared.lockStatusSnapshot() },
      unlock: { try await client.unlock() }
    )
    super.init()
  }

  func applicationDidFinishLaunching(_: Notification) {
    NSApp.servicesProvider = servicesProvider
    statusMenuController = StatusMenuController(coordinator: AppCoordinator())
    lockNotificationController.start()
  }

  func application(_: NSApplication, open urls: [URL]) {
    automationController.submit(
      KeyboardLockerURLRoute.requests(for: urls),
      source: .urlScheme
    )
  }
}
