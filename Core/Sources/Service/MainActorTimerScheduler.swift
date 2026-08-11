import Foundation

/// Schedules a one-shot main-actor action after an interval and returns a cancellation closure.
///
/// Shared by `LockEngine` (auto-unlock) and `AgentService` (replacement-preparation expiry) so
/// `ServiceTests` can substitute a deterministic manual scheduler for either consumer.
typealias MainActorTimerScheduler = (
  _ interval: TimeInterval,
  _ fire: @escaping @MainActor () -> Void
) -> () -> Void

/// Live scheduler backed by the main dispatch queue. The deadline uses the monotonic clock,
/// so it pauses while the system is asleep.
let liveMainActorTimerScheduler: MainActorTimerScheduler = { interval, fire in
  let item = DispatchWorkItem {
    MainActor.assumeIsolated { fire() }
  }
  DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: item)
  return { item.cancel() }
}
