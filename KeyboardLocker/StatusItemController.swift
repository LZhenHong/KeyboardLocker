import AppKit
import ServiceManagement

/// Owns the menu-bar status item and the popover it toggles.
///
/// It holds the coordinator's single snapshot observer and fans each update out to the menu-bar
/// icon and to `AppUIStore` (which drives the popover's SwiftUI content). Actions that need a modal
/// `NSAlert` or a System Settings jump live here and are handed to the popover through
/// `PopoverActions`, so the SwiftUI layer stays free of AppKit presentation.
@MainActor
final class StatusItemController: NSObject {
  private let commandLineToolManager: CommandLineToolLinkManager
  private let coordinator: AppCoordinator
  private let diagnosticsCollector: KeyboardLockerDiagnosticsCollector
  private let safetyCheckStore: SafetyCheckExperienceStore
  private let statusItem: NSStatusItem
  private let uiStore: AppUIStore
  private var popoverPresenter: PopoverPresenter!
  private var currentSnapshot: AppCoordinator.Snapshot
  private var hasOfferedSafetyCheckThisLaunch = false
  private var lastHandledSafetyCheckState: AppCoordinator.SafetyCheckState = .idle

  convenience init(coordinator: AppCoordinator) {
    self.init(
      coordinator: coordinator,
      commandLineToolManager: CommandLineToolLinkManager(),
      diagnosticsCollector: .live,
      safetyCheckStore: SafetyCheckExperienceStore()
    )
  }

  init(
    coordinator: AppCoordinator,
    commandLineToolManager: CommandLineToolLinkManager,
    diagnosticsCollector: KeyboardLockerDiagnosticsCollector,
    safetyCheckStore: SafetyCheckExperienceStore
  ) {
    self.coordinator = coordinator
    self.commandLineToolManager = commandLineToolManager
    self.diagnosticsCollector = diagnosticsCollector
    self.safetyCheckStore = safetyCheckStore
    currentSnapshot = coordinator.snapshot
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    let store = AppUIStore(coordinator: coordinator)
    uiStore = store
    super.init()

    // Actions capture `self`, so the popover can only be built once `self` exists.
    popoverPresenter = PopoverPresenter(
      rootView: PopoverRootView(store: store, actions: makeActions())
    )

    if let button = statusItem.button {
      button.action = #selector(statusItemClicked)
      button.target = self
    }

    // This controller owns the coordinator's single observer slot and fans each snapshot out to
    // both the menu-bar icon and the popover's store.
    coordinator.onSnapshotChange = { [weak self] snapshot in
      self?.render(snapshot)
    }
    render(coordinator.snapshot)
  }

  private func makeActions() -> PopoverActions {
    PopoverActions(
      confirmUpdateAgent: { [weak self] in self?.confirmUpdateAgent() },
      confirmRestartAgent: { [weak self] in self?.confirmRestartAgent() },
      confirmSafetyCheck: { [weak self] in self?.confirmSafetyCheck() },
      copyDiagnostics: { [weak self] in self?.copyDiagnostics() },
      manageCommandLineTool: { [weak self] in self?.manageCommandLineTool() },
      openLoginItemsSettings: { [weak self] in self?.openLoginItemsSettings() },
      openAccessibilitySettings: { [weak self] in self?.openAccessibilitySettings() },
      quit: { [weak self] in self?.quit() }
    )
  }

  // MARK: - Status item

  @objc
  private func statusItemClicked() {
    guard let button = statusItem.button else {
      return
    }
    // Recalibrate before showing: a suspended app may have missed a broadcast.
    coordinator.reconcile()
    popoverPresenter.toggle(relativeTo: button)
  }

  private func render(_ snapshot: AppCoordinator.Snapshot) {
    currentSnapshot = snapshot
    uiStore.receive(snapshot)

    let appearance = makeAppearance(for: snapshot)
    if let button = statusItem.button {
      let image = NSImage(
        systemSymbolName: appearance.symbolName,
        accessibilityDescription: appearance.accessibilityDescription
      )
      image?.isTemplate = true
      button.image = image
      button.toolTip = appearance.title
    }

    handleSafetyCheckExperience(snapshot)
  }

