#!/bin/zsh
# E4 on hardware — work holds quiet mode on, and it lets go after (TESTING.md §12).
#
# Run DETACHED, with lidawake launched under LIDAWAKE_IDLE_SECONDS=300 and OFF, so
# nobody's terminal session is part of what is measured:
#
#   nohup tools/hw-e4-work-holds-it.sh >/dev/null 2>&1 </dev/null &
#
# Three kinds of work, one after another, each LONGER than the window — so during
# each one, that work is the only thing that can be holding lidawake on:
#
#   a download   7 min   rate-limited to 300 KB/s: network and nothing else
#   a compile    7 min   ./build.sh in a loop, in a scratch copy of the source
#   a model run  7 min   local generation through Ollama
#
# then nothing, until lidawake turns itself off (expected about one window after
# the model run ends). A sampler logs, every 5 s, the sleep setting, how long ago
# anyone touched the Mac, which assertions lidawake holds, and whether any Claude
# Code session was asking the Mac to stay awake — which would void the run.
#
# It waits until the Mac has been untouched for 30 s and no agent is working,
# then turns quiet mode on ITSELF (by clicking lidawake's own menu item through
# Accessibility) and refuses to go on if that did not take. The first version
# trusted that lidawake was already on; it had turned itself off — correctly,
# five quiet minutes had passed — and 21 minutes of work were measured against
# nothing (2026-10-04).
set -u
H=${LIDAWAKE_RESEARCH_LOGS:-/Users/Shared/lidawake-research}
LOG=$H/hw-e4.log
SRC=${E4_SRC:?a scratch copy of the lidawake source to compile in}
URL=${E4_URL:-https://ash-speed.hetzner.com/1GB.bin}
MODEL=${E4_MODEL:-qwen3-coder:30b}
PHASE_S=${E4_PHASE_SECONDS:-390}
PHASEFILE=$H/hw-e4.phase
START=$(date +%s)

say()  { echo "$(date '+%H:%M:%S') $*" >> $LOG }
sd()   { pmset -g | awk '/SleepDisabled/{print $2}' }
idle() { ioreg -c IOHIDSystem | awk '/HIDIdleTime/ {print int($NF/1000000000); exit}' }
agents() { ps -axo ppid=,comm= | awk '$2 ~ /caffeinate$/ {print $1}' | while read -r pp; do ps -o comm= -p $pp 2>/dev/null; done | grep -c -i 'claude' }
locks() { pmset -g assertions | grep 'it.zayco.lidawake' | sed 's/.*named: "it.zayco.lidawake: //; s/".*//' | tr '\n' ';' }
# lidawake's own controls, by name, through Accessibility. Not keystrokes, and not HID
# input: the "you using the Mac" signal does not see them.
menu_click() { osascript - "$1" <<'OSA' 2>&1
on run argv
    tell application "System Events" to tell process "lidawake"
        set mbi to menu bar item 1 of menu bar 2
        perform action "AXPress" of mbi
        delay 0.5
        perform action "AXPress" of (menu item (item 1 of argv) of menu 1 of mbi)
    end tell
end run
OSA
}

: > $LOG; echo waiting > $PHASEFILE
say "E4 driver started — macOS $(sw_vers -productVersion), lid shut: $(ioreg -r -k AppleClamshellState -d 4 | grep -m1 AppleClamshellState | sed 's/.*= //'), power: $(pmset -g batt | head -1 | sed "s/.*'\(.*\)'.*/\1/")"

( while [[ -f $PHASEFILE ]]; do
    echo "$(date '+%H:%M:%S') S sleepdisabled=$(sd) idle=$(idle)s agents=$(agents) locks=[$(locks)] phase=$(cat $PHASEFILE 2>/dev/null)" >> $LOG
    sleep 5
  done ) &

for i in {1..600}; do (( $(idle) >= 30 && $(agents) == 0 )) && break; sleep 2; done
say "quiet Mac: idle $(idle)s, agents $(agents), SleepDisabled $(sd)"
[[ $(sd) == 1 ]] || { menu_click "Keep awake until it goes quiet" >/dev/null; sleep 3 }
if [[ $(sd) != 1 ]]; then
  say "ABORTED: quiet mode could not be turned on (SleepDisabled $(sd)). Nothing was measured."
  rm -f $PHASEFILE; exit 1
fi
[[ "$(defaults read it.zayco.lidawake keepScreenOnLidOpen 2>/dev/null)" == 1 ]] || say "NOTE: 'Keep the screen on' is off — the monitor check needs it on"
say "quiet mode is on (SleepDisabled 1), 'Keep the screen on' = $(defaults read it.zayco.lidawake keepScreenOnLidOpen 2>/dev/null) — starting"

phase() {   # name, command…
  local name=$1; shift
  echo $name > $PHASEFILE; say "PHASE $name begins"
  local end=$(( $(date +%s) + PHASE_S ))
  while (( $(date +%s) < end )); do "$@" $(( end - $(date +%s) )); done
  say "PHASE $name ends — SleepDisabled $(sd)"
}
download() { curl -s --limit-rate 300k --max-time $1 -o /dev/null "$URL"; sleep 1 }
compile()  { ( cd $SRC && ./build.sh >/dev/null 2>&1 ) }
model()    { curl -s --max-time $1 http://127.0.0.1:11434/api/generate -d "{\"model\":\"$MODEL\",\"prompt\":\"Write a very long, detailed technical essay on the history of operating systems. Do not stop early.\",\"stream\":false,\"options\":{\"num_predict\":4000}}" >/dev/null; sleep 1 }

phase download download
phase compile  compile
phase model    model
curl -s http://127.0.0.1:11434/api/generate -d "{\"model\":\"$MODEL\",\"keep_alive\":0}" >/dev/null   # unload it

echo quiet > $PHASEFILE; say "PHASE quiet begins — nothing running; waiting for lidawake to turn itself off"
QUIET0=$(date +%s)
for i in {1..450}; do [[ $(sd) == 0 ]] && break; sleep 2; done
if [[ $(sd) == 0 ]]; then say "TURNED OFF $(( $(date +%s) - QUIET0 )) s after the work ended"
else say "STILL ON $(( $(date +%s) - QUIET0 )) s after the work ended — gave up waiting"; fi

echo done > $PHASEFILE; sleep 6; rm -f $PHASEFILE
say "power log since the start (display and sleep events):"
pmset -g log | awk -v s="$(date -r $START '+%Y-%m-%d %H:%M:%S')" '$1" "$2 >= s' | grep -E 'Display is turned|Entering Sleep|Wake from|Clamshell' | cut -c1-150 >> $LOG
say "finished"
