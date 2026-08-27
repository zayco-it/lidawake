// Menu-bar glyph exploration for T4.1 — Direction A (closed lid).
//
// DESIGNED AT 16pt FIRST, deliberately. The current app icon fails at small
// sizes because it was drawn at 1024 and degraded downward; this is the inverse.
// A template image is drawn as a MASK — only alpha matters — so there is no
// colour, no gradient and no glow here. Solid fills and strokes only.
//
//   swiftc -O design/menubar-glyphs.swift -o /tmp/glyphs -framework AppKit
//   /tmp/glyphs design/glyph-pass3.png 3        # pass: 1, 2 or 3
//
// Each sheet shows every candidate at TRUE 16px and at 8x nearest-neighbour,
// in off and on states, on both a light and a dark menu bar.
//
// All three passes are kept. The current icon's header says "concept 3" and the
// other two concepts are nowhere in the repo — the record of what was tried and
// rejected is worth more than the winner alone.
//
// What the passes established:
//   1  heavy fills           — 4 of 6 failed; a filled slab has no interior
//                              information and reads as a bar or a list
//   2  outlines, side views  — B1 is the most legible laptop of all 18, and is
//                              an OPEN one: the hollow interior reads as screen.
//                              Fully-shut side views collapse to a line.
//   3  closed 3/4 from above — a shut lid still shows TWO faces (top + front
//                              edge), which is the interior detail a flat slab
//                              lacks. C2 resolves the tension.
//
// The structural finding, worth not re-deriving: interior detail is what makes
// an object legible at 16px, and a closed laptop is defined by having none.

import AppKit
import CoreGraphics
import Foundation

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
func ctx(_ w: Int, _ h: Int) -> CGContext {
    let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                      space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.setAllowsAntialiasing(true); c.interpolationQuality = .high; return c
}
func rr(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> CGPath {
    CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h),
           cornerWidth: min(r, w/2), cornerHeight: min(r, h/2), transform: nil)
}

// Each glyph draws into a unit square S, solid black, origin bottom-left.
typealias Glyph = (CGContext, CGFloat, Bool) -> Void   // ctx, size, armed

// A1 — closed slab, lit seam as negative space. Lid above, deck below, gap between.
let a1: Glyph = { c, S, armed in
    let w = 0.80*S, x = (S-w)/2
    c.addPath(rr(x, 0.46*S, w, 0.26*S, 0.07*S))                  // lid
    c.addPath(rr(x, 0.30*S, w, 0.11*S, 0.045*S))                 // deck
    c.fillPath()
    if armed {                                                    // light escaping the seam
        c.addPath(rr(x + 0.14*w, 0.425*S, w - 0.28*w, 0.035*S, 0.017*S)); c.fillPath()
    }
}

// A2 — top-down closed lid with the finger notch, plus a light dot in front.
let a2: Glyph = { c, S, armed in
    let w = 0.78*S, h = 0.52*S, x = (S-w)/2, y = 0.30*S
    c.addPath(rr(x, y, w, h, 0.10*S)); c.fillPath()
    c.setBlendMode(.clear)                                        // notch cut from the front edge
    c.addEllipse(in: CGRect(x: S/2 - 0.09*S, y: y - 0.06*S, width: 0.18*S, height: 0.12*S)); c.fillPath()
    c.setBlendMode(.normal)
    if armed { c.addEllipse(in: CGRect(x: S/2 - 0.05*S, y: 0.13*S, width: 0.10*S, height: 0.10*S)); c.fillPath() }
}

// A3 — closed slab seen front-on, light spilling downward as a wedge.
let a3: Glyph = { c, S, armed in
    let w = 0.80*S, x = (S-w)/2
    c.addPath(rr(x, 0.42*S, w, 0.30*S, 0.08*S)); c.fillPath()
    if armed {
        let p = CGMutablePath()
        p.addLines(between: [CGPoint(x: S/2-0.30*S, y: 0.22*S), CGPoint(x: S/2+0.30*S, y: 0.22*S),
                             CGPoint(x: S/2+0.20*S, y: 0.38*S), CGPoint(x: S/2-0.20*S, y: 0.38*S)])
        p.closeSubpath(); c.addPath(p); c.fillPath()
    }
}

