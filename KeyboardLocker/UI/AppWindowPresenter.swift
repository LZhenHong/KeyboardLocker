import AppKit
import SwiftUI

/// Owns the app's two SwiftUI windows and their lifetime.
///
/// The app stays an AppKit accessory process: its activation policy, services provider, and URL
/// handling are established paths, and converting the entry point to a SwiftUI `App` to gain a
/// `Settings` scene would put all three at risk for no user-visible benefit. Hosting controllers
/// give the same windows without touching startup.
@MainActor
final class AppWindowPresenter {
  private let store: AppUIStore
  private let copyDiagnostics: () -> Void
  private let manageCommandLineTool: () -> Void

  private var mainWindowController: NSWindowController?
  private var settingsWindowController: NSWindowController?

  init(
    store: AppUIStore,
    copyDiagnostics: @escaping () -> Void,
    manageCommandLineTool: @escaping () -> Void
  ) {
    self.store = store
    self.copyDiagnostics = copyDiagnostics
    self.manageCommandLineTool = manageCommandLineTool
  }

  func showMainWindow() {
    if let controller = mainWindowController {
      present(controller)
      return
    }

    let view = MainView(
      store: store,
      openSettings: { [weak self] in
        self?.showSettingsWindow()
      },
      copyDiagnostics: copyDiagnostics,
      manageCommandLineTool: manageCommandLineTool
    )
    let controller = makeWindowController(
      title: "KeyboardLocker",
      content: view
    )
    mainWindowController = controller
    present(controller)
  }

  func showSettingsWindow() {
    if let controller = settingsWindowController {
      present(controller)
      return
    }

    let controller = makeWindowController(
      title: "KeyboardLocker Settings",
      content: SettingsView(store: store)
    )
    settingsWindowController = controller
    present(controller)
  }

  private func makeWindowController(
    title: String,
    content: some View
  ) -> NSWindowController {
    let hostingController = NSHostingController(rootView: content)
    let window = NSWindow(contentViewController: hostingController)
    window.title = title
    window.styleMask = [.titled, .closable, .miniaturizable]
    window.isReleasedWhenClosed = false
    window.center()
    window.setFrameAutosaveName("io.lzhlovesjyq.keyboardlocker.\(title)")
    return NSWindowController(window: window)
  }

  /// An accessory app has no Dock icon, so a window would otherwise open behind the frontmost app.
  private func present(_ controller: NSWindowController) {
    NSApp.activateForUserPresentation()
    controller.showWindow(nil)
    controller.window?.makeKeyAndOrderFront(nil)
  }
}
