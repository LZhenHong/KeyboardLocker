//
//  MainView.swift
//  KeyboardLocker
//
//  Created by Eden on 2025/12/16.
//

import SwiftUI

struct MainView: View {
  var body: some View {
    VStack(spacing: 16) {
      header
      Divider()
      Spacer()
      footer
    }
    .padding()
  }

  private var header: some View {
    HStack {
      Image(systemName: "lock.open.fill")
        .font(.title)
        .foregroundStyle(.secondary)
      Text("KeyboardLocker")
        .font(.headline)
      Spacer()
    }
  }

  private var footer: some View {
    HStack {
      NavigationLink(value: AppRoute.settings) {
        Label("Settings", systemImage: "gear")
      }
      .buttonStyle(.borderless)

      NavigationLink(value: AppRoute.about) {
        Label("About", systemImage: "info.circle")
      }
      .buttonStyle(.borderless)

      Spacer()

      Button("Quit") {
        NSApplication.shared.terminate(nil)
      }
    }
  }
}

#Preview {
  NavigationStack {
    MainView()
  }
  .frame(width: 280, height: 320)
}