  private func makeAppearance(
    for snapshot: AppCoordinator.Snapshot
  ) -> (title: String, symbolName: String, accessibilityDescription: String) {
    if let activity = snapshot.activity {
      let title = switch activity {
      case .applyingSettings:
        "KeyboardLocker — Saving Settings…"
      case .locking:
        "KeyboardLocker — Locking…"
      case .requestingAccessibility:
        "KeyboardLocker — Requesting Access…"
      case .restartingAgent:
        "KeyboardLocker — Restarting Agent…"
      case .startingSafetyCheck:
        "KeyboardLocker — Starting Safety Check…"
      case .unlocking:
        "KeyboardLocker — Unlocking…"
      case .updatingAgent:
        "KeyboardLocker — Updating Agent…"
      }
      return (title, "arrow.triangle.2.circlepath", "Keyboard lock operation in progress")
    }

    switch snapshot.state {
    case let .checking(lastKnownLock):
      let title = lastKnownLock == true
        ? "KeyboardLocker — Checking (Locked)"
        : "KeyboardLocker — Checking…"
      return (title, "arrow.triangle.2.circlepath", "Checking keyboard lock status")

    case .agentApprovalRequired:
      return (
        "KeyboardLocker — Approval Required",
        "exclamationmark.triangle.fill",
        "Background agent approval required"
      )

    case .agentReplacementInProgress:
      return (
        "KeyboardLocker — Agent Update in Progress",
        "arrow.triangle.2.circlepath",
        "Background agent update in progress"
      )

    case let .agentUpdateRequired(isLocked, _):
      // Locked variants keep the lock icon: the warning triangle is reserved for states
      // where attention is needed and the keyboard is not known to be locked.
      return (
        isLocked == true
          ? "KeyboardLocker — Locked (Update Required)"
          : "KeyboardLocker — Agent Update Required",
        isLocked == true ? "lock.fill" : "exclamationmark.triangle.fill",
        isLocked == true ? "Keyboard locked, agent update required" : "Background agent update required"
      )

    case let .accessibilityRequired(isLocked):
      return (
        isLocked
          ? "KeyboardLocker — Locked (Access Required)"
          : "KeyboardLocker — Accessibility Required",
        isLocked ? "lock.fill" : "exclamationmark.triangle.fill",
        isLocked ? "Keyboard locked" : "Accessibility access required"
      )

    case let .ready(isLocked):
      return isLocked
        ? ("KeyboardLocker — Locked", "lock.fill", "Keyboard locked")
        : ("KeyboardLocker — Unlocked", "lock.open.fill", "Keyboard unlocked")

    case .unavailable:
      return (
        "KeyboardLocker — Agent Unavailable",
        "exclamationmark.triangle.fill",
        "Background agent unavailable"
      )
    }
  }

  private func handleSafetyCheckExperience(_ snapshot: AppCoordinator.Snapshot) {
    let previousState = lastHandledSafetyCheckState
    lastHandledSafetyCheckState = snapshot.safetyCheckState

    switch snapshot.safetyCheckState {
    case .completed where previousState != .completed:
      safetyCheckStore.markCompleted()
      presentSafetyCheckResult(
        title: "Safety Check Complete",
        message: "Keyboard input is available again. KeyboardLocker is ready to use."
      )

    case let .failed(message) where snapshot.safetyCheckState != previousState:
      presentSafetyCheckResult(
        title: "Safety Check Failed",
        message: message
      )

    case .completed, .failed, .idle, .running:
      break
    }

    guard !safetyCheckStore.hasCompletedSafetyCheck,
          !hasOfferedSafetyCheckThisLaunch,
          snapshot.activity == nil,
          snapshot.safetyCheckState == .idle,
          case .ready(isLocked: false) = snapshot.state
    else {
      return
    }

    hasOfferedSafetyCheckThisLaunch = true
    Task { @MainActor [weak self] in
      self?.confirmSafetyCheck()
    }
  }

  private func presentSafetyCheckResult(title: String, message: String) {
    Task { @MainActor in
      let alert = NSAlert()
      alert.messageText = title
      alert.informativeText = message
      alert.addButton(withTitle: "OK")
      NSApp.activateForUserPresentation()
      alert.runModal()
    }
  }

  // MARK: - Confirmed actions (carried into the popover via PopoverActions)