// A4 — closed slab with a status dot sitting on top of the lid.
let a4: Glyph = { c, S, armed in
    let w = 0.78*S, x = (S-w)/2
    c.addPath(rr(x, 0.32*S, w, 0.30*S, 0.08*S)); c.fillPath()
    if armed { c.addEllipse(in: CGRect(x: S/2 - 0.07*S, y: 0.70*S, width: 0.14*S, height: 0.14*S)); c.fillPath() }
}

// A5 — closed slab with waves above it (awake / still working).
let a5: Glyph = { c, S, armed in
    let w = 0.76*S, x = (S-w)/2
    c.addPath(rr(x, 0.26*S, w, 0.26*S, 0.07*S)); c.fillPath()
    guard armed else { return }
    c.setLineWidth(max(1, 0.065*S)); c.setLineCap(.round)
    for (i, r) in [0.16, 0.28].enumerated() {
        _ = i
        c.addArc(center: CGPoint(x: S/2, y: 0.56*S), radius: r*S,
                 startAngle: .pi*0.15, endAngle: .pi*0.85, clockwise: false)
        c.strokePath()
    }
}

// A6 — the slab is the whole mark; armed simply fills the seam solid (no second element).
let a6: Glyph = { c, S, armed in
    let w = 0.80*S, x = (S-w)/2
    c.addPath(rr(x, 0.34*S, w, 0.32*S, 0.085*S)); c.fillPath()
    c.setBlendMode(.clear)
    c.addPath(rr(x + 0.10*w, armed ? 0.60*S : 0.435*S, w - 0.20*w, 0.045*S, 0.02*S)); c.fillPath()
    c.setBlendMode(.normal)
}


// ---- pass 2: outlines and the side view -----------------------------------

// B1 — closed laptop, front 3/4, OUTLINE. Open interior is what lets a shape
// survive 16px; a filled slab has no interior information to survive with.
let b1: Glyph = { c, S, armed in
    let w = 0.80*S, x = (S-w)/2, lw = max(1, 0.075*S)
    c.setLineWidth(lw); c.setLineJoin(.round)
    c.addPath(rr(x, 0.40*S, w, 0.30*S, 0.08*S)); c.strokePath()      // lid, hollow
    c.addPath(rr(x - 0.04*S, 0.30*S, w + 0.08*S, 0.07*S, 0.03*S)); c.fillPath()  // deck edge, solid
    if armed { c.addEllipse(in: CGRect(x: S/2 - 0.055*S, y: 0.50*S, width: 0.11*S, height: 0.11*S)); c.fillPath() }
}

// B2 — SIDE view, lid a few degrees from shut. A wedge, not a slab: the one
// silhouette that says "closing the lid" rather than "a rectangle".
let b2: Glyph = { c, S, armed in
    let lw = max(1, 0.085*S)
    c.setLineWidth(lw); c.setLineCap(.round); c.setLineJoin(.round)
    let x0 = 0.14*S, x1 = 0.86*S, base = 0.34*S
    c.move(to: CGPoint(x: x0, y: base)); c.addLine(to: CGPoint(x: x1, y: base)); c.strokePath()   // deck
    c.move(to: CGPoint(x: x0 + 0.02*S, y: base + 0.06*S))                                          // lid, tilted
    c.addLine(to: CGPoint(x: x1 - 0.04*S, y: base + 0.26*S)); c.strokePath()
    if armed { c.addEllipse(in: CGRect(x: x1 - 0.10*S, y: base - 0.17*S, width: 0.10*S, height: 0.10*S)); c.fillPath() }
}

