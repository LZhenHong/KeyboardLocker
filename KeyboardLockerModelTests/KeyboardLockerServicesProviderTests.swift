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

  func testHandlerCopiesFailureMessageIntoErrorOutPointer() {
    let provider = KeyboardLockerServicesProvider { _ in
      ExternalAutomationFailure(message: "Agent not reachable")
    }

    var error: NSString?
    provider.unlockKeyboard(pasteboard, userData: nil, error: &error)

    XCTAssertEqual(error, "Agent not reachable")
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
}