  fileprivate func confirmSafetyCheck() {
    popoverPresenter.close()
    let alert = NSAlert()
    alert.messageText = "Run a 10-Second Safety Check?"
    alert.informativeText = """
    KeyboardLocker will temporarily block keyboard input and keyboard system controls. The mouse \
    and trackpad remain available, and the Agent will unlock automatically after 10 seconds even \
    if this App exits. You can also unlock earlier with the configured hotkey or the notification's \
    Unlock Now action.
    """
    alert.addButton(withTitle: "Start Safety Check")
    alert.addButton(withTitle: "Not Now")

    NSApp.activateForUserPresentation()
    guard alert.runModal() == .alertFirstButtonReturn else {
      return
    }
    coordinator.startSafetyCheck()
  }

  fileprivate func confirmUpdateAgent() {
    guard case let .agentUpdateRequired(isLocked, message) = currentSnapshot.state else {
      return
    }
    popoverPresenter.close()

    let confirmation = NSAlert()
    confirmation.alertStyle = .warning
    confirmation.messageText = "Update the KeyboardLocker Agent?"
    confirmation.informativeText = if isLocked == true {
      "The keyboard will be unlocked before the agent is replaced.\n\n\(message)"
    } else {
      message
    }
    confirmation.addButton(withTitle: "Update Agent")
    confirmation.addButton(withTitle: "Cancel")

    NSApp.activateForUserPresentation()
    if confirmation.runModal() == .alertFirstButtonReturn {
      coordinator.updateAgent()
    }
  }

  fileprivate func confirmRestartAgent() {
    popoverPresenter.close()
    let confirmation = NSAlert()
    confirmation.alertStyle = .warning
    confirmation.messageText = "Restart the KeyboardLocker Agent?"
    confirmation.informativeText = "Restarting an unresponsive agent may release an active keyboard lock."
    confirmation.addButton(withTitle: "Restart Agent")
    confirmation.addButton(withTitle: "Cancel")

    NSApp.activateForUserPresentation()
    if confirmation.runModal() == .alertFirstButtonReturn {
      coordinator.restartAgent()
    }
  }

  fileprivate func copyDiagnostics() {
    popoverPresenter.close()
    let snapshot = currentSnapshot
    Task { @MainActor [weak self] in
      guard let self else {
        return
      }

      let report = await diagnosticsCollector.report(appSnapshot: snapshot)
      let pasteboard = NSPasteboard.general
      pasteboard.clearContents()
      pasteboard.setString(report, forType: .string)

      let alert = NSAlert()
      alert.messageText = "Diagnostics Copied"
      alert.informativeText = "The report contains runtime state and version information, but no keyboard input, user name, host name, or file paths."
      alert.addButton(withTitle: "OK")
      NSApp.activateForUserPresentation()
      alert.runModal()
    }
  }

  fileprivate func openLoginItemsSettings() {
    SMAppService.openSystemSettingsLoginItems()
  }

