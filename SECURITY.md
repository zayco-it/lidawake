# Security Policy

lidawake installs a **root LaunchDaemon** and changes a **system-wide power
setting** (`pmset -a disablesleep`). That is a small amount of privilege, but it
is real privilege, and reports about it are welcome.

lidawake is maintained by one person at zaYco s. r. o. Please read "What to
expect" before reporting — there is no SLA and no bounty.

## Reporting a vulnerability

Email **security@zayco.it**. Please don't open a public issue, discussion or PR
for a security problem — mail first and give me a chance to ship a fix.

Useful things to include:

- lidawake version (menu ▸ About, or `CFBundleShortVersionString`), and the
  helper version if you have it (`helperVersion` over XPC — currently 2.2.0)
- macOS version and hardware
- what you did, what happened, what you expected
- a proof of concept if you have one, even a rough one

I don't publish a PGP key. If you need encryption, send a first mail with no
details and we'll sort something out.

## What to expect

- **Acknowledgement:** as soon as I can, realistically within a week. If you've
  heard nothing in two weeks, assume the mail went astray — resend, or open a
  public issue saying only "I emailed you about a security issue", no details.
- **A straight answer:** whether I think it's real, and roughly when I can fix
  it. If I disagree that it's a vulnerability, I'll say why rather than go quiet.
- **Disclosure:** I'd like 90 days, or until a fix ships, whichever comes first.
  If I go quiet on you, publish — that's better than sitting on it indefinitely.
- **Credit:** your name, handle or link in the CHANGELOG entry for the fix and
  in the release notes. Say so if you'd rather stay anonymous.
- **No bounty.** No money, no swag, no perks. lidawake is a one-person product
  with no security budget. If you need a paid engagement, this isn't one —
  please decide that before spending time here.

## Supported versions

Only the **latest release** gets security fixes. Current: **1.4.9**. There are no
backports; a fix ships as a new version and reaches users through Sparkle.

Worth knowing when you verify a fix: the helper is versioned separately
(currently **2.2.0**), and replacing the app bundle does **not** restart an
already-running LaunchDaemon. Until the app re-registers it or the Mac reboots,
the previous helper binary is still the one answering XPC.

## In scope

- **The privileged helper** (`lidawake-helper`, LaunchDaemon
  `it.zayco.lidawake.helper`, runs as root). Anything that makes it do more than
  `pmset -a disablesleep 0|1` and `pmset displaysleepnow`.
- **The XPC interface and its code-signature check.** Both sides call
  `setCodeSigningRequirement` before `resume()`, with a requirement pinning an
  Apple anchor, the bundle identifier, the Developer ID CA and leaf OIDs, and
  team `FXNTJBLQ2F` (`Sources/Shared/HelperProtocol.swift`). Getting an
  unauthorised process talking to the helper, or impersonating the helper to the
  app, is the highest-value report here.
- **The `pmset` invocation.** It runs `/usr/bin/pmset` by absolute path with
  fixed argument arrays and no shell, so there is nothing user-controlled to
  inject today. A way to influence the path, the arguments, or the environment it
  inherits is in scope.
- **The Sparkle update path.** Appcast at
  `https://zayco.it/lidawake/appcast.xml`, enclosures on GitHub Releases,
  EdDSA-verified against `SUPublicEDKey` in Info.plist, automatic checks on and
  automatic install off. Anything that installs a build not signed by that key —
  downgrade, appcast substitution, signature-check bypass — is in scope, as is
  abuse of the nested Sparkle XPC services re-signed under the zaYco Developer ID
  (`Downloader.xpc`, `Installer.xpc`, `Updater.app`, `Autoupdate`).
- **The Freemius licence flow.** Activation sends the licence key, a 32-char id
  derived from `IOPlatformUUID` (not the serial number) and the Mac's name to
  `api.freemius.com` over HTTPS; no API secret is embedded. In scope: that data
  reaching anywhere else, TLS or response-parsing flaws, and mishandling of the
  per-install token.
- **Failing open on the safety path.** If you can leave a Mac with
  `disablesleep=1` and no process able to clear it — defeating the reset on
  helper launch, the dead man's switch on connection loss, or the 90-second
  watchdog — that's a real bug and I want it.

## Out of scope

- **Licence and trial bypass.** The licence record and trial start live in
  `UserDefaults`, validation is cached and trusted offline, and none of it is
  obfuscated. That is deliberate: enforcement is light on purpose, and the source
  is MIT, so you can build lidawake for free anyway. Reports that this can be
  bypassed will be closed as working as intended.
- **lidawake doing its job.** Keeping a Mac awake with the lid closed, and the
  heat that comes with it, is the product. Thermal or battery-guard problems are
  welcome as ordinary bug reports, not security ones.
- **Anything that already requires root or admin.** Approving the daemon takes an
  admin once, by design; an attacker who has that has already won.
- **Physical-access scenarios** — unlocked Mac, evil maid, DFU.
- **Third-party infrastructure.** Freemius, GitHub, Homebrew and the zayco.it
  marketing pages belong to their owners; report there. The appcast endpoint's
  integrity is in scope, because lidawake trusts it.
- **Missing hardening with no exploit path.** lidawake is signed with the
  hardened runtime and notarized, but is not App-Sandboxed — an app that
  registers a LaunchDaemon can't be. Scanner output, "best practice" checklists
  and missing-mitigation reports without a working attack aren't useful to me.
- **Denial of service, spam, social engineering, self-XSS.**

## No warranty

lidawake is MIT-licensed and provided as is, without warranty — see
[LICENSE](LICENSE). This policy describes how I handle reports. It is not a
contract.
