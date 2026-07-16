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
      statusContent
      Spacer()
      footer
    }
    .padding()
  }

  private var header: some View {
    HStack {
      Image(systemName: lock.systemImageName)
        .font(.title)
        .foregroundStyle(statusColor)
      Text("KeyboardLocker")
        .font(.headline)
      Spacer()
    }
  }

  private var statusColor: Color {
    switch lock.state {
    case .ready(isLocked: true),
         .accessibilityRequired(isLocked: true),
         .agentUpdateRequired(isLocked: true, message: _):
      .accentColor
    case .agentApprovalRequired,
         .agentReplacementInProgress,
         .agentUpdateRequired(isLocked: false, message: _),
         .agentUpdateRequired(isLocked: nil, message: _),
         .accessibilityRequired(isLocked: false),
         .unavailable:
      .orange
    case .checking(lastKnownLock: true):
      .accentColor
    case .checking, .ready(isLocked: false):
      .secondary
    }
  }

  @ViewBuilder
  private var statusContent: some View {
    switch lock.state {
    case let .checking(lastKnownLock):
      checkingView(lastKnownLock: lastKnownLock)
    case .agentApprovalRequired:
      agentApprovalView
    case let .agentReplacementInProgress(message):
      agentReplacementInProgressView(message: message)
    case let .agentUpdateRequired(isLocked, message):
      agentUpdateView(isLocked: isLocked, message: message)
    case let .accessibilityRequired(isLocked):
      accessibilityView(isLocked: isLocked)
    case let .ready(isLocked):
      readyView(isLocked: isLocked)
    case let .unavailable(message, canRestartAgent):
      unavailableView(message: message, canRestartAgent: canRestartAgent)
    }
  }

  private func checkingView(lastKnownLock: Bool?) -> some View {
    VStack(spacing: 8) {
      if lastKnownLock == true {
        Button {
          lock.toggle()
        } label: {
          HStack(spacing: 6) {
            if lock.activity == .unlocking {
              ProgressView()
                .controlSize(.small)
            }
            Text(lock.activity == .unlocking ? "Unlocking…" : "Unlock")
          }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(lock.activity != nil)
      }

      if lock.activity != .unlocking {
        ProgressView()
          .controlSize(.small)
        Text(
          lock.activity == .updatingAgent
            ? "Updating background agent…"
            : "Verifying KeyboardLocker status…"
        )
        .font(.subheadline)
        .foregroundStyle(.secondary)
      }
    }
  }

  private func agentReplacementInProgressView(message: String) -> some View {
    VStack(spacing: 8) {
      ProgressView()
        .controlSize(.small)
      Text("Agent Replacement in Progress")
        .font(.headline)
      Text(message)
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)

      Button("Check Again") {
        lock.reconcile()
      }
      .buttonStyle(.borderedProminent)
      .disabled(lock.activity != nil)
    }
  }

  private func agentUpdateView(isLocked: Bool?, message: String) -> some View {
    VStack(spacing: 8) {
      Text("Agent Update Required")
        .font(.headline)
      Text(message)
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)

      Text(agentUpdateWarning(isLocked: isLocked))
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)

      if isLocked == true {
        Button {
          lock.toggle()
        } label: {
          HStack(spacing: 6) {
            if lock.activity == .unlocking {
              ProgressView()
                .controlSize(.small)
            }
            Text(lock.activity == .unlocking ? "Unlocking…" : "Unlock")
          }
        }
        .buttonStyle(.bordered)
        .disabled(lock.activity != nil)
      }

      Button {
        lock.updateAgent()
      } label: {
        HStack(spacing: 6) {
          if lock.activity == .updatingAgent {
            ProgressView()
              .controlSize(.small)
          }
          Text(agentUpdateTitle(isLocked: isLocked))
        }
      }
      .buttonStyle(.borderedProminent)
      .disabled(lock.activity != nil)

      Button("Check Again") {
        lock.reconcile()
      }
      .buttonStyle(.borderless)
      .disabled(lock.activity != nil)

      actionError
    }
  }

  private var agentApprovalView: some View {
    VStack(spacing: 8) {
      Text("Background Agent Disabled")
        .font(.headline)
      Text("Enable KeyboardLocker in System Settings → General → Login Items.")
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)

      Button("Open Login Items") {
        lock.openAgentApprovalSettings()
      }
      .buttonStyle(.borderedProminent)

      Button("Check Again") {
        lock.reconcile()
      }
      .buttonStyle(.borderless)
    }
  }

  private func accessibilityView(isLocked: Bool) -> some View {
    VStack(spacing: 8) {
      if isLocked {
        Button {
          lock.toggle()
        } label: {
          HStack(spacing: 6) {
            if lock.activity == .unlocking {
              ProgressView()
                .controlSize(.small)
            }
            Text(lock.activity == .unlocking ? "Unlocking…" : "Unlock")
          }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(lock.activity != nil)

        Text("Keyboard is locked")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }

      Text("Accessibility Access Required")
        .font(.headline)
      Text("Allow KeyboardLockerAgent to filter keyboard events. After granting access, check again.")
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)

      Button {
        lock.requestAccessibilityPermission()
      } label: {
        HStack(spacing: 6) {
          if lock.activity == .requestingAccessibility {
            ProgressView()
              .controlSize(.small)
          }
          Text("Request Access")
        }
      }
      .buttonStyle(.bordered)
      .disabled(lock.activity != nil)

      HStack(spacing: 12) {
        Button("Open Settings") {
          lock.openAccessibilitySettings()
        }
        .buttonStyle(.borderless)

        Button("Check Again") {
          lock.reconcile()
        }
        .buttonStyle(.borderless)
        .disabled(lock.activity != nil)
      }

      actionError
    }
  }

  private func readyView(isLocked: Bool) -> some View {
    VStack(spacing: 8) {
      Button {
        lock.toggle()
      } label: {
        HStack(spacing: 6) {
          if lock.activity == .locking || lock.activity == .unlocking {
            ProgressView()
              .controlSize(.small)
          }
          Text(toggleTitle(isLocked: isLocked))
        }
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
      .disabled(lock.activity != nil)

      Text(isLocked ? "Keyboard is locked" : "Keyboard is unlocked")
        .font(.subheadline)
        .foregroundStyle(.secondary)

      actionError
    }
  }

  private func toggleTitle(isLocked: Bool) -> String {
    switch lock.activity {
    case .locking:
      "Locking…"
    case .unlocking:
      "Unlocking…"
    case .requestingAccessibility, .restartingAgent, .updatingAgent, nil:
      isLocked ? "Unlock" : "Lock Keyboard"
    }
  }

  private func agentUpdateTitle(isLocked: Bool?) -> String {
    if lock.activity == .updatingAgent {
      return "Updating Agent…"
    }
    return isLocked == true ? "Unlock and Replace Agent" : "Replace Agent"
  }

  private func agentUpdateWarning(isLocked: Bool?) -> String {
    if lock.agentUpdateUsesSafeReplacement {
      return isLocked == true
        ? "The Agent will block new lock requests, unlock, and remain drained until replacement completes."
        : "The Agent will block new lock requests until replacement completes."
    }
    if isLocked == nil {
      return "The running Agent's lock state cannot be verified. Replacing it may release an active keyboard lock."
    }
    return """
    This Agent cannot block other clients during replacement. A lock created in that brief \
    window may be released.
    """
  }

  private func unavailableView(message: String, canRestartAgent: Bool) -> some View {
    VStack(spacing: 8) {
      Text("KeyboardLocker Is Unavailable")
        .font(.headline)
      Text(message)
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)

      Button("Retry") {
        lock.reconcile()
      }
      .buttonStyle(.borderedProminent)
      .disabled(lock.activity != nil)

      if canRestartAgent {
        Text("Restarting the agent releases any active keyboard lock.")
          .font(.caption)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)

        Button {
          lock.restartAgent()
        } label: {
          HStack(spacing: 6) {
            if lock.activity == .restartingAgent {
              ProgressView()
                .controlSize(.small)
            }
            Text(lock.activity == .restartingAgent ? "Restarting Agent…" : "Restart Agent")
          }
        }
        .buttonStyle(.bordered)
        .disabled(lock.activity != nil)
      }
    }
  }

  @ViewBuilder
  private var actionError: some View {
    if let error = lock.lastError {
      Text(error)
        .font(.caption)
        .foregroundStyle(.red)
        .multilineTextAlignment(.center)
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
      .environmentObject(LockController(previewState: .accessibilityRequired(isLocked: false)))
  }
  .frame(width: 280, height: 320)
}