  fileprivate func openAccessibilitySettings() {
    // Only Login Items has a public System Settings entry point; once the one-shot
    // Accessibility prompt has been dismissed, the privacy-pane deep link is the
    // established path to land the user on the right pane.
    guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
      return
    }
    NSWorkspace.shared.open(url)
  }

  fileprivate func quit() {
    guard snapshotShowsLockedKeyboard else {
      NSApp.terminate(nil)
      return
    }
    popoverPresenter.close()

    // Quitting removes the only in-App lock indicator while the Agent-owned lock stays active.
    // Make sure the user leaves knowing how to get out of the lock.
    let confirmation = NSAlert()
    confirmation.alertStyle = .warning
    confirmation.messageText = "Quit KeyboardLocker while the keyboard is locked?"
    confirmation.informativeText = """
    The lock stays active without the menu bar indicator. You can still unlock with the \
    configured unlock hotkey, the notification's Unlock Now button, or `klock unlock`.
    """
    confirmation.addButton(withTitle: "Quit")
    confirmation.addButton(withTitle: "Cancel")

    NSApp.activateForUserPresentation()
    if confirmation.runModal() == .alertFirstButtonReturn {
      NSApp.terminate(nil)
    }
  }

  private var snapshotShowsLockedKeyboard: Bool {
    switch currentSnapshot.state {
    case let .accessibilityRequired(isLocked),
         let .ready(isLocked):
      isLocked
    case let .checking(lastKnownLock):
      // Same evidence standard as `AppCoordinator.performDisplayedLockAction()`: a
      // last-known-locked reading means the keyboard may still be locked, so quitting must warn.
      lastKnownLock ?? false
    case let .agentUpdateRequired(isLocked, _):
      isLocked ?? false
    case .agentApprovalRequired, .agentReplacementInProgress, .unavailable:
      false
    }
  }

  // MARK: - Command line tool

  fileprivate func manageCommandLineTool() {
    popoverPresenter.close()
    NSApp.activateForUserPresentation()

    switch commandLineToolManager.state {
    case let .installed(destination):
      let canRemove = commandLineToolManager.canRemoveLink(at: destination)
      let alert = NSAlert()
      alert.messageText = "klock Command Is Installed"
      alert.informativeText = if canRemove {
        "Terminal command: \(commandLineToolManager.displayPath(destination)). If Terminal cannot find it, copy the PATH command."
      } else {
        "Terminal command: \(commandLineToolManager.displayPath(destination)). KeyboardLocker does not have permission to remove this link."
      }
      if canRemove {
        alert.addButton(withTitle: "Uninstall")
      }
      alert.addButton(withTitle: "Copy PATH Command")
      alert.addButton(withTitle: "Close")

      switch alert.runModal() {
      case .alertFirstButtonReturn where canRemove:
        do {
          _ = try commandLineToolManager.uninstall()
          showCommandLineToolResult(
            title: "klock Command Removed",
            message: "The command link was removed. The bundled executable was not changed."
          )
        } catch {
          showCommandLineToolError(error)
        }

      case .alertFirstButtonReturn,
           .alertSecondButtonReturn where canRemove:
        copyPathCommand(for: destination)

      default:
        return
      }

    case let .notInstalled(destination, requiresPathSetup):
      let path = commandLineToolManager.displayPath(destination)
      let alert = NSAlert()
      alert.messageText = "Install the klock Command?"
      alert.informativeText = if requiresPathSetup {
        """
        KeyboardLocker will create a symbolic link at \(path). It will not modify shell profiles. \
        You may need to add its directory to PATH before Terminal can find klock.
        """
      } else {
        "KeyboardLocker will create a symbolic link at \(path). The signed executable stays inside the App."
      }
      alert.addButton(withTitle: "Install")
      alert.addButton(withTitle: "Cancel")
      guard alert.runModal() == .alertFirstButtonReturn else {
        return
      }
      do {
        _ = try commandLineToolManager.install()
        showCommandLineToolInstalled(
          at: destination,
          requiresPathSetup: requiresPathSetup
        )
      } catch {
        showCommandLineToolError(error)
      }

    case let .conflict(destination):
      showCommandLineToolResult(
        title: "Cannot Install klock",
        message: "A different item already exists at \(commandLineToolManager.displayPath(destination)). Nothing was changed."
      )

    case let .sourceUnavailable(source):
      showCommandLineToolResult(
        title: "klock Is Unavailable",
        message: "The App bundle is incomplete. The expected executable was not found at \(commandLineToolManager.displayPath(source))."
      )
    }
  }

  private func showCommandLineToolInstalled(
    at destination: URL,
    requiresPathSetup: Bool
  ) {
    let alert = NSAlert()
    alert.messageText = "klock Command Installed"
    alert.informativeText = if requiresPathSetup {
      """
      Installed at \(commandLineToolManager.displayPath(destination)). Add its directory to PATH, \
      then open a new Terminal and run klock --help.
      """
    } else {
      "Installed at \(commandLineToolManager.displayPath(destination)). Open a new Terminal and run klock --help."
    }
    if requiresPathSetup {
      alert.addButton(withTitle: "Copy PATH Command")
      alert.addButton(withTitle: "Close")
      if alert.runModal() == .alertFirstButtonReturn {
        copyPathCommand(for: destination)
      }
    } else {
      alert.addButton(withTitle: "OK")
      alert.runModal()
    }
  }

  private func copyPathCommand(for destination: URL) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(
      commandLineToolManager.pathSetupCommand(for: destination),
      forType: .string
    )
  }

  private func showCommandLineToolError(_ error: Error) {
    showCommandLineToolResult(
      title: "Command Line Tool Error",
      message: error.localizedDescription
    )
  }

  private func showCommandLineToolResult(title: String, message: String) {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.addButton(withTitle: "OK")
    alert.runModal()
  }
}
