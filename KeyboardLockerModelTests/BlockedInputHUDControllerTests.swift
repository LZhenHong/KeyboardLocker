import Foundation
import Testing

@MainActor
@Suite(.serialized)
final class BlockedInputHUDControllerTests {
  @Test
  func lockedSnapshotPresentsHint() {
    var presented: [BlockedInputHUDController.Hint] = []
    let hint = BlockedInputHUDController.Hint(hotkeyDisplay: "⌃⌘L", hasUnlockPhrase: true)
    let controller = BlockedInputHUDController(
      hintProvider: { hint },
      present: { presented.append($0) },
      now: { Date(timeIntervalSinceReferenceDate: 1000) }
    )

    controller.handleSignal()

    #expect(presented == [hint])
  }

  @Test
  func unlockedSnapshotPresentsNothing() {
    var presented: [BlockedInputHUDController.Hint] = []
    // A nudge that lands after the lock already ended must not flash.
    let controller = BlockedInputHUDController(
      hintProvider: { nil },
      present: { presented.append($0) },
      now: { Date(timeIntervalSinceReferenceDate: 1000) }
    )

    controller.handleSignal()

    #expect(presented.isEmpty)
  }

  @Test
  func signalsWithinCoalescingWindowAreDropped() {
    var presented: [BlockedInputHUDController.Hint] = []
    var now = Date(timeIntervalSinceReferenceDate: 1000)
    let hint = BlockedInputHUDController.Hint(hotkeyDisplay: "⌃⌘L", hasUnlockPhrase: false)
    let controller = BlockedInputHUDController(
      hintProvider: { hint },
      present: { presented.append($0) },
      now: { now }
    )

    controller.handleSignal()
    controller.handleSignal()
    #expect(presented.count == 1)

    now = now.addingTimeInterval(2)
    controller.handleSignal()
    #expect(presented.count == 2)
  }

  @Test
  func droppedSignalDoesNotLatchTheCoalescingWindow() {
    var presented: [BlockedInputHUDController.Hint] = []
    let now = Date(timeIntervalSinceReferenceDate: 1000)
    var hint: BlockedInputHUDController.Hint?
    let controller = BlockedInputHUDController(
      hintProvider: { hint },
      present: { presented.append($0) },
      now: { now }
    )

    controller.handleSignal()
    #expect(presented.isEmpty)

    // The unlocked signal left no timestamp behind, so a locked signal arriving inside the
    // window still presents immediately.
    hint = BlockedInputHUDController.Hint(hotkeyDisplay: "⌃⌘L", hasUnlockPhrase: false)
    controller.handleSignal()
    #expect(presented.count == 1)
  }
}
