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

  func testMissingCapabilityExplainsAgentUpdateRecovery() throws {
    let suggestion = try XCTUnwrap(
      XPCClientError.missingCapability(.interactiveLock).recoverySuggestion
    )

    XCTAssertTrue(suggestion.contains("update its background agent"))
  }

  func testUnknownMutationOutcomeExplainsStateRecovery() throws {
    let suggestion = try XCTUnwrap(
      XPCClientError.operationOutcomeUnknown.recoverySuggestion
    )

    XCTAssertTrue(suggestion.contains("Inspect the current state"))
    XCTAssertTrue(suggestion.contains("repeat the intended lock or unlock action"))
  }
}
