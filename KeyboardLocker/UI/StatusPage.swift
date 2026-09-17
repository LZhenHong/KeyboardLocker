import Client
import SwiftUI

/// The popover's status page: what the lock is doing now, the primary action, and any recovery
/// the current agent state calls for.
///
/// Layout is a row grid: a single state row carries the status and the primary Lock/Unlock action,
/// optional detail rows sit below it, and the bottom bar pairs the hotkey hint with the menu.
/// Every value comes from the coordinator's authoritative snapshot via `store`; the view only maps
/// state to presentation. Actions that need a modal confirmation or a System Settings jump are
/// carried by `PopoverActions`, keeping this view free of `NSAlert`.
struct StatusPage: View {
  @ObservedObject var store: AppUIStore
  let actions: PopoverActions
  let openSettings: () -> Void
  let openStats: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      stateRow
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
      if showsDetail {
        Divider()
        detail
          .padding(.horizontal, 16)
          .padding(.vertical, 14)
      }
      Divider()
      toolbar
    }
  }

  // MARK: - State row

  private var stateRow: some View {
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
        statusSubtitle
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      Spacer(minLength: 0)

      if store.canPerformLockAction {
        Button(store.isLocked ? "Unlock" : "Lock") {
          store.performDisplayedLockAction()
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
      }
    }
  }

  // MARK: - Detail

  /// Detail rows only exist when the state has something to say; a healthy unlocked page is just
  /// the state row and the toolbar.
  private var showsDetail: Bool {
    store.isLocked
      || (!store.isLocked && store.lastUnlock != nil)
      || store.snapshot.hasSettingsPendingNextLock
      || store.snapshot.lastError != nil
      || !store.recoveryActions.isEmpty
  }

  private var detail: some View {
    VStack(alignment: .leading, spacing: 14) {
      if store.isLocked, let started = store.lockStartDate {
        InfoRow(label: "Locked since", systemImage: "clock") {
          Text(started, style: .time).font(.callout.monospacedDigit())
        }
      }

      // Answers "why is my keyboard unlocked right now" — e.g. a timer expiry the user did
      // not watch happen. Only meaningful while unlocked; a running lock reports its own row.
      if !store.isLocked, let lastUnlock = store.lastUnlock {
        InfoRow(label: "Last unlocked", systemImage: "clock.arrow.circlepath") {
          Text(lastUnlock.date, style: .time).font(.callout.monospacedDigit())
            + Text(" · \(lastUnlock.reason.displayName)")
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

      ForEach(store.recoveryActions, id: \.self) { action in
        recoveryButton(action)
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
      if let hotkey = displayedHotkey {
        Text("Unlock hotkey \(hotkey.displayString)")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer(minLength: 0)

      Button(action: openStats) {
        Image(systemName: "chart.bar")
      }
      .help("Lock statistics")

      Menu {
        // One-off quick locks: the saved auto-unlock policy is never changed by these, and a
        // running lock cannot adopt an override, so they only exist while unlocked and ready.
        if store.canPerformTimedLock {
          ForEach(Self.timedLockPresets, id: \.self) { minutes in
            Button("Lock for \(minutes) Minutes") {
              store.performTimedLock(seconds: TimeInterval(minutes * 60))
            }
          }
          Divider()
        }
        Button("Settings…", action: openSettings)
          .disabled(store.isBusy)
        Button("Copy Diagnostics", action: actions.copyDiagnostics)
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

  /// Quick-lock presets offered by the toolbar menu, in minutes.
  private static let timedLockPresets = [5, 10, 30]

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

  @ViewBuilder
  private var statusSubtitle: some View {
    if let activity = store.snapshot.activity {
      Text(Self.activityLabel(activity))
    } else {
      switch store.snapshot.state {
      case .ready(isLocked: true):
        if let deadline = store.autoUnlockDeadline {
          // The authoritative deadline is transported; the countdown is derived locally so no
          // stale counter crosses XPC.
          Text("Unlocks in ")
            + Text(timerInterval: Date()...deadline, countsDown: true).monospacedDigit()
        } else {
          Text("No auto-unlock.")
        }
      case .ready(isLocked: false):
        Text("Mouse and trackpad keep working.")
      case .checking:
        Text("Checking agent…")
      case .agentApprovalRequired:
        Text("Enable KeyboardLocker in System Settings → General → Login Items.")
      case let .agentReplacementInProgress(message),
           let .agentUpdateRequired(_, message),
           let .unavailable(message, _):
        Text(message)
      case .accessibilityRequired:
        Text("The agent needs Accessibility access to filter keyboard events.")
      }
    }
  }

  private static func activityLabel(_ activity: AppCoordinator.Activity) -> String {
    switch activity {
    case .applyingSettings:
      "Saving settings…"
    case .locking:
      "Locking…"
    case .requestingAccessibility:
      "Requesting access…"
    case .restartingAgent:
      "Restarting agent…"
    case .startingSafetyCheck:
      "Starting safety check…"
    case .unlocking:
      "Unlocking…"
    case .updatingAgent:
      "Updating agent…"
    }
  }
}

// MARK: - Shared small views

/// A leading label + trailing value row, used for lock detail.
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
