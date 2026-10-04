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
mut "ours: known by our own pid only"            IdleWatcher.swift 's/        r.pid == ownPid || r.process == "lidawake" || r.name.hasPrefix(ownPrefix)/        r.pid == ownPid/'
mut "ours: our own pid not known"                IdleWatcher.swift 's/        r.pid == ownPid || r.process == "lidawake" || r.name.hasPrefix(ownPrefix)/        r.process == "lidawake-x" || r.name.hasPrefix("zz")/'
mut "video: lidawake's own screen request counted" IdleWatcher.swift 's/for r in rows where r.trueType == displaySleep \&\& !isOurs(r, ownPid: ownPid) {/for r in rows where r.trueType == displaySleep {/'
mut "request: lidawake's own request counted"    IdleWatcher.swift 's/for r in rows where requestTypes.contains(r.trueType) \&\& !isOurs(r, ownPid: ownPid) {/for r in rows where requestTypes.contains(r.trueType) {/'
mut "request: macOS's own holders counted"       IdleWatcher.swift 's/            guard WorkRule.isWork(path: p.path, ppid: p.ppid) else { continue }//'
mut "request: a display request counted too"     IdleWatcher.swift 's/static let requestTypes: Set<String> = \[systemSleep, "PreventSystemSleep"\]/static let requestTypes: Set<String> = [systemSleep, displaySleep, "PreventSystemSleep"]/'
mut "request: caffeinate -s not counted"         IdleWatcher.swift 's/static let requestTypes: Set<String> = \[systemSleep, "PreventSystemSleep"\]/static let requestTypes: Set<String> = [systemSleep]/'
mut "request: caffeinate named as itself"        IdleWatcher.swift 's/            if p.path == caffeinate, p.ppid > 1, let parent = lookup(p.ppid) { who = (parent.path, parent.name) }//'
mut "request: another account's program named"   IdleWatcher.swift 's/            guard p.uid == ownUid || p.uid == 0 else { other = true; continue }//'
mut "request: another account's not counted"     IdleWatcher.swift 's/            guard p.uid == ownUid || p.uid == 0 else { other = true; continue }/            guard p.uid == ownUid || p.uid == 0 else { continue }/'
mut "request: root's holder left unnamed"        IdleWatcher.swift 's/            guard p.uid == ownUid || p.uid == 0 else { other = true; continue }/            guard p.uid == ownUid else { other = true; continue }/'
mut "a name cut at 16 bytes left cut"            IdleWatcher.swift 's/        return leaf$/        return comm/'
mut "request: an unreadable list read as nothing" IdleWatcher.swift 's/        else { note(.unreadable(.request, at: now)) }//'
mut "request: the list read only on the tick"    IdleWatcher.swift 's/        else if !fired { policy?.observeRequests(source.readRequests(), at: now) }//'
mut "request: every look is a full tick"         IdleWatcher.swift 's/        if looks % Self.requestReadsPerTick == 0 { tick(at: now) }/        if looks % 1 == 0 { tick(at: now) }/'
mut "request: the holder forgotten once named"   IdleWatcher.swift 's/        heldBy = holders?.first/        heldBy = holders?.first ?? heldBy/'
mut "request: ties behind the CPU it came with"  IdleWatcher.swift 's/case presence, audio, video, request, program, graphics, network/case presence, audio, video, program, request, graphics, network/'
mut "the status line silent about the holder"    ArmMode.swift     's/if let heldBy { age = "kept on by \\(heldBy)" }/if let heldBy, heldBy.isEmpty { age = "" }/'
mut "Apple .app bundles counted as work"         IdleWatcher.swift 's|static let systemPrefixes = \["/System/", "/usr/libexec/", "/usr/sbin/", "/sbin/", "/Library/Apple/"\]|static let systemPrefixes = ["/System/Library/", "/usr/libexec/", "/usr/sbin/", "/sbin/"]|'
mut "an orphaned job treated as macOS's own"     IdleWatcher.swift 's|static let systemPrefixes = \["/System/", "/usr/libexec/", "/usr/sbin/", "/sbin/", "/Library/Apple/"\]|static let systemPrefixes = ["/System/", "/usr/", "/opt/", "/sbin/", "/Library/Apple/"]|'
mut "a terminal's child judged by its path"      IdleWatcher.swift 's/        if ppid != 1 { return true } .*$/        _ = ppid/'
mut "switching modes arms the helper"            ArmMode.swift     's/return ModeTransition(mode: item, helper: .none,/return ModeTransition(mode: item, helper: .arm,/'
mut "the long-wait sentence dropped from one tooltip" ArmMode.swift 's/Use this for anything that waits longer than/Use this whenever you like, even for longer than/'
mut "the agent sentence dropped from the other"  ArmMode.swift     's/An AI agent that asks the Mac to stay awake while it works/Something that asks the Mac to stay awake while it works/'
mut "the quiet tooltip promises every agent"     ArmMode.swift     's/ \\u{2014} Claude Code does \\u{2014} / /'

rm -rf "$M"
(( survived == 0 )) && print -- "\nevery mutation was caught" || { print -- "\nSOME MUTATIONS SURVIVED OR DID NOT APPLY"; exit 1; }
