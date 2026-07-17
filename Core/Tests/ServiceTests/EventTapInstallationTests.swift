@testable import Service
import XCTest

final class EventTapInstallationTests: XCTestCase {
  func testMissingTapHasNoResourcesToRollBack() {
    var actions: [String] = []

    XCTAssertThrowsError(
      try makeInstallation(
        actions: &actions,
        tap: nil,
        source: 2,
        isEnabled: true
      )
    ) { error in
      XCTAssertEqual(
        error as? EventTapInstallationError,
        .eventTapCreationFailed
      )
    }
    XCTAssertEqual(actions, ["createTap"])
  }

  func testMissingSourceInvalidatesCreatedTap() {
    var actions: [String] = []

    XCTAssertThrowsError(
      try makeInstallation(
        actions: &actions,
        tap: 1,
        source: nil,
        isEnabled: true
      )
    ) { error in
      XCTAssertEqual(
        error as? EventTapInstallationError,
        .runLoopSourceCreationFailed
      )
    }
    XCTAssertEqual(actions, ["createTap", "createSource", "invalidateTap"])
  }

  func testDisabledTapDetachesSourceBeforeInvalidatingTap() {
    var actions: [String] = []

    XCTAssertThrowsError(
      try makeInstallation(
        actions: &actions,
        tap: 1,
        source: 2,
        isEnabled: false
      )
    ) { error in
      XCTAssertEqual(
        error as? EventTapInstallationError,
        .eventTapEnableFailed
      )
    }
    XCTAssertEqual(
      actions,
      [
        "createTap",
        "createSource",
        "attachSource",
        "enableTap",
        "isTapEnabled",
        "detachSource",
        "invalidateTap",
      ]
    )
  }

  func testSuccessfulInstallationTransfersResourceOwnership() throws {
    var actions: [String] = []

    let installation = try makeInstallation(
      actions: &actions,
      tap: 1,
      source: 2,
      isEnabled: true
    )

    XCTAssertEqual(installation.tap, 1)
    XCTAssertEqual(installation.source, 2)
    XCTAssertEqual(
      actions,
      [
        "createTap",
        "createSource",
        "attachSource",
        "enableTap",
        "isTapEnabled",
      ]
    )
  }

  private func makeInstallation(
    actions: inout [String],
    tap: Int?,
    source: Int?,
    isEnabled: Bool
  ) throws -> EventTapInstallation<Int, Int> {
    try EventTapInstallation.make(
      createTap: {
        actions.append("createTap")
        return tap
      },
      createSource: { _ in
        actions.append("createSource")
        return source
      },
      attachSource: { _ in
        actions.append("attachSource")
      },
      enableTap: { _ in
        actions.append("enableTap")
      },
      isTapEnabled: { _ in
        actions.append("isTapEnabled")
        return isEnabled
      },
      detachSource: { _ in
        actions.append("detachSource")
      },
      invalidateTap: { _ in
        actions.append("invalidateTap")
      }
    )
  }
}
