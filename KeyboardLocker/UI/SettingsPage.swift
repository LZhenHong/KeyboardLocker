import Client
import SwiftUI

/// The popover's settings page: edits the Agent's persisted configuration, with a header that
/// returns to the status page.
///
/// The view never stores settings of its own beyond the in-progress edit: `draft` is seeded from
/// the Agent's published values and reset whenever they change, so a failed or superseded write
/// cannot leave the form showing a configuration that is not stored.
struct SettingsPage: View {
  @ObservedObject var store: AppUIStore
  let goBack: () -> Void

  @State private var draft: KeyboardLockerSettings?
  @State private var hotkeyRejection: KeyboardLockerSettingsValidationError?
  @State private var isConfirmingDisabledAutoUnlock = false

  private static let timeoutChoices: [TimeInterval] = [15, 30, 60, 120, 300, 600, 1800, 3600]

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Divider()
      body(for: store.settingsUnavailableMessage)
        .padding(16)
    }
    .onAppear {
      // Re-read on appear in case a change was made from another surface while this was closed.
      store.reconcile()
      syncDraft()
    }
    .onChange(of: store.editableSettings) { _ in
      syncDraft()
    }
    .confirmationDialog(
      "Turn off auto-unlock?",
      isPresented: $isConfirmingDisabledAutoUnlock
    ) {
      Button("Turn Off Auto-Unlock", role: .destructive) {
        commit(policy: .disabled)
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(
        """
        The keyboard will stay locked until you unlock it with the hotkey, the notification's \
        Unlock Now button, the menu bar, a widget, or `klock unlock`. Without a timeout there is \
        no automatic recovery if the hotkey does not reach KeyboardLocker.
        """
      )
    }
  }

  // MARK: - Header

  private var header: some View {
    HStack(spacing: 6) {
      Button(action: goBack) {
        Label("Back", systemImage: "chevron.backward")
          .labelStyle(.titleAndIcon)
      }
      .buttonStyle(.borderless)

      Spacer(minLength: 0)

      Text("Settings")
        .font(.headline)

      Spacer(minLength: 0)

      // Balances the leading back button so the title stays centered.
      Label("Back", systemImage: "chevron.backward")
        .labelStyle(.titleAndIcon)
        .hidden()
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
  }

  // MARK: - Body

  @ViewBuilder
  private func body(for unavailableMessage: String?) -> some View {
    if let unavailableMessage {
      UnavailableRow(message: unavailableMessage) {
        store.reconcile()
      }
    } else if let draft {
      VStack(alignment: .leading, spacing: 18) {
        hotkeySection(draft: draft)
        autoUnlockSection(draft: draft)
        statusFootnotes
      }
    } else {
      HStack(spacing: 8) {
        ProgressView().controlSize(.small)
        Text("Reading settings from the background agent…")
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  // MARK: - Sections

  private func hotkeySection(draft: KeyboardLockerSettings) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      SectionHeader("Unlock Hotkey")

      HotkeyRecorderField(
        hotkey: draft.unlockHotkey,
        isEnabled: store.canEditSettings
      ) { outcome in
        switch outcome {
        case let .accepted(hotkey):
          hotkeyRejection = nil
          commit(hotkey: hotkey)
        case let .rejected(error):
          hotkeyRejection = error
        }
      }
      .frame(maxWidth: .infinity)

      if let hotkeyRejection {
        Label {
          VStack(alignment: .leading, spacing: 2) {
            Text(hotkeyRejection.localizedDescription)
            if let suggestion = hotkeyRejection.recoverySuggestion {
              Text(suggestion).foregroundStyle(.secondary)
            }
          }
        } icon: {
          Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
        .font(.caption)
      } else {
        Text("Click the field, then press the shortcut you want to use to unlock the keyboard.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  private func autoUnlockSection(draft: KeyboardLockerSettings) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      SectionHeader("Auto-Unlock")

      Picker("Unlock automatically", selection: autoUnlockSelection(draft: draft)) {
        ForEach(Self.timeoutChoices, id: \.self) { seconds in
          Text(Self.timeoutLabel(seconds)).tag(TimeInterval?.some(seconds))
        }
        Divider()
        Text("Never (not recommended)").tag(TimeInterval?.none)
      }
      .labelsHidden()
      .disabled(!store.canEditSettings)

      Text(Self.autoUnlockFooter(for: draft.autoUnlockPolicy))
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  @ViewBuilder
  private var statusFootnotes: some View {
    if store.snapshot.hasSettingsPendingNextLock {
      footnote(
        "Saved. The keyboard is locked right now, so these values take effect on the next lock.",
        systemImage: "clock.badge.checkmark"
      )
    } else if store.isLocked {
      footnote(
        "The keyboard is locked. Changes take effect on the next lock.",
        systemImage: "clock"
      )
    }

    if let error = store.snapshot.lastError {
      footnote(error, systemImage: "exclamationmark.triangle.fill", tint: .orange)
    }
  }

  private func footnote(
    _ text: String,
    systemImage: String,
    tint: Color = .secondary
  ) -> some View {
    Label {
      Text(text).fixedSize(horizontal: false, vertical: true)
    } icon: {
      Image(systemName: systemImage).foregroundStyle(tint)
    }
    .font(.caption)
    .foregroundStyle(.secondary)
  }

  // MARK: - Editing

  private func autoUnlockSelection(
    draft: KeyboardLockerSettings
  ) -> Binding<TimeInterval?> {
    Binding(
      get: { draft.autoUnlockPolicy.timeout },
      set: { newValue in
        guard let seconds = newValue else {
          // Reachable but gated: removing the fail-safe deserves an explicit decision.
          isConfirmingDisabledAutoUnlock = true
          return
        }
        commit(policy: .timed(seconds: seconds))
      }
    )
  }

  private func commit(hotkey: KeyboardLockerSettings.Hotkey) {
    guard var updated = draft else {
      return
    }
    updated.unlockHotkey = hotkey
    commit(updated)
  }

  private func commit(policy: KeyboardLockerSettings.AutoUnlockPolicy) {
    guard var updated = draft else {
      return
    }
    updated.autoUnlockPolicy = policy
    commit(updated)
  }

  private func commit(_ settings: KeyboardLockerSettings) {
    // Show the intent immediately, but the Agent's reply is what ultimately lands in `draft` via
    // `store.editableSettings`.
    draft = settings
    store.applySettings(settings)
  }

  private func syncDraft() {
    draft = store.editableSettings
    hotkeyRejection = nil
  }

  // MARK: - Copy

  private static func timeoutLabel(_ seconds: TimeInterval) -> String {
    let minutes = Int(seconds) / 60
    let remainder = Int(seconds) % 60
    if minutes == 0 {
      return "After \(remainder) seconds"
    }
    if remainder == 0 {
      return minutes == 1 ? "After 1 minute" : "After \(minutes) minutes"
    }
    return "After \(minutes)m \(remainder)s"
  }

  private static func autoUnlockFooter(
    for policy: KeyboardLockerSettings.AutoUnlockPolicy
  ) -> String {
    switch policy {
    case .disabled:
      """
      Auto-unlock is off. Unlock with the hotkey, the notification's Unlock Now button, the menu \
      bar, a widget, or `klock unlock`.
      """
    case .timed:
      """
      The background agent owns this timer, so it still releases the keyboard if KeyboardLocker \
      quits. The countdown pauses while the Mac is asleep.
      """
    }
  }
}

// MARK: - Shared small views

private struct SectionHeader: View {
  let title: String

  init(_ title: String) {
    self.title = title
  }

  var body: some View {
    Text(title.uppercased())
      .font(.caption.weight(.semibold))
      .foregroundStyle(.secondary)
  }
}

/// Shared presentation for an agent value the app could not read.
private struct UnavailableRow: View {
  let message: String
  let retry: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label {
        VStack(alignment: .leading, spacing: 2) {
          Text("Settings are unavailable")
          Text(message)
            .font(.callout)
            .foregroundStyle(.secondary)
        }
      } icon: {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
      }
      Button("Try Again", action: retry)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
