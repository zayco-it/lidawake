# Changelog

All notable changes to lidawake are documented here.
This project follows [Semantic Versioning](https://semver.org).

## [1.0.1] — unreleased

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
