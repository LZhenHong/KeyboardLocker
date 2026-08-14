import Foundation
@testable import Service
import Testing

@Suite(.serialized)
struct LockEngineAutoUnlockScheduleTests {
  private let initialDate = Date(timeIntervalSinceReferenceDate: 1000)

  @Test
  func initialScheduleUsesTimeoutForDeadlineAndDelay() throws {
    let schedule = try #require(
      AutoUnlockSchedule.make(
        timeout: 60,
        referenceDate: initialDate,
        currentDate: initialDate
      )
    )

    #expect(schedule.deadline == initialDate.addingTimeInterval(60))
    #expect(schedule.delay == 60)
  }

  @Test
  func explicitRearmStartsANewTimeoutWindow() throws {
    let initialSchedule = try #require(
      AutoUnlockSchedule.make(
        timeout: 60,
        referenceDate: initialDate,
        currentDate: initialDate
      )
    )
    let rearmDate = initialDate.addingTimeInterval(15)
    let rearmedSchedule = try #require(
      AutoUnlockSchedule.make(
        timeout: 60,
        referenceDate: rearmDate,
        currentDate: rearmDate
      )
    )

    #expect(rearmedSchedule.deadline == rearmDate.addingTimeInterval(60))
    #expect(rearmedSchedule.delay == 60)
    #expect(
      rearmedSchedule.deadline.timeIntervalSince(initialSchedule.deadline) == 15
    )
  }

  @Test
  func pastDeadlineSchedulesImmediateUnlock() throws {
    let schedule = try #require(
      AutoUnlockSchedule.make(
        timeout: 10,
        referenceDate: initialDate,
        currentDate: initialDate.addingTimeInterval(15)
      )
    )

    #expect(schedule.deadline == initialDate.addingTimeInterval(10))
    #expect(schedule.delay == 0)
  }

  @Test
  func invalidTimeoutDoesNotCreateSchedule() {
    let invalidTimeouts: [TimeInterval?] = [
      nil,
      0,
      -1,
      .nan,
      .infinity,
      -.infinity,
    ]

    for timeout in invalidTimeouts {
      #expect(
        AutoUnlockSchedule.make(
          timeout: timeout,
          referenceDate: initialDate,
          currentDate: initialDate
        ) == nil,
        "Expected \(String(describing: timeout)) to be rejected"
      )
    }
  }
}
