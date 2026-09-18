# KeyboardLocker FAQ

KeyboardLocker can be driven from many places — the menu bar app, a CLI, Shortcuts, Focus modes, the Services menu, a URL scheme, AppleScript, a desktop widget, and Control Center. This FAQ is organized by what you might want to do.

## Basics

**Q: What exactly gets locked?**

Your keyboard: standard keys, plus the system control keys on the keyboard — volume, brightness, media playback, eject, and power — are consumed before they reach the system. Your mouse and trackpad keep working; that's **by design, not a bug**. *Hardware paths that macOS never delivers to event taps are outside this guarantee.*

**Q: My keyboard is locked. How do I unlock it?**

Pick any of these:

1. Press the unlock hotkey (⌃⌘L by default; change it in Settings).
2. Click Unlock Now in the system notification (the mouse still works).
3. Click the menu bar icon, then Unlock.
4. Run `klock unlock` in Terminal.
5. Wait for auto-unlock (60 seconds by default).

If you set an unlock phrase, typing it while locked also works. The lock is global: **no matter which surface locked the keyboard, any surface can unlock it.**

**Q: Does quitting KeyboardLocker unlock the keyboard?**

No. The lock is held by a background agent, independent of the menu bar app. The auto-unlock timer also lives in the agent, so quitting the app neither unlocks the keyboard nor disables the timer. If the agent itself ever exits, its event tap is released and the keyboard simply works again — **no failure path can lock you out of your Mac**.

## Unlock Gestures

**Q: Where do I change the unlock hotkey? Can it be turned off?**

Menu bar icon → ⋯ → Settings → Unlock Hotkey; click the recorder field and press a new combination. **It can't be disabled** — it's the always-reliable way out of a lock, and it's matched by the background agent, so it works even when the app isn't running.

**Q: Can I unlock by typing instead of a key combo?**

Yes. Enable Settings → Unlock Phrase and pick a phrase (3–64 characters: lowercase letters, digits, and spaces). Type it while locked to unlock. The phrase itself **never appears** in notifications, the widget, or the CLI — those only hint that the gesture exists.

**Q: Lock hotkey vs. unlock hotkey — what's the difference?**

- The unlock hotkey (required) is matched by the background agent and always works; it's the way out of a lock.
- The lock hotkey (optional, off by default) is registered by the app and works only while the app is running; ⌃⌘K is the suggested starting point.

Setting both to the same combination gives you a **toggle**: press it to lock, press it again to unlock. While recording, Settings shows a *non-blocking* warning if your combination collides with a system shortcut such as Spotlight or screenshots.

## Timers

**Q: How do I make the keyboard unlock itself after a while?**

Two ways:

- Standing policy: Settings → Auto-Unlock, anywhere from 5 seconds to 60 minutes; applies to every lock.
- One-shot override: `klock lock --for 10m` — applies to that lock only and never rewrites your saved settings.

**Q: Is auto-unlock still accurate after the Mac sleeps?**

Yes. The timer pauses while the system is asleep and reconciles against the wall-clock deadline on wake: a deadline that already passed unlocks immediately; otherwise the timer is rescheduled for the remaining time.

**Q: I changed settings while locked and nothing happened. Why?**

While locked, settings writes are saved but don't touch the current lock — changing them mid-lock would break the auto-unlock fail-safe. The popover notes that they take effect on the **next lock**.

## Automation

**Q: Is there a command-line tool?**

Yes. Settings → klock CLI… installs `klock` (a symlink in a command directory; your shell profile is never modified):

```bash
klock lock              # Lock and wait for the unlock; Ctrl+C unlocks this lock
klock lock --no-wait    # Lock and exit as soon as the agent confirms
klock lock --for 10m    # One-shot timed lock (5–3600 seconds); settings untouched
klock status            # Locked / Unlocked
klock status --json     # Stable one-line {"locked":true} for scripts
klock toggle            # Atomically flip and print the new state
klock unlock
```

`status` reporting "Unlocked" is still a success with exit code 0; only argument or agent-call failures exit 1, so scripts never confuse the two.

**Q: What happens if I close the terminal while `klock lock` is waiting?**

klock makes a best-effort release of the lock it created before exiting. `kill -9` can't be caught; the leftover lock still yields to the unlock hotkey, the notification's Unlock Now button, or auto-unlock.

