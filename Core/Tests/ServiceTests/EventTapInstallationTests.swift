@testable import Service
import Testing

@Suite(.serialized)
struct EventTapInstallationTests {
  @Test
  func missingTapHasNoResourcesToRollBack() {
    var actions: [String] = []

    #expect(throws: EventTapInstallationError.eventTapCreationFailed) {
      try makeInstallation(
        actions: &actions,
        tap: nil,
        source: 2,
        isEnabled: true
      )
    }
    #expect(actions == ["createTap"])
  }

  @Test
  func missingSourceInvalidatesCreatedTap() {
    var actions: [String] = []

    #expect(throws: EventTapInstallationError.runLoopSourceCreationFailed) {
      try makeInstallation(
        actions: &actions,
        tap: 1,
        source: nil,
        isEnabled: true
      )
    }
    #expect(actions == ["createTap", "createSource", "invalidateTap"])
  }

  @Test
  func disabledTapDetachesSourceBeforeInvalidatingTap() {
    var actions: [String] = []

    #expect(throws: EventTapInstallationError.eventTapEnableFailed) {
      try makeInstallation(
        actions: &actions,
        tap: 1,
        source: 2,
        isEnabled: false
      )
    }
    #expect(
      actions == [
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

  @Test
  func successfulInstallationTransfersResourceOwnership() throws {
    var actions: [String] = []

    let installation = try makeInstallation(
      actions: &actions,
      tap: 1,
      source: 2,
      isEnabled: true
    )

    #expect(installation.tap == 1)
    #expect(installation.source == 2)
    #expect(
      actions == [
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
