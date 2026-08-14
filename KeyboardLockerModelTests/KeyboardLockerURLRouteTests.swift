import Foundation
import Testing

@Suite(.serialized)
struct KeyboardLockerURLRouteTests {
  @Test
  func canonicalURLsMapToDesiredStateActions() throws {
    #expect(
      try KeyboardLockerURLRoute(url: url("keyboardlocker://lock")).action ==
        .lock
    )
    #expect(
      try KeyboardLockerURLRoute(url: url("keyboardlocker://unlock")).action ==
        .unlock
    )
    #expect(
      try KeyboardLockerURLRoute(url: url("keyboardlocker://status")).action ==
        .status
    )
  }

  @Test
  func schemeAndHostFollowURLCaseInsensitivity() throws {
    #expect(
      try KeyboardLockerURLRoute(url: url("KEYBOARDLOCKER://LOCK")).action ==
        .lock
    )
  }

  @Test
  func invalidOrAmbiguousShapesAreRejected() {
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
      #expect(
        throws: KeyboardLockerURLRouteError.invalidURL,
        "Expected \(value) to be rejected."
      ) {
        try KeyboardLockerURLRoute(url: url(value))
      }
    }
  }

  @Test
  func multipleURLsPreserveDeliveryOrderAndRepresentFailures() {
    let requests = KeyboardLockerURLRoute.requests(for: [
      url("keyboardlocker://lock"),
      url("keyboardlocker://invalid"),
      url("keyboardlocker://unlock"),
    ])

    #expect(requests.count == 3)
    #expect(requests[0] == .action(.lock))
    guard case let .failure(failure) = requests[1] else {
      Issue.record("Expected the invalid route to become a failure request.")
      return
    }
    #expect(failure.message.contains("invalid automation URL"))
    #expect(!failure.message.contains("keyboardlocker://invalid"))
    #expect(requests[2] == .action(.unlock))
  }

  @Test
  func failureMessageNeverEchoesQueryData() {
    let requests = KeyboardLockerURLRoute.requests(for: [
      url("keyboardlocker://lock?token=do-not-echo"),
    ])

    guard case let .failure(failure) = requests.first else {
      Issue.record("Expected the URL to be rejected.")
      return
    }
    #expect(!failure.message.contains("do-not-echo"))
  }

  private func url(_ value: String) -> URL {
    guard let url = URL(string: value) else {
      preconditionFailure("The test URL must be syntactically representable: \(value)")
    }
    return url
  }
}
