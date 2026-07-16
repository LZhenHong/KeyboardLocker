//
//  KeyboardLockerApp.swift
//  KeyboardLocker
//
//  Created by Eden on 2025/11/19.
//

import SwiftUI

@main
struct KeyboardLockerApp: App {
  @StateObject private var lockController = LockController()

  var body: some Scene {
    MenuBarExtra("KeyboardLocker", systemImage: lockController.systemImageName) {
      ContentView()
        .environmentObject(lockController)
    }
    .menuBarExtraStyle(.window)
  }
}
