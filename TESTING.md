# lidawake — manual test plan

How to verify the app does what it should. Work top to bottom; each section is
independent. Check the box when it passes. "Core" tests are must-pass before any
release; the rest are good coverage.

> Why manual: the product is a physical-behaviour app (closing the lid, pulling
> power). Most of it can't be unit-tested — it has to be exercised on a real Mac.

> **Read every line end to end — do not just confirm it appeared.** Six explanatory
> lines shipped truncated from 1.0.0 through 1.4.9, including the licence-activation
> error that tells a paying customer what to do when their key will not take. They
> shipped because the checks here ask whether text is *present*, and a truncated
> string is present: the first-run check in the Quick regression pass passes on a
> sentence nobody can read, and the 1.0.2 entry in the results log quotes one of
> them mid-truncation without noticing.
>
> `tools/ui-selftest.swift` now catches the geometric half of this automatically —
> it fails if a string cannot fit the window width and is not free to wrap:
>
> ```sh
> swiftc -O tools/ui-selftest.swift -framework AppKit \
>     -o /tmp/lidawake-ui-selftest && /tmp/lidawake-ui-selftest
> ```
>
> It cannot tell you the words are *right*. That half is still your eyes.

> ## ⚠ Every result below was taken on macOS 26 (Tahoe) or earlier
>
> This Mac moved to **macOS 27.0 (Golden Gate, build 26A428)** on 2026-09-20. The
> log has **not** been re-run against it. Spot-checked on 27 that day — a sample,
> not a pass:
>
> | checked on 27 | result |
> |---|---|
> | `pmset disablesleep` | works; still absent from the man page |
> | `AppleSmartBattery` → `InstantAmperage` | present, signed value reads correctly |
> | SMAppService daemon + XPC signature check | survived the upgrade, helper runs from boot |
> | arm → `SleepDisabled 1` → clean quit → `0` | pass |
> | force-kill dead man's switch | pass |
> | `tools/power-selftest.swift` | 19/19 |
> | Login Items row | survived the upgrade |
> | Gatekeeper / notarization | still `accepted`, Notarized Developer ID |
> | `arm64-apple-macos13` target | still compiles and runs on SDK 27 |
>
> **Not re-verified, and these are the two that matter:** a *fresh* install from a
> downloaded DMG, and the Sparkle update path (§8). Both need hardware, and both
> are where macOS 27 is most likely to bite. A macOS 27 regression breaking
> privileged helpers was chased to a conclusion on 2026-09-20 on shipping 27.0
> (26A428). **lidawake is NOT affected, and the reason is worth keeping.**
>
> Two of the three links are real:
>
> 1. Copying the app out of a quarantined DMG does put `com.apple.quarantine` on
>    `Contents/Library/LaunchDaemons/it.zayco.lidawake.helper.plist` — verified
>    with both `ditto` and `cp -R`. Gatekeeper does **not** clear it from nested
>    files at first launch, verified with a notarized third-party app installed
>    the ordinary way.
> 2. launchd does refuse a plist carrying that attribute — `launchctl bootstrap`
>    on a quarantined LaunchAgent fails `Bootstrap failed: 5: Input/output
>    error`, and the same file loads after nothing but `xattr -d`.
> 3. **But link 3 does not connect, because `SMAppService` never takes that
>    path.** Its jobs are parsed by `smd` and submitted to launchd as a job
>    dictionary — `launchctl print system/it.zayco.lidawake.helper` shows
>    `path = (submitted by smd.…)`, where a legacy daemon shows a real
>    `/Library/LaunchDaemons/….plist`. The quarantine check lives in launchd's
>    read-a-plist-from-disk path, which is never reached.
>
> Proven, not reasoned: a Developer ID–signed probe app registering an embedded
> LaunchAgent through `SMAppService` registered and **ran** with the nested plist
> quarantined, and again with the agent executable quarantined too. The signature
> stayed valid throughout (quarantine is excluded from code signing), and `smd`
> left the attribute in place rather than stripping it — it simply does not
> consult it.
>
> **Why SMJobBless apps do break:** they *copy* the helper and its plist out of
> the quarantined bundle into `/Library/PrivilegedHelperTools` and
> `/Library/LaunchDaemons`, carrying the attribute with them — and launchd then
> file-loads those copies. lidawake's helper never leaves the bundle, which is
> what `BundleProgram` buys. **Do not “simplify” the helper to a copy-out
> install.**
>
> Residual gap, stated so nobody assumes it was covered: the probe was a
> gui-domain *agent*, not a system-domain root *daemon*. The load mechanism, not
> the domain, was the deciding variable in both directions — a gui-domain agent
> was refused via the file path and allowed via the submit path — but a real
> daemon was never tested, which would need a clean machine.
>
> If a helper ever does fail this way the symptom is “Getting lidawake ready…”
> forever plus `helper register failed`, and the workaround is one command:
> `xattr -dr com.apple.quarantine /Applications/lidawake.app`.
>
> **`./build.sh` builds again on macOS 27 with Command Line Tools alone**, as of
> 2026-09-20. It had failed with 12 errors: SwiftUI's `@State` is an external
> macro in Swift 6.4 and the CLT ships no SwiftUI macro plugin. The six `@State`
> declarations in `Onboarding.swift` and `LicenseWindow.swift` are now
> hand-expanded to the storage the property wrapper always desugared to, so the
> macro spelling is gone. **Do not "tidy" them back to `@State`** — it breaks the
> CLT-only build the README promises.

