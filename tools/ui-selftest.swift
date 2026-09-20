// Headless self-test for text wrapping in the SwiftUI windows. Reads the REAL
// sources — so it checks the shipping code, not a copy — and needs no GUI, no
// window server and no Accessibility permission. Dev-only; NOT part of the app build.
//
//   swiftc -O tools/ui-selftest.swift -framework AppKit \
//       -o /tmp/lidawake-ui-selftest && /tmp/lidawake-ui-selftest
//
// WHY THIS EXISTS
//
// A `Text` inside a `VStack` that has `.frame(width:)` applied to the STACK does
// not wrap. The stack sizes its children at their ideal width first — and a
// Text's ideal width is its full single-line width — then the outer frame
// truncates whatever overflows. The frame never tells the Text to wrap. The
// remedy is `.fixedSize(horizontal: false, vertical: true)`, which pins the
// Text's height to its wrapped height instead.
//
// This was found and fixed in Preparing.swift in 1.1.7 ("fix Getting-ready window
// text clipping") and never crossed to Onboarding.swift or LicenseWindow.swift,
// which have the identical shape. Six lines shipped truncated for eight releases,
// including the licence-activation error — the one a paying customer reads when
// their key will not take.
//
// WHY IT CHECKS SOURCE AND NOT PIXELS
//
// Two rendering-based designs were tried and both fail, so do not re-derive them:
//   * `NSHostingView.fittingSize` is IDENTICAL truncated vs wrapped (measured:
//     455.5 either way). A truncated line keeps its layout slot; only the drawing
//     differs. A height snapshot detects nothing.
//   * SwiftUI composites into one layer, so there are no per-Text NSViews to walk
//     in-process. Only an out-of-process Accessibility query sees the real frames,
//     which needs a granted permission and a running window server.
// Measuring the string instead correlates exactly with what Accessibility reports
// — matched on ten strings, e.g. 328.2 computed vs 328 rendered.

import AppKit

// Content width = the outer .frame(width:) minus .padding() on both sides.
let files = ["Sources/App/Onboarding.swift",
             "Sources/App/LicenseWindow.swift",
             "Sources/App/Preparing.swift"]

let styles: [String: NSFont.TextStyle] = [
    "largeTitle": .largeTitle, "title": .title1, "title2": .title2, "title3": .title3,
    "headline": .headline, "subheadline": .subheadline, "body": .body,
    "callout": .callout, "footnote": .footnote, "caption": .caption1, "caption2": .caption2,
]

/// Turn `\u{2019}` escapes into real characters so widths are measured honestly.
func decode(_ s: String) -> String {
    var out = "", i = s.startIndex
    while i < s.endIndex {
        if s[i] == "\\", let o = s[i...].range(of: "\\u{"), o.lowerBound == i,
           let close = s[o.upperBound...].firstIndex(of: "}"),
           let v = UInt32(s[o.upperBound..<close], radix: 16), let u = Unicode.Scalar(v) {
            out.append(Character(u)); i = s.index(after: close)
        } else { out.append(s[i]); i = s.index(after: i) }
    }
    return out
}

/// The outer frame width and padding of a view file.
func geometry(_ src: String) -> (width: CGFloat, padding: CGFloat) {
    var widest: CGFloat = 0, pad: CGFloat = 0
    for line in src.split(separator: "\n") {
        if let r = line.range(of: "\\.frame\\(width: [0-9]+", options: .regularExpression),
           let n = Double(line[r].dropFirst(".frame(width: ".count)) { widest = max(widest, n) }
        if let r = line.range(of: "\\.padding\\([0-9]+\\)", options: .regularExpression),
           let n = Double(line[r].dropFirst(".padding(".count).dropLast()), n >= 10 { pad = max(pad, n) }
    }
    return (widest, pad)
}

struct Row { let file: String, text: String, font: NSFont.TextStyle
             let dynamic: Bool, fixed: Bool, line: Int }

