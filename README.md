# lidawake

**Keep your Mac awake — even with the lid closed.** No more books wedged in your MacBook.

lidawake is a tiny menu-bar app that stops your Mac from sleeping when you close the
lid, so it can keep downloading, backing up, running a task, or playing audio with
the lid shut. One click to turn it on, one to turn it off. Safe by default.

## What it does — and doesn't

lidawake installs a small privileged helper that does exactly one thing: toggles
macOS's documented `pmset disablesleep` setting. That is the only supported way to
keep a Mac awake with the lid closed.

- **No network.** It never phones home (except Sparkle, and only when you check for updates).
- **No data collection.** No analytics, no tracking — nothing leaves your Mac.
- **Open source.** The helper runs as administrator, so you can read every line of
  exactly what it does — right here.

## Safety

Closing the lid blocks your Mac's cooling vent (it's in the hinge), so lidawake is
built to be careful:

- **Off by default on battery** — opt-in, with a warning, since lid-closed-on-battery runs warm.
- **Thermal cutoff** — if the Mac gets too hot, it disarms automatically.
- **Always restores sleep** — on quit, crash, or power loss your Mac goes back to
  sleeping normally. It can never strand your Mac awake.
- **Turns the screen off** when you close the lid.

## Requirements

- Apple Silicon Mac (M1 or later)
- macOS 13 (Ventura) or later

## Install

Download the latest signed, notarized build from **[zayco.it/lidawake](https://zayco.it/lidawake)**.
(Homebrew coming later.)

## How it works

- A menu-bar app (AppKit) for the UI and the safety guards.
- A root LaunchDaemon helper, installed via `SMAppService`, that runs
  `pmset disablesleep`. The app and helper validate each other's code signature
  over XPC before any privileged action.
- IOKit power assertions handle the lid-open "don't idle-sleep" case.
- Automatic updates via [Sparkle](https://sparkle-project.org) (EdDSA-signed).

## Build from source

Command Line Tools only — no Xcode needed.

```sh
./tools/fetch-sparkle.sh   # one-time: fetch the Sparkle framework
./build.sh                 # compile (unsigned, quick check)
SIGN=1 ./build.sh          # signed build (requires a Developer ID certificate)
```

## License

MIT © zaYco s. r. o. — see [LICENSE](LICENSE).
