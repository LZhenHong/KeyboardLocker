//
//  ContentView.swift
//  KeyboardLocker
//
//  Created by Eden on 2025/11/19.
//

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
  }
}

#Preview {
  ContentView()
    .environmentObject(LockController())
}
