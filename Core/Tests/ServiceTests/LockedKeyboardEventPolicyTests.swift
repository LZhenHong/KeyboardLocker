import AppKit
import CoreGraphics
import IOKit
@testable import Service
import Testing

@Suite(.serialized)
struct LockedKeyboardEventPolicyTests {
  @Test
  func suppressesStandardKeyboardEvents() {
    for type in [CGEventType.keyDown, .keyUp, .flagsChanged] {
      #expect(LockedKeyboardEventPolicy.shouldSuppress(type: type))
    }
  }

  @Test
  func suppressesKeyboardSystemControls() {
    let subtypes = [
      NX_SUBTYPE_AUX_CONTROL_BUTTONS,
      NX_SUBTYPE_EJECT_KEY,
      NX_SUBTYPE_POWER_KEY,
    ]

    for subtype in subtypes {
      #expect(
        LockedKeyboardEventPolicy.shouldSuppress(
          type: LockedKeyboardEventPolicy.systemDefinedEventType,
          systemDefinedSubtype: Int16(subtype)
        )
      )
    }
  }

  @Test
  @MainActor
  func readsSystemDefinedSubtypeFromEventPayload() throws {
    let keyboardControl = try makeSystemDefinedEvent(
      subtype: NX_SUBTYPE_AUX_CONTROL_BUTTONS
    )
    let auxiliaryMouseButton = try makeSystemDefinedEvent(
      subtype: NX_SUBTYPE_AUX_MOUSE_BUTTONS
    )

    #expect(
      keyboardControl.type == LockedKeyboardEventPolicy.systemDefinedEventType
    )
    #expect(
      LockedKeyboardEventPolicy.shouldSuppress(
        type: keyboardControl.type,
        event: keyboardControl
      )
    )
    #expect(
      !LockedKeyboardEventPolicy.shouldSuppress(
        type: auxiliaryMouseButton.type,
        event: auxiliaryMouseButton
      )
    )
  }

  @Test
  func preservesPointerAndUnclassifiedSystemEvents() {
    #expect(
      !LockedKeyboardEventPolicy.shouldSuppress(
        type: LockedKeyboardEventPolicy.systemDefinedEventType,
        systemDefinedSubtype: Int16(NX_SUBTYPE_AUX_MOUSE_BUTTONS)
      )
    )
    #expect(
      !LockedKeyboardEventPolicy.shouldSuppress(
        type: LockedKeyboardEventPolicy.systemDefinedEventType,
        systemDefinedSubtype: Int16(NX_SUBTYPE_SLEEP_EVENT)
      )
    )
    #expect(
      !LockedKeyboardEventPolicy.shouldSuppress(
        type: LockedKeyboardEventPolicy.systemDefinedEventType,
        systemDefinedSubtype: nil
      )
    )
    #expect(
      !LockedKeyboardEventPolicy.shouldSuppress(
        type: LockedKeyboardEventPolicy.systemDefinedEventType,
        systemDefinedSubtype: .max
      )
    )
  }

  @Test
  func preservesPointerEventTypes() {
    for type in [
      CGEventType.leftMouseDown,
      .otherMouseDown,
      .rightMouseDown,
      .scrollWheel,
    ] {
      #expect(!LockedKeyboardEventPolicy.shouldSuppress(type: type))
    }
  }

  @Test
  @MainActor
  func eventTapObservesEverySuppressibleEventClassWithoutObservingPointers() {
    for type in [
      CGEventType.keyDown,
      .keyUp,
      .flagsChanged,
      LockedKeyboardEventPolicy.systemDefinedEventType,
    ] {
      #expect(eventMaskContains(type))
    }

    for type in [
      CGEventType.leftMouseDown,
      .otherMouseDown,
      .rightMouseDown,
      .scrollWheel,
    ] {
      #expect(!eventMaskContains(type))
    }
  }

  @MainActor
  private func eventMaskContains(_ type: CGEventType) -> Bool {
    LockEngine.eventMasks & (CGEventMask(1) << type.rawValue) != 0
  }

  @MainActor
  private func makeSystemDefinedEvent(subtype: Int32) throws -> CGEvent {
    let event = try #require(
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
    return try #require(event.cgEvent)
  }
}
