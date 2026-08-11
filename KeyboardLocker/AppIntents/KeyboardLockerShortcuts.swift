import AppIntents

/// Promoted App Shortcuts for Spotlight, Quick Keys, and Siri. App Shortcuts only run on
/// macOS 26 and later; earlier versions keep exposing the same intents through the Shortcuts
/// action library without invocation phrases.
@available(macOS 26.0, *)
struct KeyboardLockerShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: LockKeyboardIntent(),
      phrases: [
        "Lock keyboard in \(.applicationName)",
        "Lock my keyboard with \(.applicationName)",
      ],
      shortTitle: "Lock Keyboard",
      systemImageName: "lock"
    )

    AppShortcut(
      intent: UnlockKeyboardIntent(),
      phrases: [
        "Unlock keyboard in \(.applicationName)",
        "Unlock my keyboard with \(.applicationName)",
      ],
      shortTitle: "Unlock Keyboard",
      systemImageName: "lock.open"
    )

    AppShortcut(
      intent: ToggleKeyboardLockIntent(),
      phrases: [
        "Toggle keyboard lock in \(.applicationName)",
        "Toggle my keyboard with \(.applicationName)",
      ],
      shortTitle: "Toggle Keyboard Lock",
      systemImageName: "lock.rotation"
    )
  }
}
