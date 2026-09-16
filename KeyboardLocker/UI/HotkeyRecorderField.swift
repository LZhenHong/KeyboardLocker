import AppKit
import Client
import SwiftUI

/// A focusable field that records the next modifier+key combination.
///
/// Uses an `NSView` because SwiftUI has no first-class key-capture primitive on macOS 13: the field
/// must see raw `keyDown` before the app turns it into a menu shortcut or an insertion.
struct HotkeyRecorderField: NSViewRepresentable {
  let hotkey: KeyboardLockerSettings.Hotkey?
  let isEnabled: Bool
  let onCapture: (HotkeyCapture.Outcome) -> Void

  func makeNSView(context _: Context) -> HotkeyRecorderView {
    let view = HotkeyRecorderView()
    view.onCapture = onCapture
    return view
  }

  func updateNSView(_ view: HotkeyRecorderView, context _: Context) {
    view.onCapture = onCapture
    view.isEnabled = isEnabled
    view.displayedHotkey = hotkey
  }
}

/// Records one hotkey at a time and reports the outcome without deciding whether it is valid.
final class HotkeyRecorderView: NSView {
  var onCapture: ((HotkeyCapture.Outcome) -> Void)?
  var displayedHotkey: KeyboardLockerSettings.Hotkey? {
    didSet {
      guard displayedHotkey != oldValue else {
        return
      }
      refreshTitle()
    }
  }

  var isEnabled = true {
    didSet {
      guard isEnabled != oldValue else {
        return
      }
      if !isEnabled, isRecording {
        endRecording()
      }
      refreshTitle()
    }
  }

  private let label = NSTextField(labelWithString: "")
  private var isRecording = false

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.cornerRadius = 6
    layer?.borderWidth = 1

    label.alignment = .center
    label.font = .systemFont(ofSize: NSFont.systemFontSize)
    label.translatesAutoresizingMaskIntoConstraints = false
    addSubview(label)
    NSLayoutConstraint.activate([
      label.centerXAnchor.constraint(equalTo: centerXAnchor),
      label.centerYAnchor.constraint(equalTo: centerYAnchor),
      label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 8),
      label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
      heightAnchor.constraint(equalToConstant: 24),
      widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
    ])
    refreshAppearance()
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  override var acceptsFirstResponder: Bool {
    isEnabled
  }

  override func mouseDown(with _: NSEvent) {
    guard isEnabled else {
      return
    }
    if isRecording {
      endRecording()
    } else {
      window?.makeFirstResponder(self)
      beginRecording()
    }
  }

  override func becomeFirstResponder() -> Bool {
    let accepted = super.becomeFirstResponder()
    if accepted {
      refreshAppearance()
    }
    return accepted
  }

  override func resignFirstResponder() -> Bool {
    if isRecording {
      endRecording()
    }
    refreshAppearance()
    return super.resignFirstResponder()
  }

  override func keyDown(with event: NSEvent) {
    guard isRecording else {
      super.keyDown(with: event)
      return
    }

    // Escape and Return leave the recorder rather than being recorded, so the keyboard alone is
    // always enough to get out of it.
    if HotkeyCapture.isRecordingTerminator(keyCode: event.keyCode) {
      endRecording()
      return
    }

    onCapture?(
      HotkeyCapture.outcome(
        keyCode: event.keyCode,
        modifierFlags: event.modifierFlags
      )
    )
    endRecording()
  }

  /// Swallows system shortcuts while recording so combinations like ⌘Q reach `keyDown` instead of
  /// activating a menu item.
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    guard isRecording else {
      return super.performKeyEquivalent(with: event)
    }
    keyDown(with: event)
    return true
  }

  override func drawFocusRingMask() {
    bounds.insetBy(dx: 1, dy: 1).fill()
  }

  override var focusRingMaskBounds: NSRect {
    bounds
  }

  private func beginRecording() {
    isRecording = true
    refreshAppearance()
  }

  private func endRecording() {
    isRecording = false
    refreshAppearance()
  }

  private func refreshAppearance() {
    refreshTitle()
    layer?.borderColor = (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
    layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
    needsDisplay = true
  }

  private func refreshTitle() {
    if isRecording {
      label.stringValue = "Press a shortcut…"
      label.textColor = .secondaryLabelColor
      return
    }

    label.textColor = isEnabled ? .labelColor : .disabledControlTextColor
    guard let displayedHotkey else {
      label.stringValue = "Not set"
      return
    }
    label.stringValue = displayedHotkey.displayString
  }
}
