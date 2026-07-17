import AppKit
import XCTest

final class KeyboardLockerServicesProviderTests: XCTestCase {
  func testProviderExportsEveryDeclaredServiceSelector() {
    let provider = KeyboardLockerServicesProvider { _ in }

    XCTAssertTrue(provider.responds(to: NSSelectorFromString("lockKeyboard:userData:error:")))
    XCTAssertTrue(provider.responds(to: NSSelectorFromString("unlockKeyboard:userData:error:")))
    XCTAssertTrue(
      provider.responds(to: NSSelectorFromString("showKeyboardLockStatus:userData:error:"))
    )
  }
}
