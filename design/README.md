# T4.1 — app icon: ATTEMPTED AND REVERTED

Shipped as 1.4.1 on 2026-08-27 and **reverted in 1.4.2 the same day**, after
seeing it in a real menu bar. Everything here is kept as the record, so the next
attempt starts from what was learned rather than from scratch.

## What was tried

Direction A — a **closed lid**, on the reasoning that the old icon draws an
*open* laptop with a lit screen, which is the opposite of what the product does.

18 menu-bar candidates over three passes, all designed at **16pt monochrome
first** and inspected at 8x nearest-neighbour (`menubar-glyphs.swift`, sheets
regenerable with `swiftc -O design/menubar-glyphs.swift -o /tmp/g -framework
AppKit && /tmp/g design/glyph-pass3.png 3`). C5 was chosen. `icon.swift` grew it
into a full icon set.

## Why it failed — two findings any future attempt must solve

**1. A closed lid has no interior detail, and interior detail is what makes an
object legible at 16px.** This showed up in pass 2: B1 is the most legible
laptop of all 18 and is an *open* one, because the hollow interior reads as the
screen. Fully-shut side views collapse to a diagonal line. The 3/4 view was the
workaround — a shut lid still shows two faces — but it only narrows the gap.
pipekey's read of the shipped result was *"a blue dot above two dark bars"*, not
a closed laptop.

**2. A small state indicator on a menu-bar glyph is not distinguishable without
a side-by-side reference.** This is the one that actually killed it. C2 was
rejected during design for exactly this and C5 was chosen because its dot
"reads instantly" — and in a real menu bar it does not. **Nobody ever sees the
two states together.** They see one glyph and must know, from that alone, which
state it is. Off was a white rectangle; on was the same rectangle with a barely
visible mark above.

The verification that missed it compared the two states side by side, which is
not the condition that matters. **Test a state indicator by looking at ONE state
and asking whether you can name it.**

## What was kept

- **One generator for the `.icns` and the site's `icon.png`**
  (`tools/make-icon.swift`, driven by `tools/build-icon.sh`). The site copy was
  a separate hand-export and had already drifted. Independent of artwork.
- **This directory** — all 18 candidates, the sheets and the reasoning.

## What could NOT be kept

The **template-mode fix**. It only worked because the new glyph distinguished
states by *shape*. The shipping glyph distinguishes them by **colour** — same
SF Symbol, brand blue when armed — so making both states templates would render
them pixel-identical and destroy the only state signal it has. The fix was never
independent of the artwork.

## Next time

The icon is a **candidate for a professional designer once there is revenue**,
not a defect to fix now. Whoever picks it up: both findings above are hard
constraints, and the second one is the expensive one.
