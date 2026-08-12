import AppKit

extension NSApplication {
  /// Requests activation before presenting an alert or other user-facing UI.
  ///
  /// `activate(ignoringOtherApps:)` is marked "will be deprecated in a future release" in the
  /// SDK; `activate()` is its designated replacement but requires macOS 14, so the legacy call
  /// remains on the macOS 13 path.
  func activateForUserPresentation() {
    if #available(macOS 14.0, *) {
      activate()
    } else {
      activate(ignoringOtherApps: true)
    }
  }
}
