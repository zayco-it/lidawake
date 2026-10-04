#!/bin/zsh
# Break each rule of the quiet detector on purpose, on a copy, and confirm the
# selftest notices. A check that cannot fail is not a check; this is how the
# claim "mutation-checked" at the top of idlewatcher-selftest.swift stays true.
#
#   tools/idlewatcher-mutations.sh          # from the repo root; ~2 minutes
#
# Each line: a label, the file, and a sed expression that plants one bug. A
# mutation that does not apply (the source moved) is reported as such — fix the
# expression, do not delete the line. Exit status 1 if any mutation survives.
set -u
cd "$(dirname "$0")/.."
M=$(mktemp -d)
survived=0

mut () {   # label, file under Sources/App, sed expression
  cp Sources/App/IdleWatcher.swift Sources/App/ArmMode.swift tools/idlewatcher-selftest.swift "$M"/
  sed -i '' -e "$3" "$M/$2"
  if cmp -s "$M/$2" "Sources/App/$2"; then print -r -- "  NOT APPLIED  $1 — the sed no longer matches"; survived=1; return; fi
  if ! swiftc -O -parse-as-library "$M"/IdleWatcher.swift "$M"/ArmMode.swift "$M"/idlewatcher-selftest.swift -o "$M"/t 2>/dev/null; then
    print -r -- "  caught       $1 — does not compile"; return
  fi
  local n first
  n=$("$M"/t | grep -c '  FAIL')
  first=$("$M"/t | grep -m1 '  FAIL' | sed 's/  FAIL  //; s/  .*//')
  if (( n > 0 )); then print -r -- "  caught       $1 — $n check(s), first: $first"
  else print -r -- "  SURVIVED     $1"; survived=1; fi
}

print -r -- "mutations (each must be caught):"
mut "an unreadable input read as nothing"        IdleWatcher.swift 's/else { note(.unreadable(.presence, at: now)) }/else { }/'
mut "an unreadable load signal read as nothing"  IdleWatcher.swift 's/guard let value else { return (w, .unreadable(signal, at: now)) }/guard let value else { return (w, nil) }/'
mut "an unreadable program list read as nothing" IdleWatcher.swift 's/            note(.unreadable(.program, at: now))/            _ = now/'
mut "window >= became >"                         IdleWatcher.swift 's/quietAge(at: now) >= thresholds.quietWindow/quietAge(at: now) > thresholds.quietWindow/'
mut "median became mean"                         IdleWatcher.swift 's|return n % 2 == 1 ? s\[n / 2\] : (s\[n / 2 - 1\] + s\[n / 2\]) / 2|return s.reduce(0, +) / Double(n)|'
mut "minimumSamples ignored"                     IdleWatcher.swift 's/guard count >= minimum, let m = median/guard let m = median/'
mut "note() may move backwards"                  IdleWatcher.swift 's/if let old = last\[a.signal\], old.at > a.at { return }//'
mut "tie goes to the later signal"               IdleWatcher.swift 's/(a.at, b.signal) < (b.at, a.signal)/(a.at, a.signal) < (b.at, b.signal)/'
mut "program windows never decay"                IdleWatcher.swift 's/for program in programs.keys where cores\[program\] == nil { programs\[program\]?.add(0) }//'
mut "sound: any holder of the type"              IdleWatcher.swift 's/rows.contains { $0.process == "coreaudiod" \&\& $0.trueType == systemSleep }/rows.contains { $0.process != "powerd" \&\& $0.trueType == systemSleep }/'
mut "sound: coreaudiod holding anything"         IdleWatcher.swift 's/rows.contains { $0.process == "coreaudiod" \&\& $0.trueType == systemSleep }/rows.contains { $0.process == "coreaudiod" }/'
mut "video: own pid is the only exclusion"       IdleWatcher.swift 's/            \&\& r.pid != ownPid \&\& r.process != "lidawake" \&\& !r.name.hasPrefix(ownPrefix) {/            \&\& r.pid != ownPid {/'
mut "video: our own pid not excluded"            IdleWatcher.swift 's/            \&\& r.pid != ownPid \&\& r.process != "lidawake" \&\& !r.name.hasPrefix(ownPrefix) {/            \&\& r.process != "lidawake-x" \&\& !r.name.hasPrefix("zz") {/'
mut "Apple .app bundles counted as work"         IdleWatcher.swift 's|static let systemPrefixes = \["/System/", "/usr/libexec/", "/usr/sbin/", "/sbin/", "/Library/Apple/"\]|static let systemPrefixes = ["/System/Library/", "/usr/libexec/", "/usr/sbin/", "/sbin/"]|'
mut "an orphaned job treated as macOS's own"     IdleWatcher.swift 's|static let systemPrefixes = \["/System/", "/usr/libexec/", "/usr/sbin/", "/sbin/", "/Library/Apple/"\]|static let systemPrefixes = ["/System/", "/usr/", "/opt/", "/sbin/", "/Library/Apple/"]|'
mut "a terminal's child judged by its path"      IdleWatcher.swift 's/        if ppid != 1 { return true } .*$/        _ = ppid/'
mut "switching modes arms the helper"            ArmMode.swift     's/return ModeTransition(mode: item, helper: .none,/return ModeTransition(mode: item, helper: .arm,/'
mut "the loop sentence dropped from one tooltip" ArmMode.swift     's/an AI agent running in a loop belongs here\./this is the one that never stops by itself./'
mut "the loop sentence dropped from the other"   ArmMode.swift     's/An AI agent running in a loop looks quiet between its checks and would be stopped/Some things look quiet and would be stopped/'

rm -rf "$M"
(( survived == 0 )) && print -- "\nevery mutation was caught" || { print -- "\nSOME MUTATIONS SURVIVED OR DID NOT APPLY"; exit 1; }
