# Changelog

All notable changes to lidawake are documented here.
This project follows [Semantic Versioning](https://semver.org).

## [Unreleased]

- **Two ways to keep your Mac awake, where there was one.** The menu now has "Keep awake until I turn it off" — what lidawake has always done — and "Keep awake until it goes quiet", which turns itself off 30 minutes after the last sign that anything is happening. The icon is blue in the first and green in the second. You can switch from one to the other while it is on without turning it off; clicking the one that is checked turns it off.
- **"Until it goes quiet" watches for seven things:** you using the Mac, sound playing, video playing, one of your programs asking the Mac to stay awake, one of your programs working hard, the graphics chip working, and steady network traffic. What macOS does for itself in the background — analysing photos, indexing, syncing — does not count, however busy it gets. While it is on, the menu shows how long it has been quiet, or which program is keeping it on. A program in another person's account on the same Mac counts as well, but lidawake never shows you its name: it says "a program in another account". When it turns itself off, the note it leaves says what the last thing was and when: "The last thing it saw was sound playing, at 23:40."
- **Which one to pick if you run an AI agent: it depends on how long it waits.** An agent that asks the Mac to stay awake while it works — Claude Code in a terminal does, for every turn — keeps "until it goes quiet" on for as long as its checks come less than 30 minutes apart, and lidawake turns itself off 30 minutes after the last one. Run from a script or a scheduled job instead (`claude -p`, with no terminal interface), Claude Code does not ask, and lidawake cannot see it; start it as `caffeinate -i claude -p …` and it counts for as long as it runs. A loop that waits longer than 30 minutes between checks belongs in "Keep awake until I turn it off". So does anything else that works in bursts with long waits between them, a job on another computer that you are only waiting for, a muted video in Chrome, Edge, Brave or Arc, and work under another user account that never asks the Mac to stay awake. Both menu items say so when you hover over them.
- **This is the automatic cut-off that 1.4.9 switched off**, because what it counted could not tell an idle Mac from a working one — it added up everything the processor was doing, and macOS's own background work alone kept that busy all night. It is back, built on what was measured instead: it asks whose work it is, not how much there is. And it is a choice now, not something that happens to you: "Keep awake until I turn it off" never stops by itself, short of the Mac overheating or the battery running low.
- **One switch where there were two.** In Settings, "Let lidawake manage the screen" is gone and "Keep the screen on" stays, always visible. The removed row never changed anything by itself — while lidawake is on, it keeps your Mac awake with the lid open too, whatever that row said — it only showed or hid the switch beneath it. Your setting carries over exactly: if your screen was being kept on, it still is, and if it wasn't, it still isn't.
- **"Keep the screen on" now means what its heading says: only while the lid is open.** Until now it held the screen awake whenever lidawake was on, lid open or shut — so with the lid closed on an external monitor, that monitor never went to sleep, and could stay lit all night after you left your desk. Now, when you close the lid, the monitor sleeps on its normal timer, and when you open the lid again the setting applies as before. Your Mac itself stays awake either way.

## [1.5.0] — 2026-09-27

- **lidawake now warns you, out loud, when your Mac is about to stay awake in a bag.** If you close the lid while lidawake is on and your Mac is on battery, it plays a sound — the first sound lidawake has ever made — and leaves a note in Notification Center saying so. The same happens if you unplug with the lid already shut, which is how a laptop comes off its dock and goes into a bag, and which used to get no warning at all. This only applies if you have turned on "Keep going on battery power"; otherwise unplugging turns lidawake off, as before.
- **It stays quiet when a closed lid is plainly what you meant.** Plugged in, closing the lid is usually deliberate — an overnight download, a closed laptop driving a monitor — so nothing happens. Closing the lid on battery with an external display attached gets you the note without the sound. With battery use on, unplugging with the lid already shut always sounds, even with a monitor still attached: from the Mac's side, pulling just the charger at a desk looks the same as pulling a dock on the way out, and a sound at your desk costs far less than a Mac left running in your bag.
- **It does not fight your volume.** Muted, or turned all the way down, it stays silent. If the volume is below 60%, it is raised to 60% for the second the sound plays and put straight back — unless you changed it yourself in the meantime, in which case yours stands, or switched to headphones, in which case they are left alone. If lidawake quits unexpectedly mid-sound, the volume is put back the next time it opens.
- **The morning summary is still silent.** A Mac that has been awake all night still does not announce itself with a chime. The sound is only for the moment when you can still do something about it.

## [1.4.10] — 2026-09-20

- **Six lines of explanation were being cut off mid-sentence, and now read in full.** The worst was the message shown when a license key isn't accepted: it told you the key wasn't recognized and then stopped, exactly where it was about to say what to do — copy the key again from your purchase email, and write to us if it still won't take. That advice was added in 1.4.7 and has never once been readable. The Welcome window lost four lines the same way, including the whole of the reply to "I've turned it on" that tells you what to check when the background item still isn't on, and the buy screen cut off how many days of your trial are left.
- **Nothing about the wording changed — the words were always there.** They were drawn wider than the window and quietly truncated, which is why every check we had passed: a sentence nobody can read is still a sentence that appeared. Testing now measures whether text fits, not just whether it showed up.
- **This is the same fault that was found and fixed once before**, in the "Getting lidawake ready" window in 1.1.7. The fix was never carried across to the two windows that had it too. Both now have it, and a check that fails the build catches the next one.

## [1.4.9] — 2026-09-06

- lidawake no longer refuses to turn on while your Mac is plugged in and charging below your battery limit — and then tells you to charge it, which is what you were already doing. That limit exists to stop the battery running out, and it cannot run out while charge is going in. It now applies whenever charge is actually being lost: on battery always, and while plugged in only if your Mac is draining anyway, which an underpowered adapter or a busy hub really can do.
- When the battery is below your limit and still falling while plugged in, lidawake now says where the battery is instead of announcing it reached a limit it was already past. On battery the old wording stays, because there it is accurate — the charge did fall to your limit while running.
- The "Turn the screen off" setting is gone. There was no situation in which switching it off helped you. With an external display connected lidawake never touched your screens anyway, and without one the setting only decided whether to light a panel behind a shut lid that nobody can see — spending power and making heat for nothing, which is the exact thing the battery warning below it argues against. Closing the lid now sleeps the built-in screen, and an external display is left alone, as before. Removing that row also fixed a line of explanation that had been cut off the bottom of the Settings window in every release so far, whenever both sections were open.
- The lid-open setting now describes what lidawake actually does. It used to read "Also keep my Mac awake", which offered a choice lidawake does not have: while it is on, your Mac stays awake with the lid open too. What you can genuinely choose is what happens to the screen, so that is what the setting now says.
- lidawake now tells you when its helper has turned it off. If lidawake stops responding, the helper hands sleep back to macOS after ninety seconds — that has always been true, and it is the safety net that makes lidawake safe to leave running. But lidawake used to notice and flip itself quietly to off, leaving you to discover it. Every other way it stops explains itself; this one does now too.
- The automatic "nothing is happening, let it sleep" cut-off no longer runs. Measured in the situation it was built for — lid shut, unattended, ordinary apps open — it read "busy" permanently and so never once fired. It was not a threshold set slightly wrong; the thing it counted cannot tell an idle Mac from a working one. It will return built on measurements that do work, and until then nothing in lidawake claims it is there.

## [1.4.8] — 2026-09-04

- Pressing Return after pasting your license key now activates it. It used to close the window instead, leaving the key untried and nothing on screen to say so — on the one screen where you can least afford to wonder whether anything happened. Escape closes the window now, which is what Escape is for.

## [1.4.7] — 2026-09-04

- The license key box no longer shows a made-up example key. It used to hint at a format like XXXX-XXXX-XXXX-XXXX, which looks nothing like the keys actually issued — so the only clue the box offered was telling people holding a perfectly good key that theirs was the wrong shape, before they had even tried it. It now simply says to paste your key.
- If a key isn't accepted, lidawake now says something you can act on: copy it again from your purchase email, and write to us if it still won't take. It used to say "check for typos", which assumed you had typed a key that nobody types — they are pasted, not retyped.
- The buy screen no longer tells everyone their license covers three Macs. That stopped being true when the single-Mac license went on sale, and it was being shown to the person about to buy one.

## [1.4.6] — 2026-09-04

- Uninstall now checks that macOS actually dropped lidawake's background item, instead of assuming it worked because the request didn't fail. If the item is still registered afterwards, lidawake says so and points you at the one switch that finishes the job — rather than reporting a clean removal it never confirmed. Removing an app shouldn't leave a background item behind, and it certainly shouldn't tell you it hasn't.
- When lidawake's helper is registered but never answers, it now says that, instead of asking you to switch on something that is already switched on. The old message sent you to System Settings to turn on a background item you would have found already turned on — the one piece of advice that could not have helped in the situation that produced it.

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
