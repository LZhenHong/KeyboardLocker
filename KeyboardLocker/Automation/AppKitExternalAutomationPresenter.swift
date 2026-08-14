import AppKit

@MainActor
struct AppKitExternalAutomationPresenter: ExternalAutomationPresenting {
  func presentStatus(isLocked: Bool, source _: ExternalAutomationSource) {
    let state = isLocked ? "Locked" : "Unlocked"
    presentAlert(
      style: .informational,
      message: "Keyboard is \(state)",
      information: "This status was read from the KeyboardLocker Agent."
    )
  }

  func presentFailures(
    _ failures: [ExternalAutomationFailure],
    source: ExternalAutomationSource
  ) {
    let uniqueMessages = failures.reduce(into: [String]()) { messages, failure in
      if !messages.contains(failure.message) {
        messages.append(failure.message)
      }
    }

    presentAlert(
      style: .warning,
      message: "KeyboardLocker \(source.rawValue) Failed",
      information: uniqueMessages.joined(separator: "\n\n")
    )
  }

  private func presentAlert(
    style: NSAlert.Style,
    message: String,
    information: String
  ) {
    let alert = NSAlert()
    alert.alertStyle = style
    alert.messageText = message
    alert.informativeText = information
    alert.addButton(withTitle: "OK")
    NSApp.activateForUserPresentation()
    alert.runModal()
  }
}
