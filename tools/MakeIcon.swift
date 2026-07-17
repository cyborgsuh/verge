// MakeIcon.swift — standalone Verge app-icon generator (not part of the app target).
// Usage: makeicon [output.icns]
// Draws the 1024px master with Core Graphics into offscreen bitmap contexts
// (no NSApplication / window server needed), writes every iconset size into a
// temp Verge.iconset, then runs `iconutil -c icns` to produce the .icns.
//
// Mark: a dark squircle holding a trackpad plate whose right edge carries a
// glowing pink slider bar with a knob and faint up/down chevrons.
import AppKit

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Verge.icns"

let space = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

let pinkDeep  = rgb(255, 46, 126)   // #FF2E7E
let pinkLight = rgb(255, 111, 181)  // #FF6FB5

func gradient(_ colors: [CGColor]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil)!
}

// Draws the icon at `px` pixels. All coordinates are in 1024-master units.
func draw(px: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8,
                        bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let s = CGFloat(px) / 1024

    // Background squircle: dark charcoal gradient, baked soft drop shadow.
    let bg = CGRect(x: 64 * s, y: 64 * s, width: 896 * s, height: 896 * s)
    let bgPath = CGPath(roundedRect: bg, cornerWidth: 205 * s, cornerHeight: 205 * s, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14 * s), blur: 40 * s, color: rgb(0, 0, 0, 0.55))
    ctx.addPath(bgPath)
    ctx.setFillColor(rgb(23, 23, 26))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()          // everything below clipped to the squircle
    ctx.addPath(bgPath)
    ctx.clip()
    ctx.drawLinearGradient(gradient([rgb(46, 46, 52), rgb(23, 23, 26)]),
                           start: CGPoint(x: 0, y: bg.maxY),
                           end: CGPoint(x: 0, y: bg.minY), options: [])
    // Faint pink ambience rising from the slider side.
    let glowCenter = CGPoint(x: 724 * s, y: 440 * s)
    ctx.drawRadialGradient(gradient([rgb(255, 46, 126, 0.18), rgb(255, 46, 126, 0)]),
                           startCenter: glowCenter, startRadius: 0,
                           endCenter: glowCenter, endRadius: 560 * s, options: [])

    // Trackpad plate: slightly darker (reads as inset), hairline highlight edge.
    let pad = CGRect(x: 232 * s, y: 300 * s, width: 560 * s, height: 424 * s)
    let padPath = CGPath(roundedRect: pad, cornerWidth: 58 * s, cornerHeight: 58 * s, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8 * s), blur: 28 * s, color: rgb(0, 0, 0, 0.6))
    ctx.addPath(padPath)
    ctx.setFillColor(rgb(30, 30, 34))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(padPath)
    ctx.setStrokeColor(rgb(255, 255, 255, 0.13))
    ctx.setLineWidth(5 * s)
    ctx.strokePath()

    // Glowing pink slider bar along the trackpad's right edge.
    let bar = CGRect(x: 717 * s, y: 346 * s, width: 30 * s, height: 332 * s)
    let barPath = CGPath(roundedRect: bar, cornerWidth: 15 * s, cornerHeight: 15 * s, transform: nil)
    for blur: CGFloat in [70, 28] {   // two passes = layered glow
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: blur * s, color: rgb(255, 46, 126, 0.85))
        ctx.addPath(barPath)
        ctx.setFillColor(pinkDeep)
        ctx.fillPath()
        ctx.restoreGState()
    }
    ctx.saveGState()
    ctx.addPath(barPath)
    ctx.clip()
    ctx.drawLinearGradient(gradient([pinkLight, pinkDeep]),
                           start: CGPoint(x: 0, y: bar.maxY),
                           end: CGPoint(x: 0, y: bar.minY), options: [])
    ctx.restoreGState()

    // Faint up/down hint chevrons on the bar.
    ctx.setStrokeColor(rgb(255, 255, 255, 0.75))
    ctx.setLineWidth(13 * s)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.beginPath()
    ctx.move(to: CGPoint(x: 706 * s, y: 630 * s))
    ctx.addLine(to: CGPoint(x: 732 * s, y: 654 * s))
    ctx.addLine(to: CGPoint(x: 758 * s, y: 630 * s))
    ctx.move(to: CGPoint(x: 706 * s, y: 428 * s))
    ctx.addLine(to: CGPoint(x: 732 * s, y: 404 * s))
    ctx.addLine(to: CGPoint(x: 758 * s, y: 428 * s))
    ctx.strokePath()

    // Knob, riding slightly above center ("sliding up").
    let knob = CGRect(x: (732 - 40) * s, y: (552 - 40) * s, width: 80 * s, height: 80 * s)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 34 * s, color: rgb(255, 46, 126, 0.9))
    ctx.setFillColor(rgb(255, 255, 255))
    ctx.fillEllipse(in: knob)
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addEllipse(in: knob)
    ctx.clip()
    ctx.drawLinearGradient(gradient([rgb(255, 255, 255), rgb(255, 214, 232)]),
                           start: CGPoint(x: 0, y: knob.maxY),
                           end: CGPoint(x: 0, y: knob.minY), options: [])
    ctx.restoreGState()

    ctx.restoreGState()       // end squircle clip
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) throws {
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "MakeIcon", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "PNG encode failed for \(url.path)"])
    }
    try data.write(to: url)
}

do {
    let fm = FileManager.default
    let iconset = fm.temporaryDirectory
        .appendingPathComponent("Verge-\(ProcessInfo.processInfo.processIdentifier).iconset")
    try? fm.removeItem(at: iconset)
    try fm.createDirectory(at: iconset, withIntermediateDirectories: true)

    for base in [16, 32, 128, 256, 512] {
        try writePNG(draw(px: base), to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
        try writePNG(draw(px: base * 2), to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
    }

    let out = URL(fileURLWithPath: outPath)
    try? fm.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    p.arguments = ["-c", "icns", iconset.path, "-o", out.path]
    try p.run()
    p.waitUntilExit()
    guard p.terminationStatus == 0 else {
        FileHandle.standardError.write("MakeIcon: iconutil failed (\(p.terminationStatus))\n".data(using: .utf8)!)
        exit(1)
    }
    try? fm.removeItem(at: iconset)
    print("Wrote \(out.path)")
} catch {
    FileHandle.standardError.write("MakeIcon: \(error)\n".data(using: .utf8)!)
    exit(1)
}
