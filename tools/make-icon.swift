// lidawake app icon — final generator (concept 3: flat laptop, screen lit).
// Writes the full .iconset (caller runs iconutil), a 1024 preview, and a
// small-size legibility strip.
//
//   swiftc -O icon-final.swift -o icon-final -framework AppKit
//   ./icon-final <iconset-dir> <preview.png> <strip.png>

import AppKit
import CoreGraphics
import CoreText
import Foundation

func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(srgbRed: r/255, green: g/255, blue: b/255, alpha: a)
}
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
func makeContext(_ px: Int) -> CGContext {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high; ctx.setAllowsAntialiasing(true); return ctx
}
func grad(_ a: CGColor, _ b: CGColor) -> CGGradient {
    CGGradient(colorsSpace: sRGB, colors: [a, b] as CFArray, locations: [0, 1])!
}
let white = rgb(245,247,250), accent = rgb(90,170,255), accentL = rgb(160,210,255)

func drawIcon(_ ctx: CGContext, _ S: CGFloat, compact: Bool) {
    // background: night-indigo rounded square
    let m = 0.0977*S, side = S - 2*m, r = side*0.2256
    let bg = CGPath(roundedRect: CGRect(x: m, y: m, width: side, height: side),
                    cornerWidth: r, cornerHeight: r, transform: nil)
    ctx.saveGState(); ctx.addPath(bg); ctx.clip()
    ctx.drawLinearGradient(grad(rgb(43,58,103), rgb(15,19,41)),
                           start: CGPoint(x:0,y:S), end: CGPoint(x:0,y:0), options: [])
    ctx.restoreGState()

    let cx = 0.5*S
    if compact {
        // 16/32px: big, flat, high-contrast — no glow (turns to mush small)
        let base = CGMutablePath()
        base.addLines(between: [
            CGPoint(x: cx-0.35*S, y: 0.275*S), CGPoint(x: cx+0.35*S, y: 0.275*S),
            CGPoint(x: cx+0.285*S, y: 0.365*S), CGPoint(x: cx-0.285*S, y: 0.365*S)])
        base.closeSubpath()
        ctx.addPath(base); ctx.setFillColor(white); ctx.fillPath()
        let sr = CGRect(x: cx-0.30*S, y: 0.385*S, width: 0.60*S, height: 0.40*S)
        ctx.addPath(CGPath(roundedRect: sr, cornerWidth: 0.05*S, cornerHeight: 0.05*S, transform: nil))
        ctx.setFillColor(rgb(120,200,255)); ctx.fillPath()
    } else {
        // base deck (white trapezoid, wider at the front/bottom)
        let base = CGMutablePath()
        base.addLines(between: [
            CGPoint(x: cx-0.31*S, y: 0.31*S), CGPoint(x: cx+0.31*S, y: 0.31*S),
            CGPoint(x: cx+0.255*S, y: 0.385*S), CGPoint(x: cx-0.255*S, y: 0.385*S)])
        base.closeSubpath()
        ctx.addPath(base); ctx.setFillColor(white); ctx.fillPath()
        // screen (lit, accent) with soft glow
        let sr = CGRect(x: cx-0.245*S, y: 0.395*S, width: 0.49*S, height: 0.35*S)
        let screen = CGPath(roundedRect: sr, cornerWidth: 0.03*S, cornerHeight: 0.03*S, transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 0.045*S, color: accent.copy(alpha: 0.9)!)
        ctx.addPath(screen); ctx.setFillColor(accent); ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState(); ctx.addPath(screen); ctx.clip()
        ctx.drawLinearGradient(grad(accentL, accent),
                               start: CGPoint(x:0,y:0.745*S), end: CGPoint(x:0,y:0.395*S), options: [])
        ctx.restoreGState()
    }
}

func writePNG(_ img: CGImage, _ url: URL) {
    try! NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])!.write(to: url)
}
func iconImage(_ px: Int) -> CGImage { let c = makeContext(px); drawIcon(c, CGFloat(px), compact: px <= 32); return c.makeImage()! }

let a = CommandLine.arguments
guard a.count >= 4 else { fputs("usage: icon-final <iconset> <preview> <strip>\n", stderr); exit(2) }
let setDir = URL(fileURLWithPath: a[1])
try? FileManager.default.createDirectory(at: setDir, withIntermediateDirectories: true)
let entries: [(String, Int)] = [
    ("icon_16x16.png",16),("icon_16x16@2x.png",32),("icon_32x32.png",32),("icon_32x32@2x.png",64),
    ("icon_128x128.png",128),("icon_128x128@2x.png",256),("icon_256x256.png",256),
    ("icon_256x256@2x.png",512),("icon_512x512.png",512),("icon_512x512@2x.png",1024)]
for (n, px) in entries { writePNG(iconImage(px), setDir.appendingPathComponent(n)) }
writePNG(iconImage(1024), URL(fileURLWithPath: a[2]))

// legibility strip: actual-size renders on a split light/dark background
let sizes = [256, 128, 64, 32, 16], gap = 40
let stripW = sizes.reduce(0,+) + gap*(sizes.count+1)
let stripH = 256 + 90
let strip = CGContext(data: nil, width: stripW, height: stripH, bitsPerComponent: 8, bytesPerRow: 0,
                      space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
strip.setFillColor(rgb(238,238,240)); strip.fill(CGRect(x:0, y:0, width:stripW, height:stripH))
strip.setFillColor(rgb(40,40,44)); strip.fill(CGRect(x:0, y:0, width:CGFloat(stripW), height:CGFloat(stripH)/2))
var x = gap
for s in sizes {
    let img = iconImage(s)
    let y = (256 - s)/2 + 70
    strip.draw(img, in: CGRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(s), height: CGFloat(s)))
    strip.textMatrix = .identity
    let font = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, 26, nil)
    let astr = NSAttributedString(string: "\(s)px", attributes: [
        .init(kCTFontAttributeName as String): font,
        .init(kCTForegroundColorAttributeName as String): rgb(120,120,124)])
    let line = CTLineCreateWithAttributedString(astr)
    let b = CTLineGetImageBounds(line, strip)
    strip.textPosition = CGPoint(x: CGFloat(x) + CGFloat(s)/2 - b.width/2 - b.minX, y: 26)
    CTLineDraw(line, strip)
    x += s + gap
}
writePNG(strip.makeImage()!, URL(fileURLWithPath: a[3]))
print("ok")
