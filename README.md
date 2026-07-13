# lidawake

**Keep your Mac awake — even with the lid closed.** No more books wedged in your MacBook.

lidawake is a tiny menu-bar app that stops your Mac from sleeping when you close the
lid, so it can keep downloading, backing up, running a task, or playing audio with
the lid shut. One click to turn it on, one to turn it off. Safe by default.

It does a few things, and does them well — made for people who just want to close the
lid and keep going, not to configure anything.

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

## Free to build, or done for you

lidawake's code is MIT — read it, and build it yourself for free (see
[Build from source](#build-from-source)). The **notarized, ready-to-run app** on
**[zayco.it/lidawake](https://zayco.it/lidawake)** is a small paid product: a **14-day free
trial**, then a **one-time $6.67** (works on up to 3 Macs). If you used lidawake before it
became paid, it stays free for you — forever.

**Why pay for something open source?** Not for a secret — the trick (`pmset disablesleep`) is
well known, and free tools use it too. You're paying for the *packaged* version: notarized so
macOS trusts it on the first launch, a signed helper you approve with one click (no `sudo`
scripts or sudoers grants, no "unidentified developer" bypass), the safety guards, and a real
company to answer if something breaks. Prefer to build it yourself? Please do — that's what the
source is for.

## Install

Download the latest signed, notarized build from **[zayco.it/lidawake](https://zayco.it/lidawake)**
and drag lidawake to your Applications folder.

Or with **Homebrew**:

```sh
brew install --cask zayco-it/tap/lidawake
```

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
