import Client
import SwiftUI

/// The popover's status page: what the lock is doing now, the primary action, and any recovery
/// the current agent state calls for.
///
/// Every value comes from the coordinator's authoritative snapshot via `store`; the view only maps
/// state to presentation. Actions that need a modal confirmation or a System Settings jump are
/// carried by `PopoverActions`, keeping this view free of `NSAlert`.
struct StatusPage: View {
  @ObservedObject var store: AppUIStore
  let actions: PopoverActions
  let openSettings: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Divider()
      content
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
      Divider()
      toolbar
    }
  }

  // MARK: - Header

  private var header: some View {
    HStack(alignment: .center, spacing: 12) {
      ZStack {
        Circle()
          .fill(statusTint.opacity(0.15))
          .frame(width: 44, height: 44)
        Image(systemName: statusSymbol)
          .font(.system(size: 20, weight: .medium))
          .foregroundStyle(statusTint)
          .symbolRenderingMode(.hierarchical)
      }

      VStack(alignment: .leading, spacing: 2) {
        Text(statusTitle)
          .font(.headline)
        Text(statusSubtitle)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      Spacer(minLength: 0)
    }
    .padding(16)
  }

  // MARK: - Content

  private var content: some View {
    VStack(alignment: .leading, spacing: 14) {
      if store.isLocked {
        lockDetail
      }

      if let hotkey = displayedHotkey {
        InfoRow(label: "Unlock hotkey", systemImage: "keyboard") {
          Text(hotkey.displayString)
            .font(.callout.monospaced())
            .foregroundStyle(.primary)
        }
      }

      if store.snapshot.hasSettingsPendingNextLock {
        FootnoteLabel(
          "Saved settings take effect on the next lock.",
          systemImage: "clock.badge.checkmark"
        )
      }

      if let error = store.snapshot.lastError {
        FootnoteLabel(error, systemImage: "exclamationmark.triangle.fill", tint: .orange)
      }

      actionButtons
    }
  }

  private var lockDetail: some View {
    VStack(alignment: .leading, spacing: 10) {
      if let deadline = store.autoUnlockDeadline {
        InfoRow(label: "Unlocks in", systemImage: "timer") {
          // The authoritative deadline is transported; the countdown is derived locally so no
          // stale counter crosses XPC.
          Text(timerInterval: Date()...deadline, countsDown: true)
            .font(.callout.monospacedDigit())
        }
        Text("The countdown pauses while the Mac is asleep, so the keyboard may stay locked longer than shown.")
          .font(.caption)
          .foregroundStyle(.secondary)
      } else if store.activeSettings?.autoUnlockPolicy == .disabled {
        InfoRow(label: "Unlocks automatically", systemImage: "timer") {
          Text("Never").foregroundStyle(.secondary)
        }
      }

      if let started = store.lockStartDate {
        InfoRow(label: "Locked since", systemImage: "clock") {
          Text(started, style: .time).font(.callout.monospacedDigit())
        }
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(nsColor: .quaternaryLabelColor).opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
  }

  private var actionButtons: some View {
    VStack(spacing: 8) {
      if store.canPerformLockAction {
        Button {
          store.performDisplayedLockAction()
        } label: {
          Label(
            store.isLocked ? "Unlock Keyboard" : "Lock Keyboard",
            systemImage: store.isLocked ? "lock.open.fill" : "lock.fill"
          )
          .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
      }

      ForEach(store.recoveryActions, id: \.self) { action in
        recoveryButton(action)
      }

      if store.canRunSafetyCheck {
        Button {
          actions.confirmSafetyCheck()
        } label: {
          Label("Run 10-Second Safety Check", systemImage: "checkmark.shield")
            .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .buttonStyle(.bordered)
      }
    }
  }

  @ViewBuilder
  private func recoveryButton(_ action: AppUIStore.RecoveryAction) -> some View {
    switch action {
    case .openLoginItems:
      wideButton("Open Login Items Settings…", "arrow.up.forward.app", prominent: true) {
        actions.openLoginItemsSettings()
      }
    case .grantAccessibility:
      wideButton("Grant Accessibility Access…", "hand.raised", prominent: true) {
        store.requestAccessibilityPermission()
      }
    case .openAccessibilitySettings:
      wideButton("Open Accessibility Settings…", "gearshape") {
        actions.openAccessibilitySettings()
      }
    case .updateAgent:
      wideButton("Update KeyboardLocker Agent…", "arrow.triangle.2.circlepath", prominent: true) {
        actions.confirmUpdateAgent()
      }
    case .restartAgent:
      wideButton("Restart KeyboardLocker Agent…", "arrow.clockwise", prominent: true) {
        actions.confirmRestartAgent()
      }
    }
  }

  @ViewBuilder
  private func wideButton(
    _ title: String,
    _ systemImage: String,
    prominent: Bool = false,
    action: @escaping () -> Void
  ) -> some View {
    let label = Button(action: action) {
      Label(title, systemImage: systemImage).frame(maxWidth: .infinity)
    }
    .controlSize(.large)
    .disabled(store.isBusy)

    if prominent {
      label.buttonStyle(.borderedProminent)
    } else {
      label.buttonStyle(.bordered)
    }
  }

  // MARK: - Toolbar

  private var toolbar: some View {
    HStack(spacing: 4) {
      Button(action: openSettings) {
        Label("Settings", systemImage: "gearshape")
      }
      .disabled(store.isBusy)

      Spacer(minLength: 0)

      Menu {
        Button("Copy Diagnostics", action: actions.copyDiagnostics)
        Button("Command Line Tool…", action: actions.manageCommandLineTool)
        Divider()
        Button("Quit KeyboardLocker", action: actions.quit)
      } label: {
        Image(systemName: "ellipsis.circle")
      }
      .menuStyle(.borderlessButton)
      .menuIndicator(.hidden)
      .fixedSize()
    }
    .labelStyle(.titleAndIcon)
    .buttonStyle(.borderless)
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
  }

  // MARK: - Derived presentation

  private var displayedHotkey: KeyboardLockerSettings.Hotkey? {
    store.activeSettings?.unlockHotkey ?? store.editableSettings?.unlockHotkey
  }

  private var statusTint: Color {
    if store.snapshot.activity != nil {
      return .secondary
    }
    switch store.snapshot.state {
    case .ready(isLocked: true), .accessibilityRequired(isLocked: true):
      return .accentColor
    case .ready(isLocked: false):
      return .green
    case .agentApprovalRequired, .unavailable, .accessibilityRequired, .agentUpdateRequired:
      return .orange
    case .agentReplacementInProgress, .checking:
      return .secondary
    }
  }

  private var statusSymbol: String {
    if store.snapshot.activity != nil {
      return "arrow.triangle.2.circlepath"
    }
    switch store.snapshot.state {
    case .ready(isLocked: true):
      return "lock.fill"
    case .ready(isLocked: false):
      return "lock.open.fill"
    case .accessibilityRequired(isLocked: true), .agentUpdateRequired(isLocked: true, _):
      return "lock.fill"
    case .agentApprovalRequired, .unavailable, .accessibilityRequired, .agentUpdateRequired:
      return "exclamationmark.triangle.fill"
    case .agentReplacementInProgress, .checking:
      return "arrow.triangle.2.circlepath"
    }
  }

  private var statusTitle: String {
    if store.snapshot.activity != nil {
      return "Working…"
    }
    switch store.snapshot.state {
    case .ready(isLocked: true),
         .accessibilityRequired(isLocked: true),
         .agentUpdateRequired(isLocked: true, _):
      return "Keyboard Locked"
    case .ready(isLocked: false):
      return "Keyboard Unlocked"
    case .checking:
      return "Checking…"
    case .agentApprovalRequired:
      return "Approval Required"
    case .agentReplacementInProgress:
      return "Updating Agent…"
    case .agentUpdateRequired:
      return "Update Required"
    case .accessibilityRequired:
      return "Accessibility Required"
    case .unavailable:
      return "Agent Unavailable"
    }
  }

  private var statusSubtitle: String {
    if let activity = store.snapshot.activity {
      return Self.activityLabel(activity)
    }
    switch store.snapshot.state {
    case .checking:
      return "Checking the background agent…"
    case .agentApprovalRequired:
      return "Enable KeyboardLocker in System Settings → General → Login Items."
    case let .agentReplacementInProgress(message),
         let .agentUpdateRequired(_, message),
         let .unavailable(message, _):
      return message
    case .accessibilityRequired:
      return "The background agent needs Accessibility access before it can filter keyboard events."
    case .ready:
      return "Mouse and trackpad stay available while locked."
    }
  }

  private static func activityLabel(_ activity: AppCoordinator.Activity) -> String {
    switch activity {
    case .applyingSettings:
      "Saving settings…"
    case .locking:
      "Locking the keyboard…"
    case .requestingAccessibility:
      "Requesting Accessibility access…"
    case .restartingAgent:
      "Restarting the background agent…"
    case .startingSafetyCheck:
      "Starting the safety check…"
    case .unlocking:
      "Unlocking the keyboard…"
    case .updatingAgent:
      "Updating the background agent…"
    }
  }
}

// MARK: - Shared small views

/// A leading label + trailing value row, used for lock detail and hotkey.
private struct InfoRow<Value: View>: View {
  let label: String
  let systemImage: String
  @ViewBuilder let value: () -> Value

  var body: some View {
    HStack(spacing: 8) {
      Label(label, systemImage: systemImage)
        .font(.callout)
        .foregroundStyle(.secondary)
        .labelStyle(.titleAndIcon)
      Spacer(minLength: 12)
      value()
    }
  }
}

private struct FootnoteLabel: View {
  let text: String
  let systemImage: String
  var tint: Color = .secondary

  init(_ text: String, systemImage: String, tint: Color = .secondary) {
    self.text = text
    self.systemImage = systemImage
    self.tint = tint
  }

  var body: some View {
    Label {
      Text(text).fixedSize(horizontal: false, vertical: true)
    } icon: {
      Image(systemName: systemImage).foregroundStyle(tint)
    }
    .font(.caption)
    .foregroundStyle(.secondary)
  }
}
