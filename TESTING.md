# lidawake — manual test plan

How to verify the app does what it should. Work top to bottom; each section is
independent. Check the box when it passes. "Core" tests are must-pass before any
release; the rest are good coverage.

> Why manual: the product is a physical-behaviour app (closing the lid, pulling
> power). Most of it can't be unit-tested — it has to be exercised on a real Mac.

## Results log

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

## Quick regression pass (after any code change)

- [ ] `SIGN=1 ./build.sh` is clean and verifies.
- [ ] Arm on AC → `SleepDisabled 1`; disarm → `0`.
- [ ] Glyph goes blue/mono with state; menu checkmark tracks state.
- [ ] Quit while armed → `SleepDisabled 0`.
