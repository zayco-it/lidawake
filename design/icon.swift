// lidawake icon — ONE generator for every surface, so they cannot drift.
//
//   swiftc -O design/icon.swift -o /tmp/icon -framework AppKit && /tmp/icon design
//
// Outputs into design/:
//   app-preview.png      1024 app icon
//   app-strip.png        256/128/64/32/16 on split light/dark — the legibility check
//   menubar.png          the 16/32 template glyph, off and on, both menu bars
//   site-icon-512.png    exactly what public/lidawake/icon.png should be
//   iconset/             full .iconset, ready for iconutil
//
// GROWN FROM THE GLYPH, NOT SHRUNK INTO IT. C5 was chosen at 16pt monochrome
// first (design/menubar-glyphs.swift, pass 3) and the app icon is that same
// geometry given colour and depth. The old icon did the reverse — drawn at 1024,
// degraded downward — which is why it dissolves into a blue blob at 32px.
//
// The mark: a CLOSED laptop, front-on, with a light above it. The old icon drew
// an OPEN laptop with a lit screen, i.e. the opposite of what the product does,
// on every surface it appeared.
//
// Palette is deliberately light. Every competitor in this category is dark-with-
// a-glow, which is also the CleanMyMac trap the plan warns against; Things and
// Dato earn their premium feel through restraint. The one saturated colour is
// the light itself, in the existing brand blue.

import AppKit
import CoreGraphics
import CoreText
import Foundation

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(srgbRed: r/255, green: g/255, blue: b/255, alpha: a)
}
func ctx(_ w: Int, _ h: Int) -> CGContext {
    let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                      space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.setAllowsAntialiasing(true); c.interpolationQuality = .high; return c
}
func rr(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> CGPath {
    CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h),
           cornerWidth: min(r, w/2), cornerHeight: min(r, h/2), transform: nil)
}
func grad(_ a: CGColor, _ b: CGColor) -> CGGradient {
    CGGradient(colorsSpace: sRGB, colors: [a, b] as CFArray, locations: [0, 1])!
}

// Brand blue, unchanged — the armed menu-bar tint and the site accent already use it.
let brand      = rgb(90, 170, 255)
let brandDeep  = rgb(38, 110, 210)
let graphite   = rgb(46, 52, 66)
let graphiteHi = rgb(74, 82, 100)
let lipTone    = rgb(28, 33, 44)

// MARK: - The mark, shared by every surface
//
// Geometry is C5's, in a unit square. `armed` adds the light. Drawn in one place
// so the menu-bar glyph and the app icon are literally the same shape.

func markPaths(_ S: CGFloat) -> (body: CGPath, lip: CGPath, light: CGRect) {
    let w = 0.80*S, x = (S - w)/2
    return (rr(x, 0.42*S, w, 0.20*S, 0.06*S),
            rr(x - 0.04*S, 0.325*S, w + 0.08*S, 0.070*S, 0.035*S),
            CGRect(x: S/2 - 0.05*S, y: 0.715*S, width: 0.10*S, height: 0.10*S))
}

/// The same three elements, spread for a square canvas — plus the one detail a
/// 16px glyph cannot hold and a 1024 icon must have: THE SEAM.
///
/// The first attempt set the base well below the lid and slightly wider. It read
/// as two stacked bars and a dot — an abstract mark, or a laptop sitting on a
/// desk, which is a different object. A closed laptop is a lid and a base
/// TOUCHING, separated by a bright hairline. That line is the single most
/// laptop-identifying detail available, and it is why this reads as a device.
func iconPaths(_ S: CGFloat) -> (lid: CGPath, base: CGPath, light: CGRect) {
    let w = 0.84*S, x = (S - w)/2
    // Corner radius tightened from 0.055 to 0.030: at 1024 the generous radius
    // read pill-like rather than like a device. Base tightened to match.
    // Seam widened from 0.016 to 0.028 — it is the one detail that says
    // "closed laptop" and it was barely visible at 1024, gone below 128.
    let seam = 0.028*S
    let baseH = 0.080*S, baseY = 0.280*S
    return (rr(x, baseY + baseH + seam, w, 0.215*S, 0.030*S),
            rr(x + 0.012*S, baseY, w - 0.024*S, baseH, 0.020*S),
            CGRect(x: S/2 - 0.065*S, y: 0.685*S, width: 0.13*S, height: 0.13*S))
}

