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
  @State private var phraseText = ""
  @State private var phraseRejection: String?
  @State private var lastPhrase = "unlock"
  @FocusState private var timeoutFieldFocused: Bool
  @FocusState private var phraseFieldFocused: Bool

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
    .onChange(of: phraseFieldFocused) { focused in
      if !focused {
        settlePhraseFieldOnFocusLoss()
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
      VStack(alignment: .leading, spacing: 14) {
        unlockSection(draft: draft)
        autoUnlockSection(draft: draft)
        statusFootnotes
      }
    } else {
      HStack(spacing: 8) {
        ProgressView().controlSize(.small)
        Text("Reading settings…")
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  // MARK: - Sections

  /// Grouped card in the System Settings style: a quiet section label above, rows inside a
  /// rounded background, and a footer slot that carries guidance normally and the current
  /// validation error when there is one. The slot is permanent, so an error swapping in never
  /// shifts the form's layout.
  private func unlockSection(draft: KeyboardLockerSettings) -> some View {
    settingsSection("Unlock") {
      settingsRow("Unlock Hotkey") {
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
        .frame(width: 124)
      }

      rowDivider

      settingsRow("Unlock Phrase") {
        Toggle("Unlock phrase", isOn: phraseEnabledBinding(draft: draft))
          .labelsHidden()
          .toggleStyle(.switch)
          .disabled(!store.canEditSettings)
      }

      // The editor only exists while the gesture is on; a disabled field would read as broken.
      if draft.unlockPhrase != nil {
        rowDivider

        settingsRow("Phrase") {
          TextField("", text: $phraseText)
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .frame(width: 140)
            .focused($phraseFieldFocused)
            .onSubmit(commitPhraseText)
            .disabled(!store.canEditSettings)
        }
      }
    } footer: {
      if let hotkeyRejection {
        errorFooter {
          Text(hotkeyRejection.localizedDescription)
          if let suggestion = hotkeyRejection.recoverySuggestion {
            Text(suggestion).foregroundStyle(.secondary)
          }
        }
      } else if let phraseRejection {
        errorFooter { Text(phraseRejection) }
      } else if draft.unlockPhrase != nil {
        hintFooter("Type this while locked to unlock. Lowercase letters, digits, and spaces; 3–64 characters.")
      } else {
        hintFooter("Click the field, then press a shortcut.")
      }
    }
  }

  private func autoUnlockSection(draft: KeyboardLockerSettings) -> some View {
    settingsSection("Auto-Unlock") {
      settingsRow("Enabled") {
        Toggle("Auto-unlock", isOn: autoUnlockEnabledBinding(draft: draft))
          .labelsHidden()
          .toggleStyle(.switch)
          .disabled(!store.canEditSettings)
      }

      // The duration editor only exists while auto-unlock is on; a disabled editor would read
      // as broken, and a hidden one costs nothing because its task context is gone.
      if draft.autoUnlockPolicy.timeout != nil {
        rowDivider

        settingsRow("Duration") {
          HStack(spacing: 8) {
            TextField("", text: $timeoutText)
              .textFieldStyle(.roundedBorder)
              .multilineTextAlignment(.trailing)
              .frame(width: 48)
              .focused($timeoutFieldFocused)
              .onSubmit(commitTimeoutText)
              .disabled(!store.canEditSettings)

            Picker("Unit", selection: timeoutUnitBinding) {
              Text(TimeoutUnit.seconds.label).tag(TimeoutUnit.seconds)
              Text(TimeoutUnit.minutes.label).tag(TimeoutUnit.minutes)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .fixedSize()
            .disabled(!store.canEditSettings)
          }
        }
      }
    } footer: {
      if let timeoutRejection {
        errorFooter { Text(timeoutRejection) }
      } else if draft.autoUnlockPolicy.timeout != nil {
        hintFooter("Unlocks even if KeyboardLocker quits. 5 seconds to 60 minutes.")
      } else {
        hintFooter("Unlocks automatically after the set duration, even if KeyboardLocker quits.")
      }
    }
  }

  // MARK: - Section pieces

  private func settingsSection<Content: View, Footer: View>(
    _ title: String,
    @ViewBuilder content: () -> Content,
    @ViewBuilder footer: () -> Footer
  ) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .font(.caption.weight(.medium))
        .textCase(.uppercase)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)

      VStack(spacing: 0) {
        content()
      }
      .background(
        Color(nsColor: .controlBackgroundColor),
        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
      )

      footer()
    }
  }

  private func settingsRow<Control: View>(
    _ title: String,
    @ViewBuilder control: () -> Control
  ) -> some View {
    HStack {
      Text(title)
      Spacer(minLength: 12)
      control()
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 7)
  }

  /// Indented so the line separates the row contents rather than the card edges.
  private var rowDivider: some View {
    Divider()
      .padding(.leading, 12)
  }

  private func hintFooter(_ text: String) -> some View {
    Text(text)
      .font(.caption)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
      .padding(.horizontal, 12)
  }

  private func errorFooter<Content: View>(
    @ViewBuilder content: () -> Content
  ) -> some View {
    Label {
      VStack(alignment: .leading, spacing: 2, content: content)
    } icon: {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)
    }
    .font(.caption)
    .fixedSize(horizontal: false, vertical: true)
    .padding(.horizontal, 12)
  }

  private var toolsSection: some View {
    HStack(spacing: 8) {
      // Rendered only when it can actually run: a disabled button would read as broken here.
      if store.canRunSafetyCheck {
        toolButton("Safety Check…", systemImage: "checkmark.shield") {
          actions.confirmSafetyCheck()
        }
        .help("Locks the keyboard for 10 seconds to verify unlocking works. Mouse stays usable; the agent always unlocks.")
      }

      toolButton("klock CLI…", systemImage: "terminal") {
        actions.manageCommandLineTool()
      }
      .help("Install or remove the `klock` Terminal command. Shell profiles are never modified.")
    }
  }

  /// Full-width bordered button, the same affordance language as the status page's recovery
  /// buttons — a bare label read as text, not as something clickable.
  private func toolButton(
    _ title: String,
    systemImage: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Label(title, systemImage: systemImage)
        .frame(maxWidth: .infinity)
    }
    .buttonStyle(.bordered)
  }

  @ViewBuilder
  private var statusFootnotes: some View {
    if store.snapshot.hasSettingsPendingNextLock {
      footnote(
        "Saved — takes effect on the next lock (keyboard is locked).",
        systemImage: "clock.badge.checkmark"
      )
    } else if store.isLocked {
      footnote(
        "Locked now — changes take effect on the next lock.",
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

  private func phraseEnabledBinding(
    draft: KeyboardLockerSettings
  ) -> Binding<Bool> {
    Binding(
      get: { draft.unlockPhrase != nil },
      set: { enabled in
        // Toggling off drops the gesture entirely; toggling on restores the last edited phrase.
        commit(phrase: enabled ? lastPhrase : nil)
      }
    )
  }

  /// Same contract as the timeout field: a valid value commits immediately; an invalid one is
  /// rejected with the shared guardrail's message and the field snaps back on focus loss, so the
  /// text can never keep showing a phrase the Agent does not hold.
  private func commitPhraseText() {
    guard let draft else {
      return
    }
    let normalized: String?
    do {
      normalized = try KeyboardLockerSettings(
        autoUnlockPolicy: draft.autoUnlockPolicy,
        unlockHotkey: draft.unlockHotkey,
        unlockPhrase: phraseText
      )
      .validated()
      .unlockPhrase
    } catch {
      phraseRejection = error.localizedDescription
      return
    }
    phraseRejection = nil
    if let normalized, draft.unlockPhrase != normalized {
      commit(phrase: normalized)
    }
  }

  private func settlePhraseFieldOnFocusLoss() {
    commitPhraseText()
    if phraseRejection != nil {
      phraseRejection = nil
      phraseText = draft?.unlockPhrase ?? ""
    }
  }

  private func commit(phrase: String?) {
    guard var updated = draft else {
      return
    }
    updated.unlockPhrase = phrase
    commit(updated)
  }

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

    if let phrase = store.editableSettings?.unlockPhrase {
      lastPhrase = phrase
    }
    if !phraseFieldFocused {
      phraseText = store.editableSettings?.unlockPhrase ?? ""
      phraseRejection = nil
    }

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
