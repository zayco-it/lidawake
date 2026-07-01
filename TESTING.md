# lidawake — manual test plan

How to verify the app does what it should. Work top to bottom; each section is
independent. Check the box when it passes. "Core" tests are must-pass before any
release; the rest are good coverage.

> Why manual: the product is a physical-behaviour app (closing the lid, pulling
> power). Most of it can't be unit-tested — it has to be exercised on a real Mac.

## Results log

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

- [ ] Menu shows **Finish setup…**, and **Keep my Mac awake** is greyed out.
- [ ] Status line reads "Finish the one-time setup to begin".
- [ ] Click **Finish setup…** (or **Keep my Mac awake**) → System Settings opens
      to Login Items.
- [ ] Approve lidawake under **Allow in the Background** (admin prompt on this
      Standard account is expected).
- [ ] Reopen the menu → **Keep my Mac awake** is now enabled, **Finish setup…**
      is gone.

## 2. Menu-bar glyph & menu state

- [ ] **Off:** monochrome laptop glyph; menu item unchecked; status "Off — your
      Mac will sleep normally".
- [ ] **On:** laptop glyph turns **blue**; menu item shows a checkmark; status
      "On — you can close the lid".

## 3. Core — keep awake with the lid closed (the whole point)

On **AC power**, no external display:

- [ ] Start the heartbeat loop (see commands).
- [ ] Menu → **Keep my Mac awake** (glyph blue). `pmset -g` shows
      `SleepDisabled 1`.
- [ ] Close the lid for ~2 minutes, then reopen.
- [ ] `tail /tmp/awake.log`: timestamps are **continuous across the closed
      window** (no gap) = it never slept. ✅ core feature.
- [ ] Disarm → `SleepDisabled` back to `0`.

## 4. Screen-off when the lid closes

- [ ] Setting **Turn the screen off** ON (default): arm, close lid → the internal
      display goes dark while the system stays awake (heartbeat keeps ticking).
- [ ] Setting OFF: arm, close lid → display stays lit. (Turn it back on after.)

## 5. Lid-open options

- [ ] **Also keep my Mac awake** ON (default): arm, leave the lid open and idle
      past the Energy-Saver sleep time → it does **not** idle-sleep.
- [ ] **Keep the screen on too** ON: while armed and idle, the **display** also
      stays on (doesn't dim/sleep).
- [ ] Both OFF: arming still keeps lid-**closed** awake, but with the lid open the
      Mac idles/sleeps normally.

## 6. Battery policy

- [ ] Default (battery off): on **battery**, click **Keep my Mac awake** → refusal
      alert with an **Open Settings…** button. Clicking it opens the Settings
      window.
- [ ] Enable **Keep going on battery power**: on battery, above the floor, arm →
      it works (glyph blue).
- [ ] Floor: set the floor above the current charge → arm is refused with the
      battery message.
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
- [ ] **Also keep my Mac awake** ON → **Keep the screen on too** appears; OFF → it
      hides.
- [ ] Toggling any switch persists (re-open the window, or relaunch, to confirm).

---

## 10. Version, About & auto-update (added 1.0.1 / 1.0.2)

- [ ] Menu → **About lidawake** shows the icon + correct **Version x.y.z (build)** + copyright.
- [ ] **Live settings** (needs a *signed* build so it can arm): while armed, toggling "Keep the screen on
      too" off/on adds/removes the display lock **immediately** (no disarm/re-arm); toggling "Also keep my Mac
      awake" off drops both lid-open locks while `SleepDisabled` stays 1; no spurious disarm across toggles.
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

## Quick regression pass (after any code change)

- [ ] `SIGN=1 ./build.sh` is clean and verifies.
- [ ] Arm on AC → `SleepDisabled 1`; disarm → `0`.
- [ ] Glyph goes blue/mono with state; menu checkmark tracks state.
- [ ] Quit while armed → `SleepDisabled 0`.
