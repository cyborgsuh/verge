// MakeDmgBackground.swift — standalone Verge DMG-window background generator.
// Usage: makedmgbg [outputDir]        (default "tools/dmg-bg")
// Renders offscreen into CGContext bitmaps (no NSApplication / window server)
// and writes background.png (660x420 @1x) + background@2x.png (1320x840 @2x).
//
// Layout (Finder window content 660x420, design coords are top-left / y-down):
//   Verge.app icon center      (170, 235)   — kept clean, Finder places it
//   Applications folder center (490, 235)   — kept clean, Finder places it
//   pink drag arrow            x 250..410 at y 235
//   header band                y 40..110: wordmark + accent bar + tagline
//   Finder filename labels land below y~300 — nothing busy drawn there
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "tools/dmg-bg"

let space = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

let pinkDeep  = rgb(255, 46, 126)   // #FF2E7E
let pinkLight = rgb(255, 111, 181)  // #FF6FB5

func gradient(_ colors: [CGColor]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil)!
}

let W: CGFloat = 660, H: CGFloat = 420

func draw(scale: Int) -> CGImage {
    let s = CGFloat(scale)
    let ctx = CGContext(data: nil, width: Int(W) * scale, height: Int(H) * scale,
                        bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // design y (top-left origin, y down) -> CG y (bottom-left origin, y up)
    func cgY(_ designY: CGFloat) -> CGFloat { (H - designY) * s }

    // Charcoal vertical gradient, same mood as the app icon.
    ctx.drawLinearGradient(gradient([rgb(46, 46, 52), rgb(23, 23, 26)]),
                           start: CGPoint(x: 0, y: H * s),
                           end: CGPoint(x: 0, y: 0), options: [])
    // Subtle pink radial glow behind the drag path.
    let glowCenter = CGPoint(x: 330 * s, y: cgY(245))
    ctx.drawRadialGradient(gradient([rgb(255, 46, 126, 0.13), rgb(255, 46, 126, 0)]),
                           startCenter: glowCenter, startRadius: 0,
                           endCenter: glowCenter, endRadius: 320 * s, options: [])

    // Glowing pink arrow, left -> right (drag this way). Clear of both 130px icon squares.
    let yMid = cgY(235)
    let arrow = CGMutablePath()
    arrow.addRoundedRect(in: CGRect(x: 252 * s, y: yMid - 5 * s, width: 134 * s, height: 10 * s),
                         cornerWidth: 5 * s, cornerHeight: 5 * s)
    arrow.move(to: CGPoint(x: 384 * s, y: yMid + 20 * s))
    arrow.addLine(to: CGPoint(x: 412 * s, y: yMid))
    arrow.addLine(to: CGPoint(x: 384 * s, y: yMid - 20 * s))
    arrow.closeSubpath()
    for blur: CGFloat in [30, 12] {   // layered glow, like the icon's slider bar
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: blur * s, color: rgb(255, 46, 126, 0.8))
        ctx.addPath(arrow)
        ctx.setFillColor(pinkDeep)
        ctx.fillPath()
        ctx.restoreGState()
    }
    ctx.saveGState()
    ctx.addPath(arrow)
    ctx.clip()
    ctx.drawLinearGradient(gradient([pinkDeep, pinkLight]),
                           start: CGPoint(x: 250 * s, y: 0),
                           end: CGPoint(x: 412 * s, y: 0), options: [])
    ctx.restoreGState()

    // Header accent bar (under the wordmark).
    let bar = CGPath(roundedRect: CGRect(x: 42 * s, y: cgY(86), width: 58 * s, height: 4 * s),
                     cornerWidth: 2 * s, cornerHeight: 2 * s, transform: nil)
    ctx.saveGState()
    ctx.addPath(bar)
    ctx.clip()
    ctx.drawLinearGradient(gradient([pinkDeep, pinkLight]),
                           start: CGPoint(x: 42 * s, y: 0),
                           end: CGPoint(x: 100 * s, y: 0), options: [])
    ctx.restoreGState()

    // Text via NSGraphicsContext (headless-safe; needs no NSApplication).
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    // In a non-flipped context, draw(at:) puts the string's LOWER-left corner at the point.
    func text(_ str: String, designTop: CGFloat, x: CGFloat?, font: NSFont, color: NSColor) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = str.size(withAttributes: attrs)
        let px = x.map { $0 * s } ?? (W * s - size.width) / 2   // nil x = centered
        str.draw(at: CGPoint(x: px, y: cgY(designTop) - size.height), withAttributes: attrs)
    }
    text("Verge", designTop: 40, x: 40,
         font: .systemFont(ofSize: 30 * s, weight: .bold), color: .white)
    text("Slide the verge.", designTop: 93, x: 40,
         font: .systemFont(ofSize: 13 * s, weight: .medium),
         color: NSColor(white: 1, alpha: 0.65))
    text("Drag Verge to Applications", designTop: 378, x: nil,
         font: .systemFont(ofSize: 12 * s, weight: .regular),
         color: NSColor(white: 1, alpha: 0.45))
    NSGraphicsContext.restoreGraphicsState()

    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) throws {
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: W, height: H)   // point size -> 72dpi @1x / 144dpi @2x for tiffutil
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "MakeDmgBackground", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "PNG encode failed for \(url.path)"])
    }
    try data.write(to: url)
}

do {
    let dir = URL(fileURLWithPath: outDir)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try writePNG(draw(scale: 1), to: dir.appendingPathComponent("background.png"))
    try writePNG(draw(scale: 2), to: dir.appendingPathComponent("background@2x.png"))
    print("Wrote \(dir.path)/background.png + background@2x.png")
} catch {
    FileHandle.standardError.write("MakeDmgBackground: \(error)\n".data(using: .utf8)!)
    exit(1)
}
