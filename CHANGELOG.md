# Changelog

All notable changes to lidawake are documented here.
This project follows [Semantic Versioning](https://semver.org).

## [1.1.9] — 2026-08-06

- lidawake now tells you when it’s in the wrong place. If you open it straight from the disk image — or from anywhere other than your Applications folder — it explains that it can’t start its background helper from there and offers to open Applications for you, instead of getting stuck on “Getting lidawake ready…” forever.
- Removing lidawake is honest about what happened: if macOS refuses to remove its background item, lidawake now says so and offers to open Login Items, rather than reporting that everything was removed.
- Clearer wording while lidawake reconnects its helper.

## [1.1.8] — 2026-07-30

- Fixed the message when lidawake turns itself off on battery: it now correctly says the battery reached your set level, instead of mistakenly saying you were unplugged from power.

## [1.1.7] — 2026-07-26

- After an update, lidawake now reconnects its background helper the moment it launches, so it’s usually ready the instant you turn it on — no “Getting ready…” wait.
- Fixed the “Getting ready…” window so its text is no longer cut off.

## [1.1.6] — 2026-07-26

- After an update, lidawake now reconnects its background helper on its own and waits as long as it needs — so you no longer have to click “Try Again” if the helper takes a little longer to start.

## [1.1.5] — 2026-07-26

- Turning lidawake on right after an update is now clean: it briefly shows “Getting lidawake ready…” while it reconnects its background helper, then turns on in one click. The Welcome window no longer reappears if you’ve already set lidawake up.

## [1.1.4] — 2026-07-26

- Fixed turning lidawake on right after an update: it now waits for the background helper to be fully ready, then turns on in a single click — no stray “try again” or setup window first.

## [1.1.3] — 2026-07-26

- Turning lidawake on right after an update is now seamless — one click, with no stray setup window popping up first.

## [1.1.2] — 2026-07-26

- Fixed lidawake sometimes not turning on right after an update — the “just a moment, lidawake is starting up” message that wouldn’t clear. It now repairs its background helper on its own, so you never have to visit Login Items to fix it.

## [1.1.1] — 2026-07-26

- **Using an external monitor with the lid closed?** Your external screen now stays on. Before, closing the lid could switch it off — now you can shut the lid and keep working on the big screen.
- Fixed a case where **two lidawake icons** could show up in the menu bar. There's now only ever one.

## [1.1.0] — 2026-07-04

- **If you already use lidawake, nothing changes — it stays free for you, forever.** Thank you for being an early user.
- Going forward, lidawake has a **14-day free trial**, then a one-time purchase that works on up to **3 Macs**.
- The **About** panel now shows your license or trial status, and paste (⌘V) works in the license field.

## [1.0.3] — 2026-07-01

- Removed the confusing "automatically download updates" checkbox from update prompts — updates stay one-click and intentional.
- **Check for Updates** now opens on the first click, instead of sometimes needing a second.

## [1.0.2] — 2026-07-01

- Added an **About lidawake** menu item that shows the version.
- Update prompts now show what's new (formatted release notes).
- First-run setup: **"I've turned it on" now gives feedback** when the helper still isn't enabled, instead of silently doing nothing.

## [1.0.1] — 2026-07-01

- **Settings now apply live** — changing a toggle takes effect immediately, no need to turn lidawake off and on again.
- Clearer wording in Settings (it now explains the screen dims to save power while your Mac stays awake).

## [1.0.0] — 2026-07-01

First public release.

- Keep your Mac awake with the lid **closed** (on power; opt-in on battery, with a floor and warning).
- Keep awake with the lid **open** (no idle sleep), with an optional keep-the-screen-on too.
- Turns the internal display off when you close the lid.
- Safety: thermal cutoff, battery floor, and always-restore-sleep on quit, crash, or power loss.
- Simple one-time setup (background-helper approval in System Settings), with a first-run welcome.
- Automatic, signed updates via Sparkle.
