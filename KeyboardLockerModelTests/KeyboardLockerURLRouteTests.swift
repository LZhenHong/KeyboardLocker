import Foundation
import XCTest

final class KeyboardLockerURLRouteTests: XCTestCase {
  func testCanonicalURLsMapToDesiredStateActions() throws {
    XCTAssertEqual(
      try KeyboardLockerURLRoute(url: url("keyboardlocker://lock")).action,
      .lock
    )
    XCTAssertEqual(
      try KeyboardLockerURLRoute(url: url("keyboardlocker://unlock")).action,
      .unlock
    )
    XCTAssertEqual(
      try KeyboardLockerURLRoute(url: url("keyboardlocker://status")).action,
      .status
    )
  }

  func testSchemeAndHostFollowURLCaseInsensitivity() throws {
    XCTAssertEqual(
      try KeyboardLockerURLRoute(url: url("KEYBOARDLOCKER://LOCK")).action,
      .lock
    )
  }

  func testInvalidOrAmbiguousShapesAreRejected() {
    let invalidURLs = [
      "https://lock",
      "keyboardlocker:lock",
      "keyboardlocker://",
      "keyboardlocker://toggle",
      "keyboardlocker://lock/",
      "keyboardlocker://lock/path",
      "keyboardlocker://lock?",
      "keyboardlocker://lock?source=test",
      "keyboardlocker://lock#fragment",
      "keyboardlocker://lock:1234",
      "keyboardlocker://user@lock",
      "keyboardlocker://user:password@lock",
      "keyboardlocker://%6cock",
    ]

    for value in invalidURLs {
      XCTAssertThrowsError(
        try KeyboardLockerURLRoute(url: url(value)),
        "Expected \(value) to be rejected."
      ) { error in
        XCTAssertEqual(error as? KeyboardLockerURLRouteError, .invalidURL)
      }
    }
  }

  func testMultipleURLsPreserveDeliveryOrderAndRepresentFailures() {
    let requests = KeyboardLockerURLRoute.requests(for: [
      url("keyboardlocker://lock"),
      url("keyboardlocker://invalid"),
      url("keyboardlocker://unlock"),
    ])

    XCTAssertEqual(requests.count, 3)
    XCTAssertEqual(requests[0], .action(.lock))
    guard case let .failure(failure) = requests[1] else {
      return XCTFail("Expected the invalid route to become a failure request.")
    }
    XCTAssertTrue(failure.message.contains("invalid automation URL"))
    XCTAssertFalse(failure.message.contains("keyboardlocker://invalid"))
    XCTAssertEqual(requests[2], .action(.unlock))
  }

  func testFailureMessageNeverEchoesQueryData() {
    let requests = KeyboardLockerURLRoute.requests(for: [
      url("keyboardlocker://lock?token=do-not-echo"),
    ])

    guard case let .failure(failure) = requests.first else {
      return XCTFail("Expected the URL to be rejected.")
    }
    XCTAssertFalse(failure.message.contains("do-not-echo"))
  }

  private func url(_ value: String) -> URL {
    guard let url = URL(string: value) else {
      preconditionFailure("The test URL must be syntactically representable: \(value)")
    }
    return url
  }
}