/// Collect every `Text(...)` with the modifier chain that follows it. The house
/// style puts each modifier on a continuation line beginning with `.`, so the
/// chain is "this line, plus following lines whose first character is a dot".
func rows(_ path: String) -> [Row] {
    guard let src = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
    let lines = src.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    var out: [Row] = []
    for (i, line) in lines.enumerated() {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.contains("Text("), !t.hasPrefix("//") else { continue }
        // A Text( argument may span lines (a ternary, say), so consume until its
        // parentheses balance — counting only those outside string literals —
        // and then keep taking continuation lines that begin with a modifier dot.
        func netDepth(_ s: String) -> Int {
            var depth = 0, inString = false, escaped = false
            for c in s {
                if escaped { escaped = false; continue }
                if c == "\\" { escaped = true; continue }
                if c == "\"" { inString.toggle(); continue }
                if inString { continue }
                if c == "(" { depth += 1 } else if c == ")" { depth -= 1 }
            }
            return depth
        }
        var chunk = line, j = i + 1
        var depth = netDepth(line.components(separatedBy: "Text(").dropFirst().joined(separator: "Text(")) + 1
        while j < lines.count, depth > 0 {
            chunk += "\n" + lines[j]; depth += netDepth(lines[j]); j += 1
        }
        while j < lines.count, lines[j].trimmingCharacters(in: .whitespaces).hasPrefix(".") {
            chunk += "\n" + lines[j]; j += 1
        }
        // Pull every string literal out of the whole Text(...) expression. A
        // ternary BETWEEN literals is still statically knowable — measure its
        // longest branch rather than calling it unbounded, or every two-state
        // message in Preparing.swift reports a false alarm.
        guard let open = chunk.range(of: "Text(") else { continue }
        let arg = String(chunk[open.upperBound...])
        var literals: [String] = []
        var cur = "", inString = false, escaped = false
        for c in arg {
            if escaped { cur.append(c); escaped = false; continue }
            if c == "\\" { cur.append(c); escaped = true; continue }
            if c == "\"" {
                if inString { literals.append(cur); cur = "" }
                inString.toggle(); continue
            }
            if inString { cur.append(c) }
        }
        // Unbounded only when there is no literal at all (Text(someVariable)) or
        // a literal splices in a value whose length is not known at build time.
        let dynamic = literals.isEmpty || literals.contains { $0.contains("\\(") }
        let literal: String? = literals.max(by: { width(decode($0), .body) < width(decode($1), .body) })
        var style: NSFont.TextStyle = .body
        for (name, s) in styles where chunk.contains(".font(.\(name))") { style = s }
        out.append(Row(file: path, text: decode(literal ?? ""), font: style,
                       dynamic: dynamic, fixed: chunk.contains(".fixedSize("), line: i + 1))
    }
    return out
}

func width(_ s: String, _ style: NSFont.TextStyle) -> CGFloat {
    (s as NSString).size(withAttributes: [.font: NSFont.preferredFont(forTextStyle: style)]).width
}

let FIX = ".fixedSize(horizontal: false, vertical: true)"
var failures = 0, checked = 0

for file in files {
    guard let src = try? String(contentsOfFile: file, encoding: .utf8) else {
        print("SKIP \(file) — not readable"); continue
    }
    let g = geometry(src)
    let avail = g.width - 2 * g.padding
    print("\n\(file)  —  frame \(Int(g.width))pt − padding \(Int(g.padding))×2  =  \(Int(avail))pt available")
    for r in rows(file) {
        checked += 1
        // Rule 1: content of unbounded length must be free to wrap.
        if r.dynamic {
            if r.fixed { print("  ok    :\(r.line) dynamic text, wraps") }
            else { failures += 1
                   print("  FAIL  :\(r.line) dynamic text with no \(FIX) — its length is not knowable at build time") }
            continue
        }
        // Rule 2: a literal that cannot fit on one line must be free to wrap.
        let need = width(r.text, r.font)
        if need > avail {
            if r.fixed { print(String(format: "  ok    :%d needs %.0fpt > %.0fpt, wraps", r.line, need, avail)) }
            else { failures += 1
                   print(String(format: "  FAIL  :%d needs %.0fpt > %.0fpt available and has no %@ — this renders TRUNCATED: \"%@\"",
                                r.line, need, avail, FIX, String(r.text.prefix(56)))) }
        } else {
            print(String(format: "  ok    :%d needs %.0fpt, fits", r.line, need))
        }
    }
}

print("\n\(checked) Text views checked.")
if failures == 0 { print("ALL PASS") } else { print("\(failures) FAILED"); exit(1) }
