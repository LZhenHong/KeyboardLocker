import AppIntents
import Client
import WidgetKit

@available(macOS 14.0, *)
struct SetKeyboardLockWidgetIntent: AppIntent {
  static let title: LocalizedStringResource = "Set Keyboard Lock"
  static let description = IntentDescription(
    "Sets the global keyboard lock to the requested state from the widget."
  )
  static let isDiscoverable = false
  static let openAppWhenRun = false

  @Parameter(title: "Locked")
  var desiredIsLocked: Bool

  private let action: KeyboardLockerControlAction

  init() {
    action = .widgetLive
  }

  init(
    desiredIsLocked: Bool,
    action: KeyboardLockerControlAction = .widgetLive
  ) {
    self.action = action
    self.desiredIsLocked = desiredIsLocked
  }

  func perform() async throws -> some IntentResult {
    try await action.setLocked(desiredIsLocked)
    return .result()
  }
}

@available(macOS 14.0, *)
private extension KeyboardLockerControlAction {
  static var widgetLive: Self {
    Self(
      lock: {
        try await XPCClient.shared.lock()
      },
      unlock: {
        try await XPCClient.shared.unlock()
      },
      reload: {
        WidgetCenter.shared.reloadTimelines(ofKind: KeyboardLockerWidgetKind.status)
      }
    )
  }
}