// B3 — SIDE view, fully shut: one wedge, light at the seam.
let b3: Glyph = { c, S, armed in
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 0.12*S, y: 0.44*S))
    p.addLine(to: CGPoint(x: 0.88*S, y: 0.52*S))
    p.addLine(to: CGPoint(x: 0.88*S, y: 0.40*S))
    p.addLine(to: CGPoint(x: 0.12*S, y: 0.38*S))
    p.closeSubpath()
    c.addPath(p); c.fillPath()
    if armed {
        c.setLineWidth(max(1, 0.06*S)); c.setLineCap(.round)
        c.move(to: CGPoint(x: 0.20*S, y: 0.28*S)); c.addLine(to: CGPoint(x: 0.80*S, y: 0.28*S)); c.strokePath()
    }
}

// B4 — top-down outline with the finger notch (A2, hollowed out).
let b4: Glyph = { c, S, armed in
    let w = 0.76*S, h = 0.50*S, x = (S-w)/2, y = 0.30*S, lw = max(1, 0.075*S)
    c.setLineWidth(lw); c.addPath(rr(x, y, w, h, 0.09*S)); c.strokePath()
    c.setBlendMode(.clear)
    c.addEllipse(in: CGRect(x: S/2 - 0.10*S, y: y - 0.07*S, width: 0.20*S, height: 0.13*S)); c.fillPath()
    c.setBlendMode(.normal)
    if armed { c.addEllipse(in: CGRect(x: S/2 - 0.055*S, y: 0.46*S, width: 0.11*S, height: 0.11*S)); c.fillPath() }
}

// B5 — outline slab + dot above (A4, hollowed out).
let b5: Glyph = { c, S, armed in
    let w = 0.78*S, x = (S-w)/2, lw = max(1, 0.075*S)
    c.setLineWidth(lw); c.addPath(rr(x, 0.30*S, w, 0.28*S, 0.075*S)); c.strokePath()
    if armed { c.addEllipse(in: CGRect(x: S/2 - 0.07*S, y: 0.68*S, width: 0.14*S, height: 0.14*S)); c.fillPath() }
}

// B6 — side view shut, with the light as a wedge spilling forward from the seam.
let b6: Glyph = { c, S, armed in
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 0.14*S, y: 0.50*S)); p.addLine(to: CGPoint(x: 0.86*S, y: 0.58*S))
    p.addLine(to: CGPoint(x: 0.86*S, y: 0.46*S)); p.addLine(to: CGPoint(x: 0.14*S, y: 0.44*S))
    p.closeSubpath(); c.addPath(p); c.fillPath()
    guard armed else { return }
    let q = CGMutablePath()
    q.move(to: CGPoint(x: 0.14*S, y: 0.40*S)); q.addLine(to: CGPoint(x: 0.40*S, y: 0.40*S))
    q.addLine(to: CGPoint(x: 0.30*S, y: 0.20*S)); q.addLine(to: CGPoint(x: 0.10*S, y: 0.20*S))
    q.closeSubpath(); c.addPath(q); c.fillPath()
}


// ---- pass 3: can a CLOSED laptop show two faces? ---------------------------

// C1 — closed lid, 3/4 from above. Top face as an outlined parallelogram, front
// edge as a solid band. Two faces = the interior detail a flat slab lacks.
let c1: Glyph = { c, S, armed in
    let lw = max(1, 0.07*S)
    let p = CGMutablePath()                                   // top face
    p.move(to: CGPoint(x: 0.22*S, y: 0.66*S)); p.addLine(to: CGPoint(x: 0.80*S, y: 0.66*S))
    p.addLine(to: CGPoint(x: 0.90*S, y: 0.46*S)); p.addLine(to: CGPoint(x: 0.12*S, y: 0.46*S))
    p.closeSubpath()
    c.setLineWidth(lw); c.setLineJoin(.round); c.addPath(p); c.strokePath()
    c.addPath(rr(0.12*S, 0.34*S, 0.78*S, 0.10*S, 0.04*S)); c.fillPath()   // front edge band
    if armed { c.addEllipse(in: CGRect(x: 0.46*S, y: 0.20*S, width: 0.10*S, height: 0.10*S)); c.fillPath() }
}

