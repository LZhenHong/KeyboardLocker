import AppKit
import SwiftUI

/// Owns the menu-bar popover and its lifetime.
///
/// The app stays an AppKit accessory process: converting the entry point to a SwiftUI `App` to gain
/// a `MenuBarExtra` would put the activation policy, services provider, and URL handling — all
/// established paths — at risk for no user-visible benefit. An `NSPopover` hosting a SwiftUI view
/// gives the same UI without touching startup.
@MainActor
final class PopoverPresenter {
  private let popover = NSPopover()

  init(rootView: PopoverRootView) {
    popover.behavior = .transient
    popover.animates = true
    popover.contentViewController = NSHostingController(rootView: rootView)
  }

  var isShown: Bool {
    popover.isShown
  }

  /// Shows the popover anchored to the status item button, or closes it if already open.
  func toggle(relativeTo button: NSStatusBarButton) {
    if popover.isShown {
      popover.performClose(nil)
      return
    }
    show(relativeTo: button)
  }

  func show(relativeTo button: NSStatusBarButton) {
    // An accessory app is not active by default, so the popover could not take keyboard focus for
    // the hotkey recorder without this.
    NSApp.activateForUserPresentation()
    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    popover.contentViewController?.view.window?.makeKey()
  }

  /// Closes the popover before a modal alert is presented, so the alert is never covered by it.
  func close() {
    popover.performClose(nil)
  }
}
