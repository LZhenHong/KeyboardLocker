import AppIntents
import Client
import SwiftUI
import SystemSurfaces
import WidgetKit

@available(macOS 26.0, *)
struct KeyboardLockerControl: ControlWidget {
  nonisolated static let kind = KeyboardLockerSurfaceKind.keyboardLockControl

  var body: some ControlWidgetConfiguration {
    StaticControlConfiguration(
      kind: Self.kind,
      provider: KeyboardLockerControlValueProvider()
    ) { isLocked in
      ControlWidgetToggle(
        "Keyboard Lock",
        isOn: isLocked,
        action: SetKeyboardLockControlIntent()
      ) { isLocked in
        Label(
          isLocked ? "Locked" : "Unlocked",
          systemImage: isLocked ? "keyboard.fill" : "keyboard"
        )
      }
    }
    .displayName("Keyboard Lock")
    .description("Locks or unlocks the keyboard through the KeyboardLocker agent.")
  }
}

@available(macOS 26.0, *)
private struct KeyboardLockerControlValueProvider: ControlValueProvider {
  /// Gallery preview matches the status widget's locked sample so both system surfaces
  /// advertise the same state.
  let previewValue = true

  private let loader: KeyboardLockerControlValueLoader

  init(loader: KeyboardLockerControlValueLoader = .live) {
    self.loader = loader
  }

  func currentValue() async throws -> Bool {
    try await loader.currentValue()
  }
}

@available(macOS 26.0, *)
struct SetKeyboardLockControlIntent: SetValueIntent {
  static let title: LocalizedStringResource = "Set Keyboard Lock"
  static let description = IntentDescription(
    "Sets the global keyboard lock to the requested state."
  )

  @Parameter(title: "Locked")
  var value: Bool

  init() {}

  func perform() async throws -> some IntentResult {
    try await KeyboardLockerControlAction.live.setLocked(value)
    return .result()
  }
}

@available(macOS 26.0, *)
private extension KeyboardLockerControlValueLoader {
  static var live: Self {
    Self {
      try await XPCClient.shared.status()
    }
  }
}
