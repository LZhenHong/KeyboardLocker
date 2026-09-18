import AppKit
import SwiftUI

/// Owns a standalone guide window and its lifetime. One instance per bundled document (FAQ,
/// Usage Guide).
///
/// Long-form prose outgrew the fixed 320pt popover: it reads better in a regular window with room
/// to resize. The app stays an accessory process, so presentation follows the same rule as the
/// alerts — activate first, then bring the window forward. One window instance is kept and
/// reused, so a user-arranged position and size survive close/reopen.
@MainActor
final class GuideWindowPresenter {
  private let windowTitle: String
  private let rootView: GuideView
  private var window: NSWindow?

  init(windowTitle: String, guideTitle: String, resource: String) {
    self.windowTitle = windowTitle
    rootView = GuideView(title: guideTitle, resource: resource)
  }

  func show() {
    let window = window ?? makeWindow()
    self.window = window
    NSApp.activateForUserPresentation()
    window.makeKeyAndOrderFront(nil)
  }

  private func makeWindow() -> NSWindow {
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: Self.defaultContentSize),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = windowTitle
    window.minSize = NSSize(width: 420, height: 320)
    window.contentViewController = NSHostingController(rootView: rootView)
    // Assigning a contentViewController resizes the window to the hosting view's fitting size —
    // for a ScrollView that collapses to minSize — so the intended initial size is applied
    // after the assignment, clamped to what the screen can actually show.
    let visibleHeight = (window.screen ?? NSScreen.main)?.visibleFrame.height ?? Self.defaultContentSize.height
    window.setContentSize(
      NSSize(
        width: Self.defaultContentSize.width,
        height: min(Self.defaultContentSize.height, visibleHeight)
      )
    )
    // Reused across opens; closing hides rather than releases.
    window.isReleasedWhenClosed = false
    window.center()
    return window
  }

  /// The 620pt content column plus vertical padding, tall enough to read several entries at once.
  private static let defaultContentSize = NSSize(width: 680, height: 900)
}
