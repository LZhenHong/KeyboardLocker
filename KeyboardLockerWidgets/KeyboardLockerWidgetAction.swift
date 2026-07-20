import AppIntents

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
    action = .live
  }

  init(
    desiredIsLocked: Bool,
    action: KeyboardLockerControlAction = .live
  ) {
    self.action = action
    self.desiredIsLocked = desiredIsLocked
  }

  func perform() async throws -> some IntentResult {
    try await action.setLocked(desiredIsLocked)
    return .result()
  }
}
