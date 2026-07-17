import Foundation
import XCTest

final class KlockStatusOutputTests: XCTestCase {
  func testHumanReadableOutputPreservesExistingContract() {
    XCTAssertEqual(KlockStatusOutput.humanReadable.render(isLocked: true), "Locked")
    XCTAssertEqual(KlockStatusOutput.humanReadable.render(isLocked: false), "Unlocked")
  }

  func testJSONOutputUsesStableBooleanField() throws {
    let locked = KlockStatusOutput.json.render(isLocked: true)
    let unlocked = KlockStatusOutput.json.render(isLocked: false)

    XCTAssertEqual(locked, #"{"locked":true}"#)
    XCTAssertEqual(unlocked, #"{"locked":false}"#)
    XCTAssertEqual(try decodedLockedValue(from: locked), true)
    XCTAssertEqual(try decodedLockedValue(from: unlocked), false)
  }

  private func decodedLockedValue(from output: String) throws -> Bool? {
    let object = try JSONSerialization.jsonObject(with: Data(output.utf8))
    return (object as? [String: Bool])?["locked"]
  }
}
