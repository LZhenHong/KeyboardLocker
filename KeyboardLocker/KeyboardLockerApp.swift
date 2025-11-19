//
//  KeyboardLockerApp.swift
//  KeyboardLocker
//
//  Created by Eden on 2025/11/19.
//

import Core
import ServiceManagement
import SwiftUI

@main
struct KeyboardLockerApp: App {
  @State private var isLocked = false

  var body: some Scene {
    MenuBarExtra("KeyboardLocker", systemImage: isLocked ? "lock.fill" : "lock.open.fill") {
      Button(isLocked ? "Unlock" : "Lock") {
        toggleLock()
      }
      Divider()
      Button("Quit") {
        NSApplication.shared.terminate(nil)
      }
    }
  }

  init() {
    // Register the agent
    // Note: The agent plist must be named exactly as expected and placed in Contents/Library/LaunchAgents
    // For SMAppService, we usually rely on the system to find the helper if it's properly embedded.
    // However, for .agent(plistName:), we need the plist file.
    // A simpler way for modern macOS is .mainApp if it was the main app, but here it's a helper.
    // We will assume the user configures the build to copy the agent and plist.
    let service = SMAppService.agent(plistName: "io.lzhlovesjyq.KeyboardLocker.agent.plist")
    do {
      try service.register()
    } catch {
      print("Failed to register agent: \(error)")
    }
  }

  func toggleLock() {
    if isLocked {
      XPCClient.shared.unlock { error in
        if let error {
          print("Error unlocking: \(error)")
        } else {
          DispatchQueue.main.async {
            isLocked = false
          }
        }
      }
    } else {
      XPCClient.shared.lock { error in
        if let error {
          print("Error locking: \(error)")
        } else {
          DispatchQueue.main.async {
            isLocked = true
          }
        }
      }
    }
  }
}
