//
//  MainView.swift
//  KeyboardLocker
//
//  Created by Eden on 2025/12/16.
//

import SwiftUI

struct MainView: View {
  @EnvironmentObject private var lock: LockController

  var body: some View {
    VStack(spacing: 16) {
      header
      Divider()
      lockControl
      Spacer()
      footer
    }
    .padding()
  }

  private var header: some View {
    HStack {
      Image(systemName: lock.isLocked ? "lock.fill" : "lock.open.fill")
        .font(.title)
        .foregroundStyle(lock.isLocked ? Color.accentColor : .secondary)
      Text("KeyboardLocker")
        .font(.headline)
      Spacer()
    }
  }

  private var lockControl: some View {
    VStack(spacing: 8) {
      Button(lock.isLocked ? "Unlock" : "Lock Keyboard") {
        lock.toggle()
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)

      Text(lock.isLocked ? "Keyboard is locked" : "Keyboard is unlocked")
        .font(.subheadline)
        .foregroundStyle(.secondary)

      if let error = lock.lastError {
        Text(error)
          .font(.caption)
          .foregroundStyle(.red)
          .multilineTextAlignment(.center)
      }
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
      .environmentObject(LockController())
  }
  .frame(width: 280, height: 320)
}