## Results log

**2026-07-04 — 1.1.0 (paid licensing: 14-day trial → Freemius license key, grandfather 1.0.x), tested BEFORE
release.** Licensing is app-side + signing-independent, so most was verified on the UNSIGNED dev build (forced
states via `defaults` + env hooks) plus a real SANDBOX purchase: **live activation PROVEN** — real key → `FreemiusProvider.activate`
hit api.freemius.com → success → `LicenseRecord` cached → relaunch came up `.licensed` (real Freemius install, not
mock); **wrong key** → "That license key wasn't recognized"; **trial About** "Free trial — 9 days left"; **expired**
license window (price-free "Buy lidawake…"); **⌘V paste** works (new Edit menu); hardware-`IOPlatformUUID` binding
(1 Mac = 1 of 3 seats). Headless `tools/license-selftest.swift` (real sources, isolated defaults) = **11/11**
(trial/grandfather/sticky/countdown/expiry/licensed/expired-record). On the SIGNED 1.1.0 build: **grandfather PASS** —
this Mac (existing 1.0.x user) launched with NO paywall, "Keep my Mac awake" enabled; and `arm()` was proven to pass
the new paywall gate (ran all the way through to the final helper XPC call). **NOT freshly re-run (documented): the
literal arm→`SleepDisabled 1` flip on 1.1.0** — the root helper was wedged by SELF-INFLICTED dev churn (unsigned +
signed builds of the same bundle id), NOT a code regression: **helper + Shared code are byte-identical to v1.0.3**
(`git diff v1.0.3 -- Sources/Helper Sources/Shared` is empty), and arm/disarm/pmset were fully verified in 1.0.x.
Per the proportionate rule, core wake/safety is UNCHANGED → §3 lid-close, §6 battery, §7 thermal skipped. **Untested:**
the all-3-activations-used error path (needs 3 Macs). **Known-open at ship:** the PRODUCTION checkout wasn't confirmed
processing a real purchase (sandbox only) — existing users are grandfathered + new users have a 14-day trial buffer.

**2026-07-01 — 1.0.3 (no-checkbox one-click updates + first-click fix), tested BEFORE and validated AFTER
release.** Pre-ship: checkbox removal (`SUAllowsAutomaticUpdates=false`) AND first-click fix (activate before
`checkForUpdates`) both PROVEN locally on a fake "1.0.1 + key" build that finds the live 1.0.2 — dialog opened
on the FIRST click, no auto-download checkbox; About=1.0.3; `git diff` vs tested v1.0.1 shows
WakeAssertionManager/PowerPolicy/HelperManager/Settings **0-changed** (only Onboarding feedback + About +
checkForUpdates differ). Post-release: live **1.0.2→1.0.3 Sparkle self-update** — downloaded/verified/installed/
relaunched as 1.0.3; **NO re-onboarding** (approval preserved — the greyed dev-build "Finish setup" was
self-inflicted rebuild churn on `build/`, NOT a regression; the clean `~/Applications` install stayed enabled);
arm→`SleepDisabled 1`, disarm→`0`. **Key lesson:** the update DIALOG is drawn by the OLD (running) app, so the
checkbox/first-click fixes only take effect once a user is already ON the fixed version — the 1.0.2→1.0.3
dialog still showed 1.0.2's checkbox (expected/unavoidable, not a bug). Also fixed release hygiene: `release.sh`
now refuses a dirty tree so tags match the build (the v1.0.2 tag had silently drifted to the 1.0.1 commit).

**2026-07-01 — 1.0.2 (About item, onboarding-feedback, appcast release-notes/no-checkbox), tested BEFORE
release.** PASS (signed build): §1-normal — helper enabled, no spurious onboarding, "Keep my Mac awake" active;
§10 About → "Version 1.0.2 (3)" + copyright + icon; onboarding "I've turned it on" now shows the "don't see it
enabled yet" feedback (reproduced on an *unsigned* build, which is the only way to hold the not-enabled state);
Quick regression — arm→`SleepDisabled 1`, disarm→`0`, quit-while-armed→`0` clean, helper survives (KeepAlive).
Release-notes HTML dry-run renders correctly. **Skipped (documented): §3 lid-close, §6 battery, §7 thermal —
1.0.2 changed zero core wake/safety code since 1.0.1's full pass.** Post-release TODO: 1.0.1→1.0.2 self-update
test to confirm the update dialog shows notes + no auto-download checkbox (only verifiable against a live appcast).

