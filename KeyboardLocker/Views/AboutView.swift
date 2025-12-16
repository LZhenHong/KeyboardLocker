//
//  AboutView.swift
//  KeyboardLocker
//
//  Created by Eden on 2025/12/16.
//

import SwiftUI

struct AboutView: View {
  var body: some View {
    VStack(spacing: 16) {
      Text("About")
        .font(.headline)

      Spacer()

      Text("About content will be implemented here.")
        .foregroundStyle(.secondary)

      Spacer()
    }
    .padding()
    .navigationTitle("About")
  }
}

#Preview {
  NavigationStack {
    AboutView()
  }
  .frame(width: 280, height: 320)
}