**Q: Does it work with Shortcuts and Focus modes?**

- Shortcuts: four actions — Lock Keyboard, Unlock Keyboard, Toggle Keyboard Lock, and Get Keyboard Lock Status (returns a Boolean you can branch on). On macOS 26+ they're also promoted App Shortcuts, callable from Spotlight, Quick Keys, and Siri.
- Focus: add the Keyboard Lock filter to a Focus in System Settings > Focus. Entering the Focus locks; leaving it unlocks — but **only a lock that Focus itself created**. If another surface locked first, or you locked again manually during the Focus, leaving the Focus keeps the keyboard locked. Unlocking manually during a Focus *does not relock*.

**Q: Where else can I trigger a lock?**

- Services menu (in any app): Lock Keyboard / Unlock Keyboard / Show Keyboard Lock Status. You can bind these to global shortcuts in System Settings > Keyboard > Keyboard Shortcuts > Services.
- URL scheme: `keyboardlocker://lock`, `keyboardlocker://unlock`, `keyboardlocker://status`, for launchers, browsers, and other local apps. Note there is *no caller authentication* — any app or web page that can ask the system to open a URL can trigger these.
- AppleScript:

```applescript
tell application "KeyboardLocker"
  lock keyboard
  set isLocked to get keyboard lock status
  unlock keyboard
end tell
```

**Q: Which surface should a script use to read the lock status?**

`klock status --json` (stable one-line contract), the Shortcuts status action (Boolean), or AppleScript's `get keyboard lock status`. Services and URL `status` show a human-facing alert and have no machine-readable return channel.

## Widget & Control

**Q: Is there a widget?**

Yes — Keyboard Lock Status in small and medium sizes, showing the lock state, the auto-unlock countdown, and the current unlock hotkey. macOS 14+ adds Lock/Unlock buttons; macOS 13 is read-only. If the agent is unreachable, the widget says Agent Unavailable rather than pretending to be unlocked. Refresh timing is up to the system, so treat it as an overview, *not a live monitor*.

**Q: What's the Control Center toggle?**

On macOS 26+, a Keyboard Lock control you can add to Control Center or the menu bar: on = lock, off = unlock.

## Feedback

**Q: What feedback do I get around locking?**

- A system notification on every lock, from any surface, showing the unlock hotkey and the auto-unlock deadline, with an Unlock Now button; it's removed on unlock. Notification permission is requested on the first lock; if denied, nothing is sent.
- Lock sounds on lock/unlock, whether or not the app is running (Settings → Feedback → Lock Sounds).
- Typing hint: pressing keys while locked shows a brief centered overlay with the unlock hotkey — it never steals focus or blocks the mouse (Settings → Feedback → Typing Hint). Requires the app to be running.
- A live mm:ss countdown next to the menu bar icon whenever auto-unlock is set.

**Q: Can I see lock statistics?**

Yes — the bar-chart icon in the popover toolbar: today's lock count and total locked time, a this-week daily chart colored by unlock method, and the share by unlock method. The agent keeps the 200 most recent records; a lock counts toward the day it ended.

## Troubleshooting

**Q: What should I do on first launch?**

Launch the app once (or run `klock register-agent`) so the background agent registers with the system, and grant Accessibility access when prompted. Then run Settings → Safety Check…: a 10-second lock that proves the unlock path works — the agent force-unlocks even if the app crashes. The app also offers this skippable check the first time it's ready.

**Q: Where do I fix permission or approval prompts?**

- Accessibility: Grant Accessibility Access… in the app, or `klock request-access`, or System Settings → Privacy & Security → Accessibility.
- Login Items: the background agent must stay enabled; if it's disabled, the app shows Approval Required with an Open Login Items Settings button.

**Q: How do I report a problem?**

⋯ menu → Copy Diagnostics: a redacted text report (versions, protocol, registration and permission state, lock snapshot, recent errors — no keystrokes, username, hostname, or file paths). Paste it along with your report.

**Q: Every surface says the agent is unavailable.**

Run `klock register-agent`; if that doesn't help, use Restart KeyboardLocker Agent on the status page. Every surface fails loudly when the agent is unreachable — **nothing will ever guess "unlocked" on your behalf**.
