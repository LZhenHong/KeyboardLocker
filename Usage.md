# KeyboardLocker Usage Guide

KeyboardLocker locks your keyboard — every key, including the system control keys for volume, brightness, and media playback — while your mouse and trackpad keep working. This guide covers first setup and everyday use; for edge cases and automation details, see the FAQ (⋯ → FAQ…).

## Getting Started

### Set up on first launch

1. Launch KeyboardLocker. Its icon appears in the menu bar.
2. If macOS asks, keep the background agent enabled under System Settings → General → Login Items — the agent holds the lock independently of the app.
3. Grant Accessibility access when prompted; the agent needs it to filter keyboard events.
4. Run the Safety Check when the app offers it: a 10-second lock that proves your unlock path works. **The agent force-unlocks even if the app crashes, so the check can never lock you out.**

All of these stay reachable later: the status page shows approval and permission buttons whenever they need attention, and Settings → Safety Check… reruns the check anytime.

### Find your way around the popover

Click the menu bar icon:

- The status card shows the current state — while locked, with a live countdown to auto-unlock.
- The prominent button locks or unlocks the keyboard.
- The bar-chart icon opens lock statistics: today's count and total locked time, this week's daily chart, and the share by unlock method.
- The ⋯ menu holds Settings…, this Usage Guide, the FAQ, Copy Diagnostics, and Quit.

## Locking and Unlocking

### Lock the keyboard

- Menu bar icon → Lock.
- Or press the lock hotkey if you enabled one (Settings → Lock Hotkey; off by default).

Every lock posts a system notification showing the unlock hotkey and the auto-unlock deadline, with an Unlock Now button.

### Unlock the keyboard

Every surface unlocks the same global lock — pick whichever is within reach:

1. Press the unlock hotkey (⌃⌘L by default; change it in Settings → Unlock Hotkey).
2. Click Unlock Now in the lock notification.
3. Menu bar icon → Unlock.
4. Type your unlock phrase, if you set one (Settings → Unlock Phrase).
5. Wait for auto-unlock.

*The unlock hotkey can't be disabled — the background agent matches it, so it works even when the app isn't running.*

## Timing

### Let locks end by themselves

Settings → Auto-Unlock picks how long every lock lasts, from 5 seconds to 60 minutes (60 seconds by default). The timer pauses while the Mac is asleep and reconciles against the wall-clock deadline on wake, so it stays accurate. Choosing Never is possible but discouraged: the app asks for confirmation because it removes the fail-safe.

### Lock once with a custom duration

`klock lock --for 10m` creates a single lock with its own auto-unlock (5–3600 seconds) and never rewrites your saved settings. The FAQ covers installing the CLI.

## While Locked

### Tune the feedback

- Typing hint: pressing keys while locked shows a brief centered overlay with the unlock hotkey — it never steals focus or blocks the mouse (Settings → Feedback → Typing Hint).
- Lock sounds play on lock and unlock, whether or not the app is running (Settings → Feedback → Lock Sounds).
- A live mm:ss countdown sits next to the menu bar icon whenever auto-unlock is set.

### If something looks wrong

The status page surfaces recovery buttons for the common cases: agent approval, Accessibility permission, agent update, and agent restart. ⋯ → Copy Diagnostics produces a redacted report — no keystrokes, username, hostname, or file paths — to attach to a problem report.

## Beyond the Menu Bar

### Drive it from anywhere

KeyboardLocker can also be driven from the `klock` CLI, Shortcuts, Focus modes, the Services menu, the `keyboardlocker://` URL scheme, AppleScript, a desktop widget, and Control Center. The FAQ covers each surface and its guarantees.
