import SwiftUI
import WidgetKit

@main
struct KeyboardLockerWidgetsBundle: WidgetBundle {
  var body: some Widget {
    KeyboardLockerStatusWidget()

    if #available(macOS 26.0, *) {
      KeyboardLockerControl()
    }
  }
}
