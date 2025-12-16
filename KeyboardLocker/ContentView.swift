//
//  ContentView.swift
//  KeyboardLocker
//
//  Created by Eden on 2025/11/19.
//

import SwiftUI

struct ContentView: View {
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
  }
}

#Preview {
  ContentView()
}
