import AppKit
import XCTest

final class KeyboardLockerServicesProviderTests: XCTestCase {
  private let pasteboard = NSPasteboard(name: NSPasteboard.Name("KeyboardLockerServicesProviderTests"))

  func testProviderExportsEveryDeclaredServiceSelector() {
    let provider = KeyboardLockerServicesProvider { _ in nil }

    XCTAssertTrue(provider.responds(to: NSSelectorFromString("lockKeyboard:userData:error:")))
    XCTAssertTrue(provider.responds(to: NSSelectorFromString("unlockKeyboard:userData:error:")))
    XCTAssertTrue(
      provider.responds(to: NSSelectorFromString("showKeyboardLockStatus:userData:error:"))
    )
  }

  func testHandlerLeavesErrorUntouchedWhenActionSucceeds() {
    let provider = KeyboardLockerServicesProvider { _ in nil }

    var error: NSString?
    provider.lockKeyboard(pasteboard, userData: nil, error: &error)

    XCTAssertNil(error)
  }

  @MainActor
  func testHandlerPublishesFailureBeforeScheduledPresentationRuns() async {
    let presenter = RecordingServicesFailurePresenter()
    let provider = KeyboardLockerServicesProvider(
      presentFailure: { presenter.present($0) }
    ) { _ in
      ExternalAutomationFailure(message: "Agent not reachable")
    }

    var error: NSString?
    provider.unlockKeyboard(pasteboard, userData: nil, error: &error)

    XCTAssertEqual(error, "Agent not reachable")
    XCTAssertTrue(presenter.failures.isEmpty)

    await Task.yield()

    XCTAssertEqual(presenter.failures, [.init(message: "Agent not reachable")])
  }

  func testHandlerReportsTimeoutWhenActionDoesNotFinish() {
    let provider = KeyboardLockerServicesProvider(waitTimeout: 0.1) { _ in
      try? await Task.sleep(nanoseconds: 10_000_000_000)
      return nil
    }

    var error: NSString?
    provider.showKeyboardLockStatus(pasteboard, userData: nil, error: &error)

    XCTAssertTrue(error?.contains("did not finish") == true)
  }

  @MainActor
  func testTimedOutHandlerPresentsLateFailureAfterPublishingTimeout() async {
    let presenter = RecordingServicesFailurePresenter()
    let provider = KeyboardLockerServicesProvider(
      waitTimeout: 0.01,
      presentFailure: { presenter.present($0) }
    ) { _ in
      try? await Task.sleep(nanoseconds: 50_000_000)
      return ExternalAutomationFailure(message: "Late agent failure")
    }

    var error: NSString?
    provider.lockKeyboard(pasteboard, userData: nil, error: &error)

    XCTAssertTrue(error?.contains("did not finish") == true)
    XCTAssertTrue(presenter.failures.isEmpty)

    try? await Task.sleep(nanoseconds: 100_000_000)

    XCTAssertEqual(presenter.failures, [.init(message: "Late agent failure")])
  }
}

@MainActor
private final class RecordingServicesFailurePresenter {
  private(set) var failures: [ExternalAutomationFailure] = []

  func present(_ failure: ExternalAutomationFailure) {
    failures.append(failure)
  }
}
