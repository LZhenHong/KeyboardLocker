import WidgetKit

public enum KeyboardLockerSurfaceKind {
  public static let keyboardLockControl = "io.lzhlovesjyq.keyboardlocker.control"
  public static let statusWidget = "io.lzhlovesjyq.keyboardlocker.status"
}

/// Requests fresh system-owned presentation without becoming another lock-state authority.
/// Reload requests are deliberately nonthrowing: a confirmed Agent mutation remains successful
/// even when WidgetKit defers or coalesces the corresponding presentation refresh.
public struct LockStateSurfaceInvalidator: Sendable {
  public typealias Reload = @Sendable () -> Void

  private let reloadWidget: Reload
  private let reloadControl: Reload

  public init(
    reloadWidget: @escaping Reload,
    reloadControl: @escaping Reload
  ) {
    self.reloadWidget = reloadWidget
    self.reloadControl = reloadControl
  }

  public func invalidate() {
    reloadWidget()
    reloadControl()
  }

  public static let live = Self(
    reloadWidget: {
      WidgetCenter.shared.reloadTimelines(ofKind: KeyboardLockerSurfaceKind.statusWidget)
    },
    reloadControl: {
      if #available(macOS 26.0, *) {
        ControlCenter.shared.reloadControls(
          ofKind: KeyboardLockerSurfaceKind.keyboardLockControl
        )
      }
    }
  )
}
