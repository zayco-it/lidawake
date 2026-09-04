# Changelog

All notable changes to lidawake are documented here.
This project follows [Semantic Versioning](https://semver.org).

## [1.4.5] — 2026-09-04

- Fixed lidawake asking you to finish setting it up after an update, on a Mac where it was already set up — and then sending you to System Settings to switch on a background item that was already switched on. lidawake now asks its background helper whether it is actually working before it says anything about setup, instead of trusting a macOS status that can be wrong in both directions. A helper that is slow to answer after an update is still reconnected quietly in the background, exactly as before; what has changed is that the menu no longer contradicts that by telling you to go and redo it by hand.
- **Keep my Mac awake** now stays available while the helper is reconnecting. It used to be greyed out in precisely that situation, which closed off lidawake's own repair — the one thing that would have fixed it — and left you with nothing to do except the thing it was wrongly asking for.

## [1.4.4] — 2026-09-02

- Fixed the reason you may never have seen lidawake's messages. When lidawake keeps your Mac awake with the lid shut it also turns the screen off — and anything it had to tell you was being sent to that dark screen, where macOS files it away silently instead of showing it. Opening the lid did not bring it back. Messages now wait until your screen is actually on, so you see them when you open the lid rather than finding them in Notification Center days later.
- Turning itself off after a quiet spell now tells you the whole story in one message, when you open the lid: why it stopped, and how long your Mac stayed awake, whether it stayed cool, and what the battery did. Previously the "turned itself off" notice was sent while the lid was still closed — so it could never be seen — and the summary was thrown away entirely, which meant a Mac left overnight greeted you with nothing at all in the morning.
- Anything lidawake needs to tell you now also waits in its menu until you have actually seen it. It used to clear that reminder as soon as macOS accepted the notification, which is not the same as you reading it — so a message that arrived during Do Not Disturb, or while the screen was off, could disappear having been shown to nobody.

## [1.4.3] — 2026-09-01

- Fixed the likeliest way a brand-new install looked broken. If you opened lidawake straight from the disk image before dragging it to your Applications folder, that first copy kept running in the background — and the copy you then installed properly quit the instant you opened it. No window, no menu-bar icon, no explanation, on what was a perfectly good install. The installed copy now opens normally: a copy of lidawake that can't work never stops one that can.
- If lidawake does decline to open because another copy is genuinely already running, it now says so and tells you where that copy is, with a button to show you — instead of quitting without a word.

## [1.4.2] — 2026-08-27

- Reverted the icon introduced in 1.4.1. In a real menu bar you couldn't tell at a glance whether lidawake was on or off — the two states looked almost the same unless you saw them side by side, which never happens. The previous icon is back, where the menu-bar symbol turns blue while lidawake is keeping your Mac awake.

## [1.4.1] — 2026-08-27

- New icon. lidawake now shows a closed laptop with its light on — which is what the app actually does. The old one drew an open laptop with a lit screen, the opposite, and it dissolved into an unreadable blob at small sizes.
- The menu-bar icon is lidawake's own mark now, instead of a stock macOS symbol, and it tells you at a glance whether lidawake is on: the light above the lid is lit when it's keeping your Mac awake. It follows your menu bar in light mode, dark mode and with a tinted background, which the old one didn't.

## [1.4.0] — 2026-08-27

- lidawake now switches itself off when it isn't needed. If your Mac has been sitting with the lid closed and nothing has actually been happening for half an hour — no work, no downloads — it stops holding your Mac awake and lets it sleep normally, then tells you it did. You no longer have to remember to switch it off.

## [1.3.0] — 2026-08-26

- lidawake now opens when you log in, so it keeps working after you restart your Mac. Until now it quietly stopped at every restart and nothing on screen explained why — your Mac just went back to sleeping the moment you closed the lid. It tells you once when it sets this up, and you can switch it off whenever you like in System Settings › General › Login Items.
- Open the lid and lidawake now tells you what happened while it was shut: how long your Mac stayed awake, whether it got warm, and what the battery did. These tools are invisible by nature, and this is the first time lidawake shows you it actually did its job.

## [1.2.0] — 2026-08-26

- Safety: if lidawake ever freezes while it’s keeping your Mac awake, its background helper now notices and restores normal sleep on its own. Until now that was only caught if lidawake quit or crashed outright — a frozen-but-still-running lidawake would leave your Mac unable to sleep, with the overheating and battery cut-offs frozen along with it.
- After an update, lidawake now makes sure it’s really using its new background helper, rather than the one already running from before. Otherwise improvements to the helper wouldn’t reach you until the next time you restarted your Mac.

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
