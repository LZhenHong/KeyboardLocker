import AppKit
import Testing

@MainActor
@Suite(.serialized)
struct KeyboardLockerServicesProviderTests {
  private let pasteboard = NSPasteboard(name: NSPasteboard.Name("KeyboardLockerServicesProviderTests"))

  @Test
  func providerExportsEveryDeclaredServiceSelector() {
    let provider = KeyboardLockerServicesProvider { _ in nil }

    #expect(provider.responds(to: NSSelectorFromString("lockKeyboard:userData:error:")))
    #expect(provider.responds(to: NSSelectorFromString("unlockKeyboard:userData:error:")))
    #expect(
      provider.responds(to: NSSelectorFromString("showKeyboardLockStatus:userData:error:"))
    )
  }

  @Test
  func handlerLeavesErrorUntouchedWhenActionSucceeds() {
    let provider = KeyboardLockerServicesProvider { _ in nil }

    var error: NSString?
    provider.lockKeyboard(pasteboard, userData: nil, error: &error)

    #expect(error == nil)
  }

  @Test
  func handlerPublishesFailureBeforeScheduledPresentationRuns() async {
    let presenter = RecordingServicesFailurePresenter()
    let provider = KeyboardLockerServicesProvider(
      presentFailure: { presenter.present($0) }
    ) { _ in
      ExternalAutomationFailure(message: "Agent not reachable")
    }

    var error: NSString?
    provider.unlockKeyboard(pasteboard, userData: nil, error: &error)

    #expect(error == "Agent not reachable")
    #expect(presenter.failures.isEmpty)

    await Task.yield()

    #expect(presenter.failures == [.init(message: "Agent not reachable")])
  }

  @Test
  func handlerReportsTimeoutWhenActionDoesNotFinish() {
    let provider = KeyboardLockerServicesProvider(waitTimeout: 0.1) { _ in
      try? await Task.sleep(nanoseconds: 10_000_000_000)
      return nil
    }

    var error: NSString?
    provider.showKeyboardLockStatus(pasteboard, userData: nil, error: &error)

    #expect(error?.contains("did not finish") == true)
  }

  @Test
  func timedOutHandlerPresentsLateFailureAfterPublishingTimeout() async {
    let presenter = RecordingServicesFailurePresenter()
    let provider = KeyboardLockerServicesProvider(
      waitTimeout: 0.01,
      presentFailure: { presenter.present($0) }
    ) { _ in
      try? await Task.sleep(nanoseconds: 50_000_000)
      return ExternalAutomationFailure(message: "Late agent failure")
    }

    var error: NSString?
    provider.lockKeyboard(pasteboard, userData: nil, error: &error)

    #expect(error?.contains("did not finish") == true)
    #expect(presenter.failures.isEmpty)

    // The late presentation crosses executor hops after the action completes; poll with a
    // generous deadline instead of assuming a fixed wall-clock margin on a loaded runner.
    let deadline = ContinuousClock.now + .seconds(5)
    while presenter.failures.isEmpty, ContinuousClock.now < deadline {
      try? await Task.sleep(nanoseconds: 10_000_000)
    }

    #expect(presenter.failures == [.init(message: "Late agent failure")])
  }
}

@MainActor
private final class RecordingServicesFailurePresenter {
  private(set) var failures: [ExternalAutomationFailure] = []

  func present(_ failure: ExternalAutomationFailure) {
    failures.append(failure)
  }
}
