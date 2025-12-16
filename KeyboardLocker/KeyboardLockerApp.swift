//
//  KeyboardLockerApp.swift
//  KeyboardLocker
//
//  Created by Eden on 2025/11/19.
//

import SwiftUI

@main
struct KeyboardLockerApp: App {
  var body: some Scene {
    MenuBarExtra("KeyboardLocker", systemImage: "lock.open.fill") {
      Text("KeyboardLocker")
      Divider()
      Button("Quit") {
        NSApplication.shared.terminate(nil)
      }
    }
  }
}