// C2 — same, but the front band is hollow and the LIGHT is the band filling in.
let c2: Glyph = { c, S, armed in
    let lw = max(1, 0.07*S)
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 0.22*S, y: 0.68*S)); p.addLine(to: CGPoint(x: 0.80*S, y: 0.68*S))
    p.addLine(to: CGPoint(x: 0.90*S, y: 0.46*S)); p.addLine(to: CGPoint(x: 0.12*S, y: 0.46*S))
    p.closeSubpath()
    c.setLineWidth(lw); c.setLineJoin(.round); c.addPath(p); c.strokePath()
    let band = rr(0.12*S, 0.32*S, 0.78*S, 0.12*S, 0.05*S)
    c.addPath(band)
    if armed { c.fillPath() } else { c.setLineWidth(lw); c.strokePath() }
}

// C3 — refined B2: side view, lid a few degrees open, thicker and shorter so the
// wedge is unmistakable, with the deck clearly a separate horizontal.
let c3: Glyph = { c, S, armed in
    let lw = max(1.5, 0.10*S)
    c.setLineWidth(lw); c.setLineCap(.round); c.setLineJoin(.round)
    c.move(to: CGPoint(x: 0.16*S, y: 0.34*S)); c.addLine(to: CGPoint(x: 0.84*S, y: 0.34*S)); c.strokePath()
    c.move(to: CGPoint(x: 0.18*S, y: 0.44*S)); c.addLine(to: CGPoint(x: 0.82*S, y: 0.60*S)); c.strokePath()
    if armed { c.addEllipse(in: CGRect(x: 0.44*S, y: 0.12*S, width: 0.12*S, height: 0.12*S)); c.fillPath() }
}

// C4 — refined B5: closed slab (outline) with the light UNDER it, spilling onto
// the desk. The slab stays generic; the spill supplies the meaning.
let c4: Glyph = { c, S, armed in
    let w = 0.76*S, x = (S-w)/2, lw = max(1, 0.075*S)
    c.setLineWidth(lw); c.addPath(rr(x, 0.44*S, w, 0.26*S, 0.07*S)); c.strokePath()
    guard armed else { return }
    c.setLineCap(.round); c.setLineWidth(max(1, 0.075*S))
    c.move(to: CGPoint(x: x + 0.10*w, y: 0.32*S)); c.addLine(to: CGPoint(x: x + 0.90*w, y: 0.32*S)); c.strokePath()
    c.move(to: CGPoint(x: x + 0.26*w, y: 0.20*S)); c.addLine(to: CGPoint(x: x + 0.74*w, y: 0.20*S)); c.strokePath()
}

// C5 — B1 kept honest: the shape that reads best, but with the lid CLOSED —
// deck band plus a lid line resting directly on it, no screen cavity.
let c5: Glyph = { c, S, armed in
    let w = 0.80*S, x = (S-w)/2, lw = max(1, 0.085*S)
    c.setLineWidth(lw); c.setLineJoin(.round)
    c.addPath(rr(x, 0.42*S, w, 0.20*S, 0.06*S)); c.strokePath()            // the shut clamshell
    c.addPath(rr(x - 0.04*S, 0.34*S, w + 0.08*S, 0.06*S, 0.03*S)); c.fillPath()   // desk / front lip
    if armed { c.addEllipse(in: CGRect(x: S/2 - 0.05*S, y: 0.72*S, width: 0.10*S, height: 0.10*S)); c.fillPath() }
}

// C6 — control: Apple's laptopcomputer, for direct comparison at the same size.
let c6: Glyph = { c, S, armed in
    guard let sym = NSImage(systemSymbolName: "laptopcomputer", accessibilityDescription: nil),
          let cg = sym.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
    let side = 0.86*S
    c.saveGState()
    c.clip(to: CGRect(x: (S-side)/2, y: (S-side)/2, width: side, height: side), mask: cg)
    c.fill(CGRect(x: 0, y: 0, width: S, height: S)); c.restoreGState()
    if armed { c.addEllipse(in: CGRect(x: S/2 - 0.05*S, y: 0.80*S, width: 0.10*S, height: 0.10*S)); c.fillPath() }
}