**2026-07-01 — 1.0.1 live-settings fix, tested (this time BEFORE promoting the update).** PASS: arm holds
the correct locks (system + display per settings); **live-apply confirmed** — toggling "keep screen on too"
off/on while armed drops/returns the display lock *immediately*, system lock undisturbed; toggling "also keep
awake" off drops both lid-open locks while `SleepDisabled` stays 1; no spurious disarm across 4 toggles;
disarm restores (0, no leaked locks); force-kill dead-man's switch still fires (→0 in ~2s). The
`WakeAssertionManager` rewrite + `UserDefaults` observer introduced no regressions. (Lesson: test-before-ship —
this was validated *after* release by mistake; see the `never-ship-untested` rule.)

**2026-06-29 — full pass on M5 / Tahoe 26.4 (signed build).** PASS: §1 first-run +
Welcome onboarding · §2 glyph/menu · **§3 core lid-closed awake — on AC AND on
battery** (clean ~4.5-min sampled run, `SleepDisabled` held 1 throughout, zero
sleep in `pmset -g log`) · §4 screen-off · §5 lid-open system+display assertions ·
§6 battery refuse→opt-in→arm + auto-disarm on unplug · §7 restore on
disarm/quit/**force-kill (dead-man's switch, ~1.5s)** · §8 Uninstall + self-heal ·
§9 settings toggles + persistence. NOT run (un-forceable): §7 thermal cutoff
(can't overheat on demand); §8 "Try Again" dialog (needs the root helper down).
**Finding:** battery lid-closed *works* — the battery default-off is a heat guard,
not a capability limit (overturns the old "battery sleeps" spike note).

---

## Handy commands (run in a terminal)

```sh
# Is the privileged helper alive?
pgrep -lx lidawake-helper

# Is sleep currently blocked? 0 = normal, 1 = armed/blocked. MUST be 0 when off.
pmset -g | grep -i sleepdisabled

# Heartbeat: prints the time every 5s. A gap = the Mac slept; continuous = awake.
( while true; do date; sleep 5; done ) >> /tmp/awake.log &
tail -f /tmp/awake.log            # watch it;  kill %1  to stop the loop later

# Force-kill the app (for the dead-man's-switch test)
pkill -9 -x lidawake
```

## Build & launch

```sh
./build.sh            # compile check only (cannot talk to the helper)
SIGN=1 ./build.sh     # signed — REQUIRED for arm/disarm (helper XPC gate)
open build/lidawake.app
```

- [ ] `SIGN=1 ./build.sh` ends with "satisfies its Designated Requirement".
- [ ] App launches: a laptop icon appears at the right of the menu bar.

> Known dev quirk: a signed rebuild briefly kills the root helper; `launchd`
> (`KeepAlive`) restarts it within ~1 minute. If you arm in that window you'll
> get the "starting up — Try Again" dialog. Wait, then Try Again. Not a bug.

---

## 1. First run / setup (the new-user experience)

Start from a clean state (use **Uninstall lidawake…**, or a machine that never
had it). Relaunch the app.

- [ ] Menu shows **Finish setup…**, and **Keep awake until I turn it off** is greyed out.
- [ ] Status line reads "Finish the one-time setup to begin".
- [ ] Click **Finish setup…** (or **Keep awake until I turn it off**) → System Settings opens
      to Login Items.
- [ ] Approve lidawake under **Allow in the Background** (admin prompt on this
      Standard account is expected).
- [ ] Reopen the menu → **Keep awake until I turn it off** is now enabled, **Finish setup…**
      is gone.

### The launch probe (added 1.4.5) — MUST be run on hardware

The app now asks the helper whether it answers before it says anything about
setup, so the Welcome window arrives on a reply rather than on a guess. That
makes it slightly late on a genuine first run, and these two are exactly what
that delay could cost. **Reasoning about them is not enough — watch the screen.**

- [ ] **The Welcome window does not steal focus from something you were reading.**
      Launch a never-set-up copy, then immediately click into another app and
      start reading. When Welcome appears it must not yank you out mid-sentence.
      (It calls `activate(ignoringOtherApps: true)`; that was harmless when it
      fired synchronously at launch and is the thing to watch now that it doesn't.)
- [ ] **Nothing flickers in the menu bar or the menu while the probe runs.** Launch
      an already-set-up copy and open the menu immediately, before the probe can
      have replied. It must read "Off — your Mac will sleep normally" with a live
      toggle from the first frame — never "Finish setup…", not even for an instant.
      Hold the menu open for ~3s: nothing may change under you.
- [ ] The glyph must not blink or change during launch — `updateIcon()` reads only
      `armed`, so this is a regression check, not an expected behaviour.
- [ ] Approve in Login Items during onboarding, click **I've turned it on** →
      **Get Started**, then open the menu: **Keep awake until I turn it off** is live and
      **Finish setup…** is gone, *before* the helper has ever answered.

### Install location & duplicate copies (added 1.4.3)

The canonical first run, in order — this exact sequence used to leave a correct
install looking dead (issue #1). Mount the DMG rather than copying the app: a
copied bundle loses its stapled ticket and Gatekeeper rejects it.

- [ ] Open the DMG and launch lidawake **from the disk image**. Window:
      "Move lidawake to your Applications folder". No menu-bar icon appears,
      and the process stays running.
- [ ] Leaving that copy running, drag lidawake to Applications and launch it
      from there. It **must start normally and show its menu-bar icon** —
      it must not exit silently.
- [ ] Now quit the disk-image copy and launch it again while the Applications
      copy runs. Window: "lidawake is already running", naming
      `/Applications/lidawake.app`, with **Show Me Where** and **OK**.
      **Show Me Where** reveals it in Finder; **OK** quits that copy.
- [ ] Launch the same `/Applications` copy a second time (`open -n`, or run
      `Contents/MacOS/lidawake` in a terminal). It exits quietly, exit code 0 —
      no window. Silence is correct only when both paths match.

## 2. Menu-bar glyph & menu state

- [ ] **Off:** monochrome laptop glyph; neither item checked; status "Off — your
      Mac will sleep normally".
- [ ] **Keep awake until I turn it off:** glyph turns **blue**; that item is
      checked; status "On — you can close the lid".
- [ ] **Keep awake until it goes quiet:** glyph turns **green**; that item is
      checked; status "On — stops after 30 min of quiet (active now)". Leave the
      Mac alone and reopen the menu: the part in brackets becomes "(quiet for
      N min)" and N grows.
- [ ] **Kept on by a program:** in quiet mode, run `caffeinate -i -t 60` in a
      terminal and open the menu within the minute → the brackets read "(kept
      on by zsh)" — the shell that started it. After the minute: "(active now)"
      again. This is how a program that never lets go explains itself.
- [ ] **Switching while on:** with one mode checked, click the other → the
      checkmark and the colour move, `pmset -g | grep SleepDisabled` reads `1`
      before, during and after, and no window, alert or notification appears.
- [ ] **Clicking the checked mode** turns lidawake off, from either.
- [ ] **Tooltips:** hover each item and read to the end. "Until it goes quiet"
      must say that an AI agent that asks the Mac to stay awake while it works —
      Claude Code in a terminal does — keeps it on, provided it checks in more
      often than every 30 minutes. "Until I turn it off" must say it is for anything that
      waits longer than 30 minutes between bursts of work. They are the only
      place the app explains the two modes.
- [ ] **Welcome window** (a fresh account, or §1): once set up it says to click
      "Keep awake until I turn it off" — the name of an item that exists.

The detector behind the second item is §12.

## 3. Core — keep awake with the lid closed (the whole point)

On **AC power**, no external display:

- [ ] Start the heartbeat loop (see commands).
- [ ] Menu → **Keep awake until I turn it off** (glyph blue). `pmset -g` shows
      `SleepDisabled 1`.
- [ ] Close the lid for ~2 minutes, then reopen.
- [ ] `tail /tmp/awake.log`: timestamps are **continuous across the closed
      window** (no gap) = it never slept. ✅ core feature.
- [ ] Disarm → `SleepDisabled` back to `0`.

## 4. Screen-off when the lid closes

> The **Turn the screen off** setting was removed — this is unconditional now.
> There was no configuration in which switching it off helped: with an external
> display `handleLidClosed()` returns before it was ever read, and without one it
> only chose whether to light a panel nobody can see.

- [ ] Arm, close the lid with **no external display** → the internal display goes
      dark while the system stays awake (heartbeat keeps ticking).
- [ ] Arm, close the lid **with an external display attached** → BOTH screens are
      left alone by lidawake; the external stays lit and usable. (macOS turns the
      built-in panel off itself in clamshell — that is not lidawake's doing.)

## 5. Lid-open options

> **Lid-open wakefulness is not optional, by design.** While armed,
> `WakeAssertionManager` always holds `PreventUserIdleSystemSleep` ("keep awake
> while armed"); the heartbeat's `.userInitiated` activity holds one too (see
> **E0k** in zayco-site's decision log). The "Let lidawake manage the screen" row
> that looked like a choice here was removed: it had no effect of its own, and only
> unhid the switch below. What is left controls the **screen**, and nothing else.

- [ ] Arm, leave the lid open and idle past the Energy-Saver sleep time → it does
      **not** idle-sleep; `pmset -g assertions` shows "keep awake while armed",
      whatever the switch says.
- [ ] **Keep the screen on** ON: while armed and idle **with the lid open**, the
      **display** also stays on (doesn't dim/sleep).
- [ ] **Keep the screen on** ON, **lid shut in clamshell** on an external monitor,
      on power: the external **sleeps on its normal timer** — `pmset -g assertions`
      shows no "keep the screen on while armed" while the lid is shut, and "keep
      awake while armed" throughout. Open the lid → the screen lock is back. (Before this, the lock was held lid open or shut, and a
      monitor in clamshell never slept.) The logic is covered by the selftest:

      ```sh
      swiftc -O -parse-as-library tools/wakeassertion-selftest.swift \
          Sources/App/WakeAssertionManager.swift Sources/Shared/HelperProtocol.swift \
          -o /tmp/lidawake-wakeassertion-selftest && /tmp/lidawake-wakeassertion-selftest
      ```
- [ ] **Keep the screen on** OFF (default): the screen dims and sleeps as usual; the
      Mac stays awake.
- [ ] Either way, arming still keeps lid-**closed** awake.
- [ ] **An update keeps everyone's screen behaviour.** The migration is covered for
      every stored state by the selftest:

      ```sh
      swiftc -O -parse-as-library tools/settings-selftest.swift Sources/App/Settings.swift \
          -framework AppKit -framework SwiftUI \
          -o /tmp/lidawake-settings-selftest && /tmp/lidawake-settings-selftest
      ```

      One spot check on hardware, the case that changes a stored value: with the
      app quit, `defaults write it.zayco.lidawake keepAwakeLidOpen -bool false` and
      `defaults write it.zayco.lidawake keepScreenOnLidOpen -bool true` (the old
      window showed the screen switch hidden, so the screen was NOT kept on) →
      launch this build → **Keep the screen on** reads OFF, and
      `defaults read it.zayco.lidawake keepAwakeLidOpen` says the key does not exist.

### `disablesleep` vs idle sleep — no longer a product question

E0k asked whether the lid-open row could become a real control of lid-open idle
sleep: fix the heartbeat (`.userInitiated` → `.userInitiatedAllowingIdleSystemSleep`),
then find out whether `pmset disablesleep 1` still blocks idle sleep on its own.
With the row gone, lid-open wakefulness is a promise rather than a setting, and
`WakeAssertionManager` holds its assertion unconditionally — so the heartbeat change
is now a cleanup with no user-visible effect, and the `disablesleep` answer decides
nothing. Still unmeasured; not needed.

## 6. Battery policy

- [ ] Default (battery off): on **battery**, click **Keep awake until I turn it off** → refusal
      alert with an **Open Settings…** button. Clicking it opens the Settings
      window.
- [ ] Enable **Keep going on battery power**: on battery, above the floor, arm →
      it works (glyph blue).
- [ ] Floor, **on battery**: set the floor above the current charge → arm is
      refused with the battery message.
- [ ] Floor, **on AC**: same setting, plugged in and charging → arming
      **succeeds**. The floor guards against exhaustion, which cannot happen while
      charge is going in. (Regression guard: this used to refuse.)
- [ ] *Not forceable without an underpowered adapter:* on AC while the battery is
      genuinely draining, the floor should still apply. Covered in
      `tools/power-selftest.swift` instead.
- [ ] **Live auto-disarm:** with battery OFF in settings, arm on AC, then unplug →
      it auto-disarms and restores sleep, with a notice.
- [ ] **Persistence:** change a setting, quit, relaunch → the setting stuck.

## 7. Safety / restore — must NEVER leave `SleepDisabled 1`

- [ ] **Disarm:** → `SleepDisabled 0`.
- [ ] **Quit while armed:** arm, then Quit lidawake → `SleepDisabled 0`.
- [ ] **Force-kill while armed (dead-man's switch):** arm, then `pkill -9 -x
      lidawake`. Within ~1s `SleepDisabled` returns to `0` (the helper restores it
      when the XPC connection drops).
- [ ] **Power auto-disarm:** §6 live auto-disarm covers this.
- [ ] **Thermal auto-disarm:** by design, `.serious`/`.critical` thermal state
      disarms. Hard to trigger on demand — left as a code-reviewed, runtime-
      unverified path. Note if you ever see it fire.

## 8. Helper lifecycle

### After an update (added 1.4.5) — MUST be run on hardware

This is the bug 1.4.5 fixes, and it only ever appeared on a machine that had not
been tested on.

**Do NOT gate the release on a real Sparkle self-update.** That needs the new
version already published, so it can only ever be a POST-release check — the same
trap that made 1.0.3's pre-ship run use a fake older build against the live
appcast. It is also not what the bug is about: Sparkle's download, signature check
and relaunch are orthogonal. The failure is entirely about what the NEW app
concludes from a STALE daemon, and that state is reproducible in a minute:

1. With the current version running and its helper up, note the helper's start
   time — `ps -o lstart= -p "$(pgrep -x lidawake-helper)"`.
2. Quit lidawake from its menu-bar icon. **Leave the helper running** (KeepAlive
   keeps it up; do not reboot, do not bootout).
3. Replace the bundle in place: `ditto build/lidawake.app /Applications/lidawake.app`
   (admin auth — this is the same swap Sparkle performs).
4. `open /Applications/lidawake.app`, then confirm the helper did NOT restart —
   same PID and start time as step 1. That is the stale-daemon state.

Then, in that state:

- [ ] Open the menu straight after the update relaunch. It must show the normal
      **Off — your Mac will sleep normally** line and a live toggle. It must NEVER
      say "Finish the one-time setup to begin", and **Finish setup…** must not
      appear — that is the entire regression, and the whole point of the release.
- [ ] Click **Keep awake until I turn it off** during that window. It must either arm outright
      or show "Getting lidawake ready…" and then arm. It must not be greyed out,
      and it must not open the Welcome window.
- [ ] Force the unreachable case — toggle lidawake OFF under **Allow in the
      Background** (no admin needed; `sudo launchctl bootout system/it.zayco.lidawake.helper`
      does the same from an admin account) and relaunch the app. The menu still
      shows the normal state; the toggle is still live; clicking it goes through
      "Getting lidawake ready…". No setup UI at any point. This is the closest
      reproduction of the reported failure and the single most important check here.
- [ ] Nothing in the menu ever tells the user to go and enable a Login Items entry
      that is already enabled. If you see that text, the release is not shippable.
- [ ] **Post-release**, once the appcast is live: a real Sparkle self-update from
      the previous version, repeating the first two checks above. Record it in the
      results log either way — this is the confirmation, not the gate.

- [ ] **Self-heal:** after a `SIGN=1` rebuild, `pgrep -lx lidawake-helper` shows
      nothing for up to ~1 min, then the helper reappears on its own.
- [ ] **"Starting up" dialog:** arm during that window → the honest "Try Again"
      dialog (not a dead-end). After the helper is back, **Try Again** arms.
- [ ] **Uninstall:** menu → **Uninstall lidawake…** → confirm. Result:
      `SleepDisabled 0`, helper no longer in `pgrep`, lidawake gone from Login
      Items, settings cleared, app quits. (Then drag the app to Trash.)

## 9. Settings window

- [ ] Opens from menu **Settings…** and with **⌘,** while the window is focused.
- [ ] **Keep going on battery power** ON → a floor stepper and the heat warning
      appear; OFF → they hide.
- [ ] **When the lid is open** holds one switch, **Keep the screen on**, always
      visible.
- [ ] Toggling any switch persists (re-open the window, or relaunch, to confirm).

---

## 10. Version, About & auto-update (added 1.0.1 / 1.0.2)

- [ ] Menu → **About lidawake** shows the icon + correct **Version x.y.z (build)** + copyright.
- [ ] **Live settings** (needs a *signed* build so it can arm): while armed, toggling "Keep the screen on"
      off/on adds/removes the display lock **immediately** (no disarm/re-arm); the system lock stays held
      throughout and `SleepDisabled` stays 1; no spurious disarm across toggles.
      Verify via `pmset -g assertions | grep it.zayco.lidawake`.
- [ ] **First-run "I've turned it on"**: if the helper still isn't enabled, it shows a feedback line (not a
      silent no-op).
- [ ] **Auto-update (Sparkle)**: install an *older* version → **Check for Updates** finds the newer one → the
      dialog shows the **release notes** and has **no "auto-download" checkbox** → Install → it downloads from
      GitHub, verifies the signature, installs, and relaunches at the new version. (The 1.0.0→1.0.1 flow, with
      a fresh version pair.)

> **Release rule:** every release runs the **Quick regression pass** + a test for anything new or changed.
> A release touching **core wake/safety logic** runs this ENTIRE file. For a narrow UI-only patch it's fine to
> skip the heavy physical re-runs (§3 lid-close, §6 battery, §7 thermal) — **as long as you write down that you
> did and why** (core unchanged), in the results log. Risk-based and documented, never silent. Compiling is not
> testing. See the `never-ship-untested` rule.

## 11. Lid warning — the one sound lidawake makes

> Fires when the lid closes while armed **on battery** — with an external display
> attached that is a silent notification only — or when power goes to battery with
> the lid **already shut** (off the dock, into a bag), which **always** sounds, whatever
> is attached. On AC, nothing. The sound is **Hero**,
> played by the app itself, at **60% or louder**: a lower volume is raised to 60% for
> the sound and put back after. The notification is always silent. Only reachable with
> **Keep going on battery power** ON — with it off, going to battery disarms instead.
>
> The volume rules are covered headlessly first — run this before anything below:
>
> ```sh
> swiftc -O -parse-as-library Sources/App/WarningVolume.swift \
>     tools/lidwarning-selftest.swift -o /tmp/lidawake-lidwarning-selftest \
>     && /tmp/lidawake-lidwarning-selftest
> ```

Setup: the signed build in `/Applications`, **Keep going on battery power** ON, armed
in the account you are sitting at (audio from a fast-user-switched background session
is not known to reach the speakers). The helper is shared with the other account —
disarm when done. Read and set the level with `osascript -e 'get volume settings'` /
`osascript -e 'set volume output volume 10'`.

- [ ] **Battery, no display, volume 31%** (an ordinary setting), a TV or music on in
      the room → close the lid → the sound is **audible through the closed lid without
      listening for it**. Open it → "lidawake is still on" is in Notification Center,
      and the volume reads **31** again. (The measurement that set 60%: at 31%
      unraised, with a TV on, it was heard only by someone waiting for it.)
- [ ] **Muted** → no sound; notification present; still muted, level unchanged.
- [ ] **Volume 0, not muted** → no sound; still 0.
- [ ] **Volume 75%** → sound at 75%; level untouched.
- [ ] **Battery, external display** → no sound; banner on the external; entry in
      Notification Center.
- [ ] **AC, no display** → no sound, no notification; the panel still sleeps (§4).
- [ ] **Lid bounce** — close, open, close inside a second → one sound, not two;
      volume back at its level afterwards.
- [ ] **Dock unplug — the bag case.** Clamshell on a dock (or a monitor) that carries
      power AND the display, armed, on AC → pull the cable → **the sound at once**. It
      must not depend on the display leaving: with the lid shut and no display left,
      the CG display list freezes until the lid opens (measured 2026-09-27 — a pulled
      Thunderbolt monitor stayed listed as awake for 20–35 s), which is why the first
      version, which asked it, stayed silent here.
- [ ] **Charger only** — clamshell, display on its own cable → pull just the charger
      → **the sound** too. Accepted cost of the above: nothing reliable can tell this
      apart from the bag case with the lid shut.
- [ ] **Unplug with the lid open** → nothing.
- [ ] **Known gap, check it stays a gap:** on battery, lid shut on a monitor that does
      not charge → unplug the monitor → nothing (no power change; frozen display list).
      Not covered on purpose — the registry reading that sees it also drops when the
      monitor is switched off or changes input (measured 2026-09-27).

The next four need the raise to last long enough to act inside it. Quit lidawake, then
run it from a terminal with the test hook — its `[lidawake]` log lines print there:

```sh
LIDAWAKE_WARNING_HOLD_SECONDS=30 /Applications/lidawake.app/Contents/MacOS/lidawake
```

Each starts the same way: volume 10%, on battery, armed, close the lid (sound plays),
open it again within the 30 s.

- [ ] **Crash** → `pkill -9 -x lidawake` → the level stays at **60** → relaunch → back
      to **10**, and the log says `a lid warning was cut off last run — volume: restored`.
- [ ] **You change it** → set 70% yourself → after the 30 s it is still **70**.
- [ ] **Device switch** → plug in headphones (or pick another output) → after the
      30 s the **speakers** are back at 10 and the headphones' level is untouched.
- [ ] **Quit** → menu → Quit → back at **10** at once.

## 12. "Until it goes quiet" — the detector (added for 1.6.0)

> **What it is.** "Keep awake until it goes quiet" turns lidawake off 30 minutes
> after the last thing it could see: you using the Mac, sound, video, one of your
> programs asking the Mac to stay awake (`caffeinate`, or the same request made
> directly), one of your programs at half a core or more, the graphics chip
> over 50 %, or network traffic over 30 KB/s — the last three as a five-minute
> median, so a spike is not work. macOS's own processes never count as programs
> (their use of the graphics chip can — see "Known" below). Everything
> is read every 30 s; the keep-awake list every 10 s, because an agent's request
> for a short turn lasts barely half a minute. A program in **another user's
> account** that asks counts too, and is never named: it is "a program in
> another account" in the menu, the notice and the log. (Root's are named — a
> root daemon is nobody's private app.) A signal that cannot be read
> counts as activity. The header of `Sources/App/IdleWatcher.swift` is the short
> version; `Sources/App/ActivitySignals.swift` says exactly what is read and what
> is thrown away.
>
> **Every number behind it was measured on macOS 27.0.1**, and two of its reads
> are not public API: the GPU statistic, and the assertion table's
> `AssertionTrueType`. **Re-run "What it reads" below after every macOS update.**
> If either read breaks it shows `??`, counts as activity, and the detector
> simply never fires — the safe way to break, and invisible unless someone looks.

**The rule and its two classifiers — no hardware:**

```sh
swiftc -O -parse-as-library Sources/App/IdleWatcher.swift Sources/App/ArmMode.swift \
    tools/idlewatcher-selftest.swift -o /tmp/lidawake-idle-selftest && /tmp/lidawake-idle-selftest
tools/idlewatcher-mutations.sh    # breaks each rule on a copy; every one must be "caught"
```

**What it reads, live** — the app's own readers and rule in a terminal. It turns
nothing on or off; it prints what quiet mode would see and when it would stop:

```sh
swiftc -O -parse-as-library Sources/App/IdleWatcher.swift Sources/App/ActivitySignals.swift \
    tools/activity-probe.swift -o /tmp/lidawake-activity-probe
/tmp/lidawake-activity-probe                              # the real 30 minutes, a line every 30 s
LIDAWAKE_IDLE_SECONDS=120 /tmp/lidawake-activity-probe    # 2 minutes, a line every 2 s
```

Between two lines it looks at the keep-awake list twice more, as the app does,
and prints `asks: …` only when somebody is asking.

- [ ] No column ever shows `??`.
- [ ] `input` climbs while you keep your hands off and drops to ~0 when you
      touch a key or the trackpad.
- [ ] Play a song → `sound YES` within a tick. **Pause** → `no` within a tick or two.
- [ ] A video in QuickTime → `video QuickTime Player`. A muted video in Firefox
      → `video firefox`.
- [ ] `caffeinate -i -t 40` in another terminal → `asks: zsh` on every look for
      40 seconds, and "last: zsh asking the Mac to stay awake". Give Claude Code,
      in a terminal, something to do → `asks: claude` from the first second of
      the turn until about half a minute after it ends, and nothing while it
      sits at its prompt. The same task through `claude -p` shows nothing at
      all; as `caffeinate -i claude -p …` it shows for as long as it runs.
- [ ] `yes > /dev/null` in another terminal for six minutes (2-minute window:
      twenty seconds) → `programs: yes 1.00`, then "last: yes working". Ctrl-C it.
- [ ] Hands off, nothing running → "WOULD TURN OFF NOW", with a sentence naming
      the last activity and the time.

> ⚠ **The test hook rewrites what the user reads.** `LIDAWAKE_IDLE_SECONDS`
> shortens the window, and the minute count in the status line, the tooltip and
> the "turned itself off" message is derived from the window — so under the hook
> they say "2 minutes". A screenshot taken that way shows text no shipped build
> produces.

**The hardware pass** — the signed test build over the shared install (how, and
how to put it back, is in the results log for 1.5.0). Launch it from Terminal
with `LIDAWAKE_IDLE_SECONDS=300` to keep each run to minutes, and once at the
real 30 for E9a. (A lid-shut spell shorter than five minutes gets no "Awake …"
line in the notice — that is the wake summary's own rule, not a fault of a
short window.) Take the Mac's sleep state from `pmset -g log`, never from the
app's own account of itself.

- [ ] **E9a — it turns off, lid shut on a monitor.** "Keep the screen on" **ON**
      in Settings, on **battery**, quiet mode, nothing running, hands off. →
      Off at the window; `pmset -g log` shows `Clamshell Sleep` seconds later;
      on opening the lid, the notice names the last activity and the time.
- [ ] **E9b — lid shut, no display.** Same, with no monitor attached. With
      battery use on, the lid warning sounds as the lid shuts — and **the notice
      afterwards must not name it**: it says what happened before the warning
      ("you using the Mac"), never "sound playing" for a sound nobody played.
- [ ] **E9c — lid open.** Same, lid open on AC → off at the window, glyph back
      to monochrome, a notice with no "Awake …" line.
- [ ] **E2 — it does not turn off under your hands.** Lid shut on a monitor, on
      battery, typing in a document for longer than the window → still on.
- [ ] **E4 — work holds it, and lets go after.** One at a time: a download; a
      compile (`./build.sh` in a loop); a local model run in Ollama. Each stays
      on for as long as it runs and turns off one window after it ends, naming
      it — "network traffic", "‹the tool› working", "the graphics chip busy".
- [ ] **E13 — an AI agent running in a loop.** Quiet mode at the **real** 30
      minutes; `/tmp/lidawake-activity-probe > ~/Desktop/e13.log` in one
      terminal; Claude Code in another, **with any `Stop`-hook sound switched
      off** (below). Two runs, hands off for each:
      - **A loop that checks every few minutes** (`/loop 6m …`), 45 minutes →
        **still on.** The log shows `asks: claude` for about half a minute at
        each check and nothing between; the menu, opened during a check, reads
        "(kept on by claude)".
      - **A loop that waits longer than the window** (`/loop 1h …`, "This
        session only" — `/loop` rounds odd intervals, and 35 minutes can become
        30) → **off about 30 minutes after its first check**, the notice saying
        "The last thing it saw was claude asking the Mac to stay awake".

      With lidawake in one account and the agent in another, every "claude"
      above reads **"a program in another account"** — the rule, not a fault.
      If either run goes the other way, the tooltips and the CHANGELOG are
      wrong and get corrected before release.

      *The sound.* A `Stop` hook that plays a chime trips the **sound** signal
      at about one check in ten (E13a: the chime lasts ~3 s) — enough to keep
      the second run on at random and have it name "sound playing". It is set
      in `~/.claude/settings.json` under `hooks` → `Stop` of the account the
      agent runs in; take the entry out for the run and put it back after, and
      start the agent's session after the change.
- [ ] **E7 — every guard, in both modes.** Thermal, battery floor, unplug with
      battery use off, force-quit (§7) behave identically whether the glyph is
      blue or green.

**Known, and not bugs** (they are named to the user where it matters): an agent
in a loop that waits longer than 30 minutes between checks is stopped, and so
is one that never asks the Mac to stay awake — which includes Claude Code run
headless (`claude -p`) or from the VS Code panel; it asks only in a terminal,
and no other agent was measured (spec §11.6.6); a
program that holds a keep-awake request and never lets go keeps it on for as
long as it does, and the status line names it; a muted video in Chrome, Edge, Brave, Arc or Comet is not
seen (QuickTime, Firefox and Safari are); work under another account or as root
is not seen unless it uses sound, the network or the GPU, or asks the Mac to
stay awake; CPU-only work inside
Apple's built-in apps is not seen; and macOS's media analysis using the GPU can
keep it on longer than it should, in which case the notice says "the graphics
chip busy".

## Quick regression pass (after any code change)

- [ ] `SIGN=1 ./build.sh` is clean and verifies.
- [ ] `tools/lidwarning-selftest.swift` → ALL PASS (command in §11).
- [ ] `tools/settings-selftest.swift` → ALL PASS (command in §5).
- [ ] `tools/wakeassertion-selftest.swift` → ALL PASS (command in §5).
- [ ] `tools/idlewatcher-selftest.swift` → all checks pass, and `tools/idlewatcher-mutations.sh`
      → every mutation caught (commands in §12).
- [ ] Arm on AC → `SleepDisabled 1`; disarm → `0`.
- [ ] Glyph goes blue / green / mono with the mode; the checkmark tracks it;
      switching modes while on leaves `SleepDisabled 1`.
- [ ] Quit while armed → `SleepDisabled 0`.
- [ ] A copy running outside `/Applications` does not stop the `/Applications`
      copy from starting (see section 1).