/// Menu bar: a template mask. Only alpha matters — no colour, no gradient.
func drawGlyph(_ c: CGContext, _ S: CGFloat, armed: Bool) {
    let p = markPaths(S)
    c.setFillColor(CGColor(gray: 0, alpha: 1)); c.setStrokeColor(CGColor(gray: 0, alpha: 1))
    c.setLineWidth(max(1, 0.085*S)); c.setLineJoin(.round)
    c.addPath(p.body); c.strokePath()
    c.addPath(p.lip); c.fillPath()
    if armed { c.addEllipse(in: p.light); c.fillPath() }
}

/// App icon: the same geometry, with material.
func drawAppIcon(_ c: CGContext, _ S: CGFloat, compact: Bool) {
    // Apple's icon grid: 824/1024 square, corner radius 185.4/824.
    let m = 0.0977*S, side = S - 2*m, r = side*0.2256
    let plate = CGPath(roundedRect: CGRect(x: m, y: m, width: side, height: side),
                       cornerWidth: r, cornerHeight: r, transform: nil)
    c.saveGState(); c.addPath(plate); c.clip()
    c.drawLinearGradient(grad(rgb(252, 253, 255), rgb(226, 232, 241)),
                         start: CGPoint(x: 0, y: S), end: CGPoint(x: 0, y: 0), options: [])
    c.restoreGState()

    // The mark, inset inside the plate and nudged down to balance the light above it.
    let g = side * 0.94, ox = (S - g)/2, oy = m + side*0.03
    c.saveGState(); c.translateBy(x: ox, y: oy)
    let p = iconPaths(g)
    let lid = p.lid, base = p.base

    if compact {
        // 16/32px: the lip is under a pixel and only muddies the silhouette, so
        // it goes. Two elements, both oversized, maximum contrast — the old icon
        // died here by keeping detail it could not render.
        let w = 0.90*g, x = (g - w)/2
        c.setFillColor(graphite)
        c.addPath(rr(x, 0.26*g, w, 0.30*g, 0.08*g)); c.fillPath()
        c.setFillColor(brand)
        c.addEllipse(in: CGRect(x: g/2 - 0.11*g, y: 0.64*g, width: 0.22*g, height: 0.22*g)); c.fillPath()
    } else {
        c.saveGState()                                  // contact shadow under the lip
        // Shadow kept shallow and offset UP-free: a downward shadow lands in the
        // seam and closes the very gap that identifies the object.
        c.setShadow(offset: CGSize(width: 0, height: 0.004*g), blur: 0.030*g,
                    color: rgb(20, 28, 45, 0.22))
        c.setFillColor(graphite); c.addPath(lid); c.fillPath()
        c.restoreGState()
        c.saveGState(); c.addPath(lid); c.clip()     // lid top face catching light
        c.drawLinearGradient(grad(graphiteHi, graphite),
                             start: CGPoint(x: 0, y: 0.60*g), end: CGPoint(x: 0, y: 0.38*g), options: [])
        c.restoreGState()
        c.setFillColor(lipTone); c.addPath(base); c.fillPath()
        // NOTE: a downward glow cone was tried here and removed. A filled circle
        // above a widening shape reads as a head and shoulders — the icon became
        // a user avatar. The halo has to stay symmetric.
        c.saveGState()                                  // the light — the one saturated thing
        c.setShadow(offset: .zero, blur: 0.06*g, color: brand.copy(alpha: 0.9)!)
        c.setFillColor(brand); c.addEllipse(in: p.light); c.fillPath()
        c.restoreGState()
        c.saveGState(); c.addEllipse(in: p.light); c.clip()
        c.drawLinearGradient(grad(rgb(170, 214, 255), brandDeep),
                             start: CGPoint(x: 0, y: p.light.maxY), end: CGPoint(x: 0, y: p.light.minY), options: [])
        c.restoreGState()
    }
    c.restoreGState()
}

// MARK: - Output

func png(_ img: CGImage, _ url: URL) {
    try! NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])!.write(to: url)
}
func appIcon(_ px: Int) -> CGImage {
    let c = ctx(px, px); drawAppIcon(c, CGFloat(px), compact: px <= 32); return c.makeImage()!
}
func glyph(_ px: Int, armed: Bool) -> CGImage {
    let c = ctx(px, px); drawGlyph(c, CGFloat(px), armed: armed); return c.makeImage()!
}
func label(_ c: CGContext, _ s: String, _ x: CGFloat, _ y: CGFloat, _ col: CGColor, _ size: CGFloat = 22) {
    c.textMatrix = .identity
    let f = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, size, nil)
    let a = NSAttributedString(string: s, attributes: [
        .init(kCTFontAttributeName as String): f, .init(kCTForegroundColorAttributeName as String): col])
    c.textPosition = CGPoint(x: x, y: y); CTLineDraw(CTLineCreateWithAttributedString(a), c)
}

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "design")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

