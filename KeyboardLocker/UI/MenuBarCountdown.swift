import Foundation

/// Pure formatting rules for the menu-bar countdown, isolated from AppKit so the
/// width-stability contract stays unit-testable.
enum MenuBarCountdown {
  /// Countdown text for a locked keyboard with an auto-unlock deadline, or nil when the status
  /// item should carry no title at all.
  ///
  /// The format is always zero-padded `mm:ss` — exactly five characters for every value the
  /// settings guardrails allow (5...3600 seconds). Rendered with a monospaced-digit font, that
  /// keeps the status item's width constant while it ticks, so the countdown never pushes
  /// neighboring menu bar icons around.
  static func text(deadline: Date?, now: Date) -> String? {
    guard let deadline else {
      return nil
    }
    // Rounded up so the display never reaches "00:00" before the deadline itself; a passed
    // deadline clamps at zero until the authoritative snapshot catches up.
    let totalSeconds = Int(max(0, deadline.timeIntervalSince(now).rounded(.up)))
    return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
  }
}
