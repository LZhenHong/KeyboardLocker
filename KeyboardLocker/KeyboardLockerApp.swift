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

  init() {
    // Ensure the Agent is launchd-registered so it runs on demand for every surface.
    AgentRegistrar.registerIfNeeded()
  }

  var body: some Scene {
    MenuBarExtra("KeyboardLocker", systemImage: lockController.isLocked ? "lock.fill" : "lock.open.fill") {
      ContentView()
        .environmentObject(lockController)
    }
    .menuBarExtraStyle(.window)
  }
}
