import Client
import SwiftUI

/// The app's status window: what the lock is doing right now, and the actions that change it.
///
/// Everything shown here comes from the coordinator's authoritative snapshot. The window is a
/// parallel entry point to the status menu, not a replacement — the menu stays the reachable
/// surface while the keyboard is locked and only the mouse works.
struct MainView: View {
  @ObservedObject var store: AppUIStore

  let openSettings: () -> Void
  let copyDiagnostics: () -> Void
  let manageCommandLineTool: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Divider()
      detail
      Divider()
      footer
    }
    .frame(width: 420)
    .fixedSize(horizontal: false, vertical: true)
    .onAppear {
      // A window that was hidden may have missed a broadcast, so recalibrate on becoming visible.
      store.reconcile()
    }
  }

  // MARK: - Header

  private var header: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: store.isLocked ? "lock.fill" : "lock.open.fill")
        .font(.system(size: 28))
        .foregroundStyle(store.isLocked ? Color.accentColor : .secondary)
        .frame(width: 36)

      VStack(alignment: .leading, spacing: 4) {
        Text(store.isLocked ? "Keyboard Locked" : "Keyboard Unlocked")
          .font(.title3.weight(.semibold))

        if let activity = store.snapshot.activity {
          HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            Text(Self.activityLabel(activity)).foregroundStyle(.secondary)
          }
          .font(.callout)
        } else {
          Text(Self.stateSummary(store.snapshot.state))
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      Spacer(minLength: 0)
    }
    .padding(16)
  }

  // MARK: - Detail

  private var detail: some View {
    VStack(alignment: .leading, spacing: 10) {
      if store.isLocked {
        if let deadline = store.autoUnlockDeadline {
          LabeledContent("Unlocks automatically") {
            // A live countdown from the authoritative deadline; the deadline itself is transported,
            // never a counter that would be stale on arrival.
            Text(timerInterval: Date()...deadline, countsDown: true)
              .monospacedDigit()
          }
          Text("The countdown pauses while the Mac is asleep, so the keyboard may stay locked longer than shown.")
            .font(.caption)
            .foregroundStyle(.secondary)
        } else if store.activeSettings?.autoUnlockPolicy == .disabled {
          LabeledContent("Unlocks automatically") {
            Text("Never").foregroundStyle(.secondary)
          }
        }

        if let started = store.lockStartDate {
          LabeledContent("Locked since") {
            Text(started, style: .time).monospacedDigit()
          }
        }
      }

      if let hotkey = store.activeSettings?.unlockHotkey ?? store.editableSettings?.unlockHotkey {
        LabeledContent("Unlock hotkey") {
          Text(hotkey.displayString).monospacedDigit()
        }
      }

      if store.snapshot.hasSettingsPendingNextLock {
        Label(
          "Saved settings take effect on the next lock.",
          systemImage: "clock.badge.checkmark"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      if let error = store.snapshot.lastError {
        Label {
          Text(error).fixedSize(horizontal: false, vertical: true)
        } icon: {
          Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
        .font(.callout)
      }

      primaryActions
    }
    .padding(16)
  }

  private var primaryActions: some View {
    HStack(spacing: 8) {
      if store.canPerformLockAction {
        Button(store.isLocked ? "Unlock Keyboard" : "Lock Keyboard") {
          store.performDisplayedLockAction()
        }
        .keyboardShortcut(.defaultAction)
      }

      if case .accessibilityRequired = store.snapshot.state {
        Button("Grant Accessibility Access…") {
          store.requestAccessibilityPermission()
        }
        .disabled(store.isBusy)
      }

      if case .ready(isLocked: false) = store.snapshot.state,
         store.snapshot.safetyCheckState != .running {
        Button("Run 10-Second Safety Check…") {
          store.startSafetyCheck()
        }
        .disabled(store.isBusy)
      }

      Spacer(minLength: 0)
    }
    .padding(.top, 2)
  }

  // MARK: - Footer

  private var footer: some View {
    HStack(spacing: 8) {
      Button("Settings…", action: openSettings)
        .disabled(store.isBusy)
      Spacer(minLength: 0)
      Button("Command Line Tool…", action: manageCommandLineTool)
      Button("Copy Diagnostics", action: copyDiagnostics)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
  }

  // MARK: - Copy

  private static func activityLabel(_ activity: AppCoordinator.Activity) -> String {
    switch activity {
    case .applyingSettings:
      "Saving settings…"
    case .locking:
      "Locking…"
    case .requestingAccessibility:
      "Requesting Accessibility access…"
    case .restartingAgent:
      "Restarting the background agent…"
    case .startingSafetyCheck:
      "Starting the safety check…"
    case .unlocking:
      "Unlocking…"
    case .updatingAgent:
      "Updating the background agent…"
    }
  }

  private static func stateSummary(_ state: AppCoordinator.State) -> String {
    switch state {
    case .checking:
      "Checking the background agent…"

    case .agentApprovalRequired:
      "Enable KeyboardLocker in System Settings → General → Login Items."

    case let .agentReplacementInProgress(message),
         let .agentUpdateRequired(_, message),
         let .unavailable(message, _):
      message

    case .accessibilityRequired:
      "The background agent needs Accessibility access before it can filter keyboard events."

    case .ready:
      "The background agent is ready. Mouse and trackpad stay available while locked."
    }
  }
}
