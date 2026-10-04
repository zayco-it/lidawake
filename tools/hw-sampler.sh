#!/bin/zsh
# Hardware-pass sampler: what the Mac and lidawake were doing, every 2 s, written
# where both accounts can read it. Run DETACHED before a hands-on block, so that
# no terminal session has to work while the block runs:
#
#   nohup tools/hw-sampler.sh <name> [seconds] >/dev/null 2>&1 </dev/null &
#
# One line per sample: the sleep setting, lid, power source and charge, seconds
# since anyone touched the Mac, the assertions lidawake holds (and which account's
# lidawake holds them), and whether any Claude Code session is asking the Mac to
# stay awake. Stop it early with:  rm /Users/Shared/lidawake-research/<name>.run
set -u
H=${LIDAWAKE_RESEARCH_LOGS:-/Users/Shared/lidawake-research}
NAME=${1:?a name for the log}; SECS=${2:-3600}
LOG=$H/$NAME.log; RUN=$H/$NAME.run
: > $LOG; touch $RUN
END=$(( $(date +%s) + SECS ))
while [[ -f $RUN ]] && (( $(date +%s) < END )); do
  sd=$(pmset -g | awk '/SleepDisabled/{print $2}')
  lid=$(ioreg -r -k AppleClamshellState -d 4 | grep -m1 AppleClamshellState | sed 's/.*= //')
  batt=$(pmset -g batt)
  src=$(echo $batt | head -1 | sed "s/.*'\(.*\)'.*/\1/"); pct=$(echo $batt | grep -o '[0-9]*%' | head -1)
  idle=$(ioreg -c IOHIDSystem | awk '/HIDIdleTime/ {print int($NF/1000000000); exit}')
  locks=$(pmset -g assertions | grep 'it.zayco.lidawake' | sed -E 's/.*pid ([0-9]+)\(.*named: "it.zayco.lidawake: ([^"]*)".*/\1:\2/' | while IFS=: read -r pid what; do echo -n "$(ps -o user= -p $pid 2>/dev/null | tr -d ' ')/$what;"; done)
  agents=$(ps -axo ppid=,comm= | awk '$2 ~ /caffeinate$/ {print $1}' | while read -r pp; do ps -o comm= -p $pp 2>/dev/null; done | grep -c -i claude)
  echo "$(date '+%H:%M:%S') sleepdisabled=$sd lid_shut=$lid power=${src// /_} charge=$pct idle=${idle}s agents=$agents locks=[$locks]" >> $LOG
  sleep 2
done
rm -f $RUN
