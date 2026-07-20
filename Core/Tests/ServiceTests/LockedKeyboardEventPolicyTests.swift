import AppKit
import CoreGraphics
import IOKit
@testable import Service
import XCTest

final class LockedKeyboardEventPolicyTests: XCTestCase {
  func testSuppressesStandardKeyboardEvents() {
    for type in [CGEventType.keyDown, .keyUp, .flagsChanged] {
      XCTAssertTrue(LockedKeyboardEventPolicy.shouldSuppress(type: type))
    }
  }

  func testSuppressesKeyboardSystemControls() {
    let subtypes = [
      NX_SUBTYPE_AUX_CONTROL_BUTTONS,
      NX_SUBTYPE_EJECT_KEY,
      NX_SUBTYPE_POWER_KEY,
    ]

    for subtype in subtypes {
      XCTAssertTrue(
        LockedKeyboardEventPolicy.shouldSuppress(
          type: LockedKeyboardEventPolicy.systemDefinedEventType,
          systemDefinedSubtype: Int16(subtype)
        )
      )
    }
  }

  @MainActor
  func testReadsSystemDefinedSubtypeFromEventPayload() throws {
    let keyboardControl = try makeSystemDefinedEvent(
      subtype: NX_SUBTYPE_AUX_CONTROL_BUTTONS
    )
    let auxiliaryMouseButton = try makeSystemDefinedEvent(
      subtype: NX_SUBTYPE_AUX_MOUSE_BUTTONS
    )

    XCTAssertEqual(
      keyboardControl.type,
      LockedKeyboardEventPolicy.systemDefinedEventType
    )
    XCTAssertTrue(
      LockedKeyboardEventPolicy.shouldSuppress(
        type: keyboardControl.type,
        event: keyboardControl
      )
    )
    XCTAssertFalse(
      LockedKeyboardEventPolicy.shouldSuppress(
        type: auxiliaryMouseButton.type,
        event: auxiliaryMouseButton
      )
    )
  }

  func testPreservesPointerAndUnclassifiedSystemEvents() {
    XCTAssertFalse(
      LockedKeyboardEventPolicy.shouldSuppress(
        type: LockedKeyboardEventPolicy.systemDefinedEventType,
        systemDefinedSubtype: Int16(NX_SUBTYPE_AUX_MOUSE_BUTTONS)
      )
    )
    XCTAssertFalse(
      LockedKeyboardEventPolicy.shouldSuppress(
        type: LockedKeyboardEventPolicy.systemDefinedEventType,
        systemDefinedSubtype: Int16(NX_SUBTYPE_SLEEP_EVENT)
      )
    )
    XCTAssertFalse(
      LockedKeyboardEventPolicy.shouldSuppress(
        type: LockedKeyboardEventPolicy.systemDefinedEventType,
        systemDefinedSubtype: nil
      )
    )
    XCTAssertFalse(
      LockedKeyboardEventPolicy.shouldSuppress(
        type: LockedKeyboardEventPolicy.systemDefinedEventType,
        systemDefinedSubtype: .max
      )
    )
  }

  func testPreservesPointerEventTypes() {
    for type in [
      CGEventType.leftMouseDown,
      .otherMouseDown,
      .rightMouseDown,
      .scrollWheel,
    ] {
      XCTAssertFalse(LockedKeyboardEventPolicy.shouldSuppress(type: type))
    }
  }

  @MainActor
  func testEventTapObservesEverySuppressibleEventClassWithoutObservingPointers() {
    for type in [
      CGEventType.keyDown,
      .keyUp,
      .flagsChanged,
      LockedKeyboardEventPolicy.systemDefinedEventType,
    ] {
      XCTAssertTrue(eventMaskContains(type))
    }

    for type in [
      CGEventType.leftMouseDown,
      .otherMouseDown,
      .rightMouseDown,
      .scrollWheel,
    ] {
      XCTAssertFalse(eventMaskContains(type))
    }
  }

  @MainActor
  private func eventMaskContains(_ type: CGEventType) -> Bool {
    LockEngine.eventMasks & (CGEventMask(1) << type.rawValue) != 0
  }

  @MainActor
  private func makeSystemDefinedEvent(subtype: Int32) throws -> CGEvent {
    let event = try XCTUnwrap(
      NSEvent.otherEvent(
        with: .systemDefined,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        subtype: Int16(subtype),
        data1: 0,
        data2: 0
      )
    )
    return try XCTUnwrap(event.cgEvent)
  }
}
