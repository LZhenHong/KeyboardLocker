import Foundation
@testable import Service
import XCTest

final class LockEngineAutoUnlockScheduleTests: XCTestCase {
  private let initialDate = Date(timeIntervalSinceReferenceDate: 1000)

  func testInitialScheduleUsesTimeoutForDeadlineAndDelay() throws {
    let schedule = try XCTUnwrap(
      AutoUnlockSchedule.make(
        timeout: 60,
        referenceDate: initialDate,
        currentDate: initialDate
      )
    )

    XCTAssertEqual(schedule.deadline, initialDate.addingTimeInterval(60))
    XCTAssertEqual(schedule.delay, 60)
  }

  func testExplicitRearmStartsANewTimeoutWindow() throws {
    let initialSchedule = try XCTUnwrap(
      AutoUnlockSchedule.make(
        timeout: 60,
        referenceDate: initialDate,
        currentDate: initialDate
      )
    )
    let rearmDate = initialDate.addingTimeInterval(15)
    let rearmedSchedule = try XCTUnwrap(
      AutoUnlockSchedule.make(
        timeout: 60,
        referenceDate: rearmDate,
        currentDate: rearmDate
      )
    )

    XCTAssertEqual(rearmedSchedule.deadline, rearmDate.addingTimeInterval(60))
    XCTAssertEqual(rearmedSchedule.delay, 60)
    XCTAssertEqual(
      rearmedSchedule.deadline.timeIntervalSince(initialSchedule.deadline),
      15
    )
  }

  func testPastDeadlineSchedulesImmediateUnlock() throws {
    let schedule = try XCTUnwrap(
      AutoUnlockSchedule.make(
        timeout: 10,
        referenceDate: initialDate,
        currentDate: initialDate.addingTimeInterval(15)
      )
    )

    XCTAssertEqual(schedule.deadline, initialDate.addingTimeInterval(10))
    XCTAssertEqual(schedule.delay, 0)
  }

  func testInvalidTimeoutDoesNotCreateSchedule() {
    let invalidTimeouts: [TimeInterval?] = [
      nil,
      0,
      -1,
      .nan,
      .infinity,
      -.infinity,
    ]

    for timeout in invalidTimeouts {
      XCTAssertNil(
        AutoUnlockSchedule.make(
          timeout: timeout,
          referenceDate: initialDate,
          currentDate: initialDate
        ),
        "Expected \(String(describing: timeout)) to be rejected"
      )
    }
  }
}
