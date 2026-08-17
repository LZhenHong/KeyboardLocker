import Foundation

/// AppKit-backed actions the popover triggers but does not implement.
///
/// These either need a modal `NSAlert` confirmation (agent update/restart, quit while locked, CLI
/// management) or jump to System Settings — both of which belong in the AppKit layer, not in the
/// SwiftUI view. The view stays declarative: it decides *when* to offer an action; the controller
/// decides *how* it is presented. Keeping them here also keeps `MainView` free of `NSAlert` so its
/// state-to-action mapping remains the only thing it expresses.
@MainActor
struct PopoverActions {
  /// Agent update/restart route through the coordinator, but only after a warning alert the
  /// controller presents — a running lock may be released.
  var confirmUpdateAgent: () -> Void
  var confirmRestartAgent: () -> Void
  /// The first-run safety check is offered inline, but still gated by a confirmation alert.
  var confirmSafetyCheck: () -> Void
  var copyDiagnostics: () -> Void
  var manageCommandLineTool: () -> Void
  var openLoginItemsSettings: () -> Void
  var openAccessibilitySettings: () -> Void
  /// Quit is destructive while locked (removes the only menu-bar indicator), so the controller
  /// confirms before terminating.
  var quit: () -> Void

  #if DEBUG
  /// A no-op set for previews.
  static let preview = PopoverActions(
    confirmUpdateAgent: {},
    confirmRestartAgent: {},
    confirmSafetyCheck: {},
    copyDiagnostics: {},
    manageCommandLineTool: {},
    openLoginItemsSettings: {},
    openAccessibilitySettings: {},
    quit: {}
  )
  #endif
}
