import AppKit
import ServiceManagement

/// Thin menu-bar presentation for `AppCoordinator` snapshots and actions.
/// It never reads or mutates lock/settings state outside the coordinator's Client boundary.
@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
  private let commandLineToolManager: CommandLineToolLinkManager
  private let coordinator: AppCoordinator
  private let menu = NSMenu()
  private let statusItem: NSStatusItem
  private var currentSnapshot: AppCoordinator.Snapshot
  private var detailMessage: String?

  convenience init(coordinator: AppCoordinator) {
    self.init(
      coordinator: coordinator,
      commandLineToolManager: CommandLineToolLinkManager()
    )
  }

  init(
    coordinator: AppCoordinator,
    commandLineToolManager: CommandLineToolLinkManager
  ) {
    self.coordinator = coordinator
    self.commandLineToolManager = commandLineToolManager
    currentSnapshot = coordinator.snapshot
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    super.init()

    menu.delegate = self
    statusItem.menu = menu
    coordinator.onSnapshotChange = { [weak self] snapshot in
      self?.render(snapshot)
    }
  }

  func menuWillOpen(_: NSMenu) {
    // A long-lived wrapper must recalibrate when it becomes visible because cross-process
    // notification delivery is only a refresh hint, never the authoritative state.
    coordinator.reconcile()
  }

  private func render(_ snapshot: AppCoordinator.Snapshot) {
    currentSnapshot = snapshot
    detailMessage = makeDetailMessage(for: snapshot)

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

    rebuildMenu(statusTitle: appearance.title)
  }

  private func rebuildMenu(statusTitle: String) {
    menu.removeAllItems()

    let status = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
    status.isEnabled = false
    menu.addItem(status)
    menu.addItem(.separator())

    if currentSnapshot.activity == nil {
      addStateActions(for: currentSnapshot.state)
    }

    if detailMessage != nil {
      addAction(title: "Show Details…", action: #selector(showDetails))
    }

    menu.addItem(.separator())
    addAction(
      title: "Refresh Status",
      action: #selector(refresh),
      isEnabled: currentSnapshot.activity == nil
    )
    menu.addItem(.separator())
    addAction(title: "Command Line Tool…", action: #selector(manageCommandLineTool))
    menu.addItem(.separator())
    addAction(title: "Quit KeyboardLocker", action: #selector(quit))
  }

  private func addStateActions(for state: AppCoordinator.State) {
    switch state {
    case .agentReplacementInProgress, .checking:
      break

    case .agentApprovalRequired:
      addAction(
        title: "Open Login Items Settings…",
        action: #selector(openLoginItemsSettings)
      )

    case let .agentUpdateRequired(isLocked, _):
      if isLocked == true {
        addAction(title: "Unlock Keyboard", action: #selector(toggleLock))
      }
      addAction(title: "Update Background Agent…", action: #selector(updateAgent))

    case let .accessibilityRequired(isLocked):
      if isLocked {
        addAction(title: "Unlock Keyboard", action: #selector(toggleLock))
      }
      addAction(
        title: "Grant Accessibility Access…",
        action: #selector(requestAccessibilityPermission)
      )

    case let .ready(isLocked):
      addAction(
        title: isLocked ? "Unlock Keyboard" : "Lock Keyboard",
        action: #selector(toggleLock)
      )

    case let .unavailable(_, canRestartAgent):
      if canRestartAgent {
        addAction(title: "Restart Background Agent…", action: #selector(restartAgent))
      }
    }
  }

  private func addAction(
    title: String,
    action: Selector,
    isEnabled: Bool = true
  ) {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
    item.target = self
    item.isEnabled = isEnabled
    menu.addItem(item)
  }

  private func makeAppearance(
    for snapshot: AppCoordinator.Snapshot
  ) -> (title: String, symbolName: String, accessibilityDescription: String) {
    if let activity = snapshot.activity {
      let title = switch activity {
      case .locking:
        "KeyboardLocker — Locking…"
      case .requestingAccessibility:
        "KeyboardLocker — Requesting Access…"
      case .restartingAgent:
        "KeyboardLocker — Restarting Agent…"
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
        "KeyboardLocker — Updating Agent",
        "arrow.triangle.2.circlepath",
        "Background agent update in progress"
      )

    case let .agentUpdateRequired(isLocked, _):
      return (
        isLocked == true
          ? "KeyboardLocker — Locked (Update Required)"
          : "KeyboardLocker — Agent Update Required",
        "exclamationmark.triangle.fill",
        "Background agent update required"
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

  private func makeDetailMessage(for snapshot: AppCoordinator.Snapshot) -> String? {
    var messages: [String] = []

    switch snapshot.state {
    case .checking, .ready:
      break

    case .agentApprovalRequired:
      messages.append(
        "Enable KeyboardLocker in System Settings → General → Login Items, then refresh status."
      )

    case let .agentReplacementInProgress(message),
         let .agentUpdateRequired(_, message),
         let .unavailable(message, _):
      messages.append(message)

    case .accessibilityRequired:
      messages.append(
        "The background Agent needs Accessibility access before it can filter keyboard events."
      )
    }

    if let lastError = snapshot.lastError {
      messages.append(lastError)
    }

    return messages.isEmpty ? nil : messages.joined(separator: "\n\n")
  }

  @objc
  private func toggleLock() {
    coordinator.toggle()
  }

  @objc
  private func requestAccessibilityPermission() {
    coordinator.requestAccessibilityPermission()
  }

  @objc
  private func openLoginItemsSettings() {
    SMAppService.openSystemSettingsLoginItems()
  }

  @objc
  private func updateAgent() {
    guard case let .agentUpdateRequired(isLocked, message) = currentSnapshot.state else {
      return
    }

    let confirmation = NSAlert()
    confirmation.alertStyle = .warning
    confirmation.messageText = "Update the KeyboardLocker Agent?"
    confirmation.informativeText = if isLocked == true {
      "The keyboard will be unlocked before the Agent is replaced.\n\n\(message)"
    } else {
      message
    }
    confirmation.addButton(withTitle: "Update Agent")
    confirmation.addButton(withTitle: "Cancel")

    NSApp.activate(ignoringOtherApps: true)
    if confirmation.runModal() == .alertFirstButtonReturn {
      coordinator.updateAgent()
    }
  }

  @objc
  private func restartAgent() {
    let confirmation = NSAlert()
    confirmation.alertStyle = .warning
    confirmation.messageText = "Restart the KeyboardLocker Agent?"
    confirmation.informativeText = "Restarting an unresponsive Agent may release an active keyboard lock."
    confirmation.addButton(withTitle: "Restart Agent")
    confirmation.addButton(withTitle: "Cancel")

    NSApp.activate(ignoringOtherApps: true)
    if confirmation.runModal() == .alertFirstButtonReturn {
      coordinator.restartAgent()
    }
  }

  @objc
  private func showDetails() {
    guard let detailMessage else {
      return
    }

    let alert = NSAlert()
    alert.messageText = "KeyboardLocker"
    alert.informativeText = detailMessage
    alert.addButton(withTitle: "OK")
    NSApp.activate(ignoringOtherApps: true)
    alert.runModal()
  }

  @objc
  private func refresh() {
    coordinator.reconcile()
  }

  @objc
  private func manageCommandLineTool() {
    NSApp.activate(ignoringOtherApps: true)

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

  @objc
  private func quit() {
    NSApp.terminate(nil)
  }
}
