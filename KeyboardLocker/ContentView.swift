//
//  ContentView.swift
//  KeyboardLocker
//
//  Created by Eden on 2025/11/19.
//

import AppKit
import Combine
import SwiftUI

struct ContentView: View {
  @EnvironmentObject private var lock: LockController

  var body: some View {
    NavigationStack {
      MainView()
        .navigationDestination(for: AppRoute.self) { route in
          switch route {
          case .settings:
            SettingsView()
          case .about:
            AboutView()
          }
        }
    }
    .frame(width: 280, height: 320)
    .onAppear {
      // The menu window just opened; reconcile in case a broadcast was missed while suspended.
      lock.reconcile()
    }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      // Permission and Login Item changes happen in System Settings while this App is inactive.
      lock.reconcile()
    }
  }
}

#Preview {
  ContentView()
    .environmentObject(LockController(previewState: .ready(isLocked: false)))
}
