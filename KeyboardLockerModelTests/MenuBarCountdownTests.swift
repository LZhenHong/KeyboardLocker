import Foundation
import Testing

@Suite(.serialized)
struct MenuBarCountdownTests {
  private let now = Date(timeIntervalSinceReferenceDate: 10_000)

  @Test
  func noDeadlineProducesNoTitle() {
    #expect(MenuBarCountdown.text(deadline: nil, now: now) == nil)
  }

  @Test
  func remainingTimeFormatsAsPaddedMinutesAndSeconds() {
    #expect(text(remaining: 90) == "01:30")
    #expect(text(remaining: 60) == "01:00")
    #expect(text(remaining: 5) == "00:05")
    #expect(text(remaining: 3600) == "60:00")
  }

  @Test
  func fractionalRemainingRoundsUp() {
    // The display must never reach zero before the deadline itself.
    #expect(text(remaining: 59.4) == "01:00")
    #expect(text(remaining: 0.2) == "00:01")
  }

  @Test
  func passedDeadlineClampsAtZero() {
    #expect(text(remaining: -3) == "00:00")
  }

  @Test
  func everyAllowedValueKeepsTheConstantFiveCharacterWidth() {
    // The width-stability invariant the status item relies on: any deadline the settings
    // guardrails allow (5...3600 seconds) renders exactly five characters.
    for seconds in stride(from: 5, through: 3600, by: 37) {
      #expect(text(remaining: TimeInterval(seconds))?.count == 5)
    }
  }

  private func text(remaining: TimeInterval) -> String? {
    MenuBarCountdown.text(deadline: now.addingTimeInterval(remaining), now: now)
  }
}