// 1. iconset + preview + the 512 the site needs, all from this one draw call.
// MUST end in .iconset — iconutil rejects the directory otherwise, with a
// bare "Invalid Iconset." that says nothing about the reason.
let setDir = out.appendingPathComponent("lidawake.iconset")
try? FileManager.default.createDirectory(at: setDir, withIntermediateDirectories: true)
for (n, px) in [("icon_16x16.png",16),("icon_16x16@2x.png",32),("icon_32x32.png",32),("icon_32x32@2x.png",64),
                ("icon_128x128.png",128),("icon_128x128@2x.png",256),("icon_256x256.png",256),
                ("icon_256x256@2x.png",512),("icon_512x512.png",512),("icon_512x512@2x.png",1024)] {
    png(appIcon(px), setDir.appendingPathComponent(n))
}
png(appIcon(1024), out.appendingPathComponent("app-preview.png"))
png(appIcon(512),  out.appendingPathComponent("site-icon-512.png"))

// 2. Legibility strip — actual size, split light/dark.
let sizes = [256, 128, 64, 32, 16], gap = 40
let sw = sizes.reduce(0,+) + gap*(sizes.count+1), sh = 256 + 90
let strip = ctx(sw, sh)
strip.setFillColor(rgb(238,238,240)); strip.fill(CGRect(x:0,y:0,width:sw,height:sh))
strip.setFillColor(rgb(40,40,44));    strip.fill(CGRect(x:0,y:0,width:CGFloat(sw),height:CGFloat(sh)/2))
var x = gap
for s in sizes {
    strip.draw(appIcon(s), in: CGRect(x: CGFloat(x), y: CGFloat((256-s)/2 + 70), width: CGFloat(s), height: CGFloat(s)))
    label(strip, "\(s)px", CGFloat(x), 26, rgb(120,120,124), 26)
    x += s + gap
}
png(strip.makeImage()!, out.appendingPathComponent("app-strip.png"))

// 3. Menu bar sheet — true 16px and 8x pixels, off/on, light and dark bars.
let mw = 470, mh = 240
let mb = ctx(mw, mh)
mb.setFillColor(rgb(236,237,239)); mb.fill(CGRect(x:0,y:mh/2,width:mw,height:mh/2))
mb.setFillColor(rgb(38,38,42));    mb.fill(CGRect(x:0,y:0,width:mw,height:mh/2))
for (row, dark) in [(0,true),(1,false)] {
    let baseY = row == 0 ? 12 : mh/2 + 12
    mb.setFillColor(CGColor(gray: dark ? 0.95 : 0.05, alpha: 1))
    for (j, armed) in [false, true].enumerated() {
        let img = glyph(16, armed: armed), ox = CGFloat(30 + j*220)
        mb.saveGState(); mb.clip(to: CGRect(x: ox, y: CGFloat(baseY+78), width: 16, height: 16), mask: img)
        mb.fill(CGRect(x: ox, y: CGFloat(baseY+78), width: 16, height: 16)); mb.restoreGState()
        mb.interpolationQuality = .none
        mb.saveGState(); mb.clip(to: CGRect(x: ox+40, y: CGFloat(baseY+8), width: 96, height: 96), mask: img)
        mb.fill(CGRect(x: ox+40, y: CGFloat(baseY+8), width: 96, height: 96)); mb.restoreGState()
        mb.interpolationQuality = .high
        label(mb, armed ? "on" : "off", ox, CGFloat(baseY+62), CGColor(gray: dark ? 0.62 : 0.42, alpha: 1), 15)
    }
}
png(mb.makeImage()!, out.appendingPathComponent("menubar.png"))
// 4. Menu-bar template assets. Exported as files rather than redrawn inside the
//    app, so the app and the icon cannot drift — which is exactly how the site's
//    icon.png drifted from the .icns in the first place.
let tpl = out.appendingPathComponent("menubar-template")
try? FileManager.default.createDirectory(at: tpl, withIntermediateDirectories: true)
for (name, armed) in [("lidawake-menubar", false), ("lidawake-menubar-on", true)] {
    png(glyph(16, armed: armed), tpl.appendingPathComponent("\(name).png"))
    png(glyph(32, armed: armed), tpl.appendingPathComponent("\(name)@2x.png"))
}

print("wrote app-preview.png, app-strip.png, menubar.png, site-icon-512.png, lidawake.iconset/, menubar-template/")
