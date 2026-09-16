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
  let actions: PopoverActions
  let goBack: () -> Void

  @State private var draft: KeyboardLockerSettings?
  @State private var hotkeyRejection: KeyboardLockerSettingsValidationError?
  @State private var timeoutText = ""
  @State private var timeoutUnit: TimeoutUnit = .seconds
  @State private var timeoutRejection: String?
  @State private var lastTimedSeconds: TimeInterval = 60
  @FocusState private var timeoutFieldFocused: Bool

  private enum TimeoutUnit {
    case seconds
    case minutes

    var factor: TimeInterval {
      self == .minutes ? 60 : 1
    }

    var label: String {
      self == .minutes ? "min" : "sec"
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Divider()
      body(for: store.settingsUnavailableMessage)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
      Divider()
      // App-side tools stay reachable even when the Agent's settings are unavailable.
      toolsSection
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
    .onAppear {
      // Re-read on appear in case a change was made from another surface while this was closed.
      store.reconcile()
      syncDraft()
    }
    .onChange(of: store.editableSettings) { _ in
      syncDraft()
    }
    .onChange(of: timeoutFieldFocused) { focused in
      if !focused {
        settleTimeoutFieldOnFocusLoss()
      }
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
    .padding(.vertical, 8)
  }

  // MARK: - Body

  @ViewBuilder
  private func body(for unavailableMessage: String?) -> some View {
    if let unavailableMessage {
      UnavailableRow(message: unavailableMessage) {
        store.reconcile()
      }
    } else if let draft {
      VStack(alignment: .leading, spacing: 10) {
        hotkeyRow(draft: draft)
        autoUnlockRows(draft: draft)
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

  private func hotkeyRow(draft: KeyboardLockerSettings) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text("Unlock Hotkey")
        Spacer(minLength: 12)
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
        .frame(width: 120)
      }
      .help("Click, then press a shortcut.")

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
      }
    }
  }

  private func autoUnlockRows(draft: KeyboardLockerSettings) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("Auto-Unlock")
        Spacer(minLength: 12)
        Toggle("Auto-unlock", isOn: autoUnlockEnabledBinding(draft: draft))
          .labelsHidden()
          .disabled(!store.canEditSettings)
      }
      .help("The background agent owns this timer and unlocks even if KeyboardLocker quits. The countdown pauses while the Mac is asleep.")

      // The duration editor only exists while auto-unlock is on; a disabled editor would read
      // as broken, and a hidden one costs nothing because its task context is gone.
      if draft.autoUnlockPolicy.timeout != nil {
        HStack {
          Text("Duration")
          Spacer(minLength: 12)
          TextField("", text: $timeoutText)
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .frame(width: 64)
            .focused($timeoutFieldFocused)
            .onSubmit(commitTimeoutText)
            .disabled(!store.canEditSettings)

          Picker("Unit", selection: timeoutUnitBinding) {
            Text(TimeoutUnit.seconds.label).tag(TimeoutUnit.seconds)
            Text(TimeoutUnit.minutes.label).tag(TimeoutUnit.minutes)
          }
          .labelsHidden()
          .fixedSize()
          .disabled(!store.canEditSettings)
        }

        if let timeoutRejection {
          Text(timeoutRejection)
            .font(.caption)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
  }

  private var toolsSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      // Rendered only when it can actually run: a disabled button would read as broken here.
      if store.canRunSafetyCheck {
        Button(action: actions.confirmSafetyCheck) {
          Label("Run 10-Second Safety Check", systemImage: "checkmark.shield")
        }
        .help("Lock the keyboard for 10 seconds to prove the unlock paths work. The mouse stays usable and the agent always unlocks.")
      }

      Button(action: actions.manageCommandLineTool) {
        Label("Manage klock Command…", systemImage: "terminal")
      }
      .help("Install, remove, or get the PATH command for the `klock` Terminal command. Shell configuration files are never modified.")
    }
    .buttonStyle(.borderless)
    .labelStyle(.titleAndIcon)
    .frame(maxWidth: .infinity, alignment: .leading)
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

  private func autoUnlockEnabledBinding(
    draft: KeyboardLockerSettings
  ) -> Binding<Bool> {
    Binding(
      get: { draft.autoUnlockPolicy.timeout != nil },
      set: { enabled in
        // Toggling off disables the fail-safe directly; the user can always turn it back on.
        commit(policy: enabled ? .timed(seconds: lastTimedSeconds) : .disabled)
      }
    )
  }

  /// Switching units converts the current value instead of silently reinterpreting it, and a
  /// valid displayed value commits immediately so the text can never lie about what is stored.
  private var timeoutUnitBinding: Binding<TimeoutUnit> {
    Binding(
      get: { timeoutUnit },
      set: { newUnit in
        let oldUnit = timeoutUnit
        timeoutUnit = newUnit
        guard let value = Double(timeoutText), value > 0 else {
          return
        }
        timeoutText = Self.formatTimeout(value * oldUnit.factor, unit: newUnit)
        commitTimeoutText()
      }
    )
  }

  private func commitTimeoutText() {
    guard let draft else {
      return
    }
    guard let value = Double(timeoutText.trimmingCharacters(in: .whitespaces)), value > 0 else {
      timeoutRejection = "Enter a positive number."
      return
    }
    let seconds = (value * timeoutUnit.factor).rounded()
    do {
      _ = try KeyboardLockerSettings(
        autoUnlockPolicy: .timed(seconds: seconds),
        unlockHotkey: draft.unlockHotkey
      )
      .validated()
    } catch {
      timeoutRejection = error.localizedDescription
      return
    }
    timeoutRejection = nil
    if draft.autoUnlockPolicy.timeout != seconds {
      commit(policy: .timed(seconds: seconds))
    }
  }

  /// Returning focus means the field either commits a valid value or snaps back to the stored
  /// one — the text must never keep showing a value the Agent does not hold.
  private func settleTimeoutFieldOnFocusLoss() {
    commitTimeoutText()
    if timeoutRejection != nil {
      timeoutRejection = nil
      if let seconds = draft?.autoUnlockPolicy.timeout {
        timeoutText = Self.formatTimeout(seconds, unit: timeoutUnit)
      }
    }
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

    // Never clobber the field while the user is typing in it.
    guard !timeoutFieldFocused,
          let seconds = store.editableSettings?.autoUnlockPolicy.timeout
    else {
      return
    }
    lastTimedSeconds = seconds
    timeoutRejection = nil
    if seconds >= 60, seconds.truncatingRemainder(dividingBy: 60) == 0 {
      timeoutUnit = .minutes
    } else {
      timeoutUnit = .seconds
    }
    timeoutText = Self.formatTimeout(seconds, unit: timeoutUnit)
  }

  // MARK: - Copy

  private static func formatTimeout(_ seconds: TimeInterval, unit: TimeoutUnit) -> String {
    let value = seconds / unit.factor
    if value.rounded() == value {
      return "\(Int(value))"
    }
    return String(value)
  }
}

// MARK: - Shared small views

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