let pass = CommandLine.arguments.count > 2 ? (Int(CommandLine.arguments[2]) ?? 3) : 3
let glyphs: [(String, Glyph)] = {
    switch pass {
    case 1:  return [("A1 seam", a1), ("A2 notch", a2), ("A3 spill", a3),
                     ("A4 dot", a4), ("A5 waves", a5), ("A6 line", a6)]
    case 2:  return [("B1 3/4 out", b1), ("B2 closing", b2), ("B3 shut", b3),
                     ("B4 notch out", b4), ("B5 slab out", b5), ("B6 spill", b6)]
    default: return [("C1 3/4 shut", c1), ("C2 lit band", c2), ("C3 closing", c3),
                     ("C4 spill", c4), ("C5 shut+lip", c5), ("C6 broken", c6)]
    }
}()

func render(_ g: Glyph, _ px: Int, armed: Bool) -> CGImage {
    let c = ctx(px, px); c.setFillColor(CGColor(gray: 0, alpha: 1)); c.setStrokeColor(CGColor(gray: 0, alpha: 1))
    g(c, CGFloat(px), armed); return c.makeImage()!
}

// Contact sheet: true 16 and 32px, then nearest-neighbour 8x so the pixels are visible.
let cellW = 190, cellH = 132
let sheet = ctx(cellW * glyphs.count, cellH * 2 + 34)
sheet.setFillColor(CGColor(gray: 0.93, alpha: 1)); sheet.fill(CGRect(x: 0, y: cellH + 34, width: sheet.width, height: cellH))
sheet.setFillColor(CGColor(gray: 0.16, alpha: 1)); sheet.fill(CGRect(x: 0, y: 0, width: sheet.width, height: cellH + 34))

for (i, (name, g)) in glyphs.enumerated() {
    for (row, dark) in [(0, true), (1, false)] {
        let baseY = row == 0 ? 34 : cellH + 34
        sheet.setFillColor(CGColor(gray: dark ? 0.95 : 0.05, alpha: 1))
        for (j, armed) in [false, true].enumerated() {
            let img16 = render(g, 16, armed: armed), img32 = render(g, 32, armed: armed)
            let ox = CGFloat(i * cellW + 14 + j * 88)
            // true size
            sheet.saveGState(); sheet.clip(to: CGRect(x: ox, y: CGFloat(baseY + 92), width: 16, height: 16), mask: img16)
            sheet.fill(CGRect(x: ox, y: CGFloat(baseY + 92), width: 16, height: 16)); sheet.restoreGState()
            // 8x nearest-neighbour of the 16px raster — the pixels as they really land
            sheet.interpolationQuality = .none
            sheet.saveGState(); sheet.clip(to: CGRect(x: ox, y: CGFloat(baseY + 8), width: 64, height: 64), mask: img16)
            sheet.fill(CGRect(x: ox, y: CGFloat(baseY + 8), width: 64, height: 64)); sheet.restoreGState()
            sheet.interpolationQuality = .high
            _ = img32
        }
        // label
        sheet.textMatrix = .identity
        let f = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, 12, nil)
        let s = NSAttributedString(string: "\(name)   off / on", attributes: [
            .init(kCTFontAttributeName as String): f,
            .init(kCTForegroundColorAttributeName as String): CGColor(gray: dark ? 0.6 : 0.45, alpha: 1)])
        let line = CTLineCreateWithAttributedString(s)
        sheet.textPosition = CGPoint(x: CGFloat(i * cellW + 14), y: CGFloat(baseY + 76))
        CTLineDraw(line, sheet)
    }
}
try! NSBitmapImageRep(cgImage: sheet.makeImage()!).representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print("ok")
