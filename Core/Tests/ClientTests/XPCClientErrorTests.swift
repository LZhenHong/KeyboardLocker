import Foundation
import XCTest
@testable import Client

final class XPCClientErrorTests: XCTestCase {
  func testProxyErrorsNormalizeToServiceUnavailable() {
    let transportError = NSError(
      domain: NSCocoaErrorDomain,
      code: CocoaError.xpcConnectionInvalid.rawValue
    )

    guard case XPCClientError.serviceUnavailable = XPCClient.normalizedProxyError(transportError)
    else {
      return XCTFail("Expected the proxy error to normalize to serviceUnavailable.")
    }
  }

  func testServiceUnavailableExplainsFirstUseRecovery() throws {
    let suggestion = try XCTUnwrap(XPCClientError.serviceUnavailable.recoverySuggestion)

    XCTAssertTrue(suggestion.contains("Open KeyboardLocker once"))
    XCTAssertTrue(suggestion.contains("Show Details"))
  }
}
