//
//  SettingsView.swift
//  KeyboardLocker
//
//  Created by Eden on 2025/12/16.
//

import SwiftUI

struct SettingsView: View {
  var body: some View {
    VStack(spacing: 16) {
      Text("Settings")
        .font(.headline)

      Spacer()

      Text("Settings content will be implemented here.")
        .foregroundStyle(.secondary)

      Spacer()
    }
    .padding()
    .navigationTitle("Settings")
  }
}

#Preview {
  NavigationStack {
    SettingsView()
  }
  .frame(width: 280, height: 320)
}
