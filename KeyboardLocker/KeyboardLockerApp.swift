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
    registerAgentService()
  }

  private func registerAgentService() {
    // Register agent with SMAppService to ensure it's available for XPC communication
    let service = SMAppService.agent(plistName: "io.lzhlovesjyq.keyboardlocker.agent.plist")
    do {
      try service.register()
    } catch {
      print("Failed to register agent: \(error)")
    }
  }

  private func performLockOperation(
    _ operation: (@escaping (Error?) -> Void) -> Void,
    newState: Bool,
    errorContext: String
  ) {
    operation { error in
      if let error {
        print("Error \(errorContext): \(error)")
      } else {
        DispatchQueue.main.async {
          isLocked = newState
        }
      }
    }
  }

  func toggleLock() {
    if isLocked {
      performLockOperation(XPCClient.shared.unlock, newState: false, errorContext: "unlocking")
    } else {
      performLockOperation(XPCClient.shared.lock, newState: true, errorContext: "locking")
    }
  }
}
