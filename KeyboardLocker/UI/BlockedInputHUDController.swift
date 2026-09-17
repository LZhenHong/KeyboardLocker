import AppKit
import Client
import SwiftUI

/// Shows a brief, non-activating hint when the Agent reports swallowed keystrokes while locked.
///
/// The Agent throttles the signal at the input boundary; this controller only maps it to
/// presentation. Following the same rule as the state broadcast, the notification is treated
/// as a hint, not truth: nothing is shown unless the coordinator's authoritative snapshot still
/// says the keyboard is locked, so a nudge posted just before an unlock cannot flash afterwards.
@MainActor
final class BlockedInputHUDController {
  /// What the HUD renders: the configured unlock affordances, straight from the Agent's active
  /// settings. Phrase presence only — the phrase itself never crosses into presentation.
  struct Hint: Equatable {
    var hotkeyDisplay: String
    var hasUnlockPhrase: Bool
  }

  /// Coalesces the Darwin + Distributed pair posted for one Agent signal, plus any burst that
  /// slipped past the Agent-side throttle.
  private static let presentationCoalescingWindow: TimeInterval = 1

  private let hintProvider: @MainActor () -> Hint?
  private let present: @MainActor (Hint) -> Void
  private let now: () -> Date
  // Optional-with-default so the observer closure may capture `self` during init: by the time
  // it is installed, every other stored property already has a value.
  private var signalObserver: BlockedInputSignalObserver? = nil
  private var lastPresentedAt: Date?

  init(
    hintProvider: @escaping @MainActor () -> Hint?,
    present: @escaping @MainActor (Hint) -> Void,
    now: @escaping () -> Date = { Date() }
  ) {
    self.hintProvider = hintProvider
    self.present = present
    self.now = now
    signalObserver = BlockedInputSignalObserver { [weak self] in
      MainActor.assumeIsolated {
        self?.handleSignal()
      }
    }
  }

  convenience init(hintProvider: @escaping @MainActor () -> Hint?) {
    let presenter = BlockedInputHUDPresenter()
    self.init(hintProvider: hintProvider) { hint in
      presenter.show(hint)
    }
  }

  func handleSignal() {
    let now = now()
    if let lastPresentedAt,
       now.timeIntervalSince(lastPresentedAt) < Self.presentationCoalescingWindow {
      return
    }
    guard let hint = hintProvider() else {
      return
    }
    lastPresentedAt = now
    present(hint)
  }
}

/// Owns the Darwin + Distributed registrations for the blocked-input hint so teardown is just
/// releasing the token. Mirrors the two-channel rationale in `LockStateSubscriber`: Darwin can
/// wake an App-Napped app, Distributed is the reliable path for a running main run loop.
private final class BlockedInputSignalObserver: @unchecked Sendable {
  private let handler: @Sendable () -> Void
  private var distributedObserver: NSObjectProtocol?

  init(handler: @escaping @Sendable () -> Void) {
    self.handler = handler
    let name = NotificationNames.blockedInput
    CFNotificationCenterAddObserver(
      CFNotificationCenterGetDarwinNotifyCenter(),
      Unmanaged.passUnretained(self).toOpaque(),
      { _, observer, _, _, _ in
        guard let observer else {
          return
        }
        Unmanaged<BlockedInputSignalObserver>.fromOpaque(observer)
          .takeUnretainedValue()
          .fire()
      },
      name as CFString,
      nil,
      .deliverImmediately
    )
    distributedObserver = DistributedNotificationCenter.default().addObserver(
      forName: Notification.Name(name),
      object: nil,
      queue: .main,
      using: { _ in handler() }
    )
  }

  private func fire() {
    handler()
  }

  deinit {
    CFNotificationCenterRemoveObserver(
      CFNotificationCenterGetDarwinNotifyCenter(),
      Unmanaged.passUnretained(self).toOpaque(),
      CFNotificationName(NotificationNames.blockedInput as CFString),
      nil
    )
    if let distributedObserver {
      DistributedNotificationCenter.default().removeObserver(distributedObserver)
    }
  }
}

/// Borderless, non-activating bezel shown at the center of the main screen — the same place
/// macOS puts the volume/brightness HUD, because that is where the eyes already are when a
/// keypress gets no response. It never takes focus and never intercepts clicks — while locked,
/// the mouse is the only working input and the HUD must not get in its way.
@MainActor
private final class BlockedInputHUDPresenter {
  private static let visibleDuration: TimeInterval = 2.4
  private static let fadeDuration: TimeInterval = 0.2

  private var panel: NSPanel?
  private var dismissTask: Task<Void, Never>?

  func show(_ hint: BlockedInputHUDController.Hint) {
    // A signal arriving while visible refreshes the content and restarts the dismiss clock
    // instead of stacking panels.
    dismissTask?.cancel()

    let panel = panel ?? makePanel()
    self.panel = panel
    let hostingView = NSHostingView(rootView: BlockedInputHUDView(hint: hint))
    panel.contentView = hostingView
    panel.setContentSize(hostingView.fittingSize)
    positionAtCenterOfMainScreen(panel)

    panel.alphaValue = 0
    panel.orderFrontRegardless()
    NSAnimationContext.runAnimationGroup { context in
      context.duration = Self.fadeDuration
      panel.animator().alphaValue = 1
    }

    dismissTask = Task { @MainActor [weak panel] in
      try? await Task.sleep(for: .seconds(Self.visibleDuration))
      guard !Task.isCancelled, let panel else {
        return
      }
      NSAnimationContext.runAnimationGroup { context in
        context.duration = Self.fadeDuration
        panel.animator().alphaValue = 0
      } completionHandler: {
        panel.orderOut(nil)
      }
    }
  }

  private func makePanel() -> NSPanel {
    let panel = NSPanel(
      contentRect: .zero,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.hidesOnDeactivate = false
    panel.ignoresMouseEvents = true
    panel.level = .statusBar
    panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    panel.isReleasedWhenClosed = false
    return panel
  }

  private func positionAtCenterOfMainScreen(_ panel: NSPanel) {
    guard let screen = NSScreen.main else {
      return
    }
    let origin = NSPoint(
      x: screen.visibleFrame.midX - panel.frame.width / 2,
      y: screen.visibleFrame.midY - panel.frame.height / 2
    )
    panel.setFrameOrigin(origin)
  }
}

/// The bezel content: a large amber lock glyph over the state line and the configured unlock
/// affordances, sized to read from across the desk. Mirrors the Agent notification's copy
/// rule — the phrase gesture is advertised, never its contents. The entrance pop is what
/// separates "something just reacted to my keypress" from static UI.
private struct BlockedInputHUDView: View {
  let hint: BlockedInputHUDController.Hint

  @State private var appeared = false

  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: "lock.fill")
        .font(.system(size: 44))
        .foregroundStyle(.orange)
      VStack(spacing: 4) {
        Text("Keyboard Locked")
          .font(.title3.weight(.semibold))
        Text(unlockLine)
          .font(.callout)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }
    }
    .padding(.horizontal, 28)
    .padding(.vertical, 24)
    .background(
      .regularMaterial,
      in: RoundedRectangle(cornerRadius: 20, style: .continuous)
    )
    .scaleEffect(appeared ? 1 : 0.85)
    .opacity(appeared ? 1 : 0)
    .onAppear {
      withAnimation(.spring(duration: 0.25, bounce: 0.35)) {
        appeared = true
      }
    }
  }

  private var unlockLine: String {
    var line = "Press \(hint.hotkeyDisplay) to unlock"
    if hint.hasUnlockPhrase {
      line += " or type your unlock phrase"
    }
    return line
  }
}
