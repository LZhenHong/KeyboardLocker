import AppKit
import SwiftUI

/// Owns the standalone FAQ window and its lifetime.
///
/// The FAQ outgrew the fixed 320pt popover: long answers and code blocks read better in a regular
/// window with room to resize. The app stays an accessory process, so presentation follows the
/// same rule as the alerts — activate first, then bring the window forward. One window instance
/// is kept and reused, so a user-arranged position and size survive close/reopen.
@MainActor
final class FAQWindowPresenter {
  private var window: NSWindow?

  func show() {
    let window = window ?? makeWindow()
    self.window = window
    NSApp.activateForUserPresentation()
    window.makeKeyAndOrderFront(nil)
  }

  private func makeWindow() -> NSWindow {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 680, height: 900),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = "KeyboardLocker FAQ"
    window.minSize = NSSize(width: 420, height: 320)
    window.contentViewController = NSHostingController(rootView: FAQView())
    // Reused across opens; closing hides rather than releases.
    window.isReleasedWhenClosed = false
    window.center()
    return window
  }
}
