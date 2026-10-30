// Renders Resources/AppIcon.icns: a simplified track-car center tachometer. A dark outer track
// with white major and fine yellow minor ticks, a red numeral ring (0–10), a black center with a
// small activity trace, a redline from 9, and a yellow needle on a silver hub. Small sizes drop
// the numerals and fine ticks so the dial still reads at 16–32 px.
// Run from the repo root: swift scripts/make-icon.swift
import AppKit

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

let red = rgb(0xC8102E)
let redLit = rgb(0xE3213F)
let ink = rgb(0xF3F4F6)
let yellow = rgb(0xE8D21C)

func render(_ px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let s = CGFloat(px) / 1024
    ctx.scaleBy(x: s, y: s)
    let detailed = px >= 128

    // macOS icon grid: 824pt body centered on a 1024 canvas, continuous corners.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: body, xRadius: 186, yRadius: 186)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    rgb(0x0E1014).setFill()
    shape.fill()
    ctx.restoreGState()
    ctx.saveGState()
    shape.addClip()
    NSGradient(colors: [rgb(0x262A32), rgb(0x0E1014)])!.draw(in: body, angle: -90)
    ctx.restoreGState()

    let center = CGPoint(x: 512, y: 512)
    let outer: CGFloat = 360      // inside edge of the bezel
    let ringOuter: CGFloat = 288  // red numeral ring
    let ringInner: CGFloat = 186
    func circle(_ r: CGFloat) -> CGRect { CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2) }
    func disc(_ r: CGFloat) -> NSBezierPath { NSBezierPath(ovalIn: circle(r)) }

    // Bezel: dark gunmetal, lit from above.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 20, color: NSColor.black.withAlphaComponent(0.55).cgColor)
    rgb(0x30343B).setFill()
    disc(outer + 26).fill()
    ctx.restoreGState()
    NSGradient(colors: [rgb(0x8A9099), rgb(0x3A3F47), rgb(0x1C1F24), rgb(0x4A4F57)],
               atLocations: [0, 0.4, 0.75, 1], colorSpace: .sRGB)!.draw(in: disc(outer + 26), angle: -90)

    // Outer track.
    NSGradient(colors: [rgb(0x1A1D22), rgb(0x0A0B0E)])!.draw(in: disc(outer), angle: -90)

    // Scale 0–10 over a 300° sweep: 0 at about 8 o'clock, 5 at the top, 10 at about 4 o'clock.
    let maxValue: CGFloat = 10
    let redline: CGFloat = 9
    func angle(_ v: CGFloat) -> CGFloat { (240 - 300 * v / maxValue) * .pi / 180 }
    func point(_ v: CGFloat, _ r: CGFloat) -> CGPoint {
        CGPoint(x: center.x + cos(angle(v)) * r, y: center.y + sin(angle(v)) * r)
    }
    func tick(_ v: CGFloat, from r0: CGFloat, to r1: CGFloat, width: CGFloat, color: NSColor) {
        ctx.setLineCap(.butt)
        ctx.setLineWidth(width)
        ctx.setStrokeColor(color.cgColor)
        ctx.move(to: point(v, r0))
        ctx.addLine(to: point(v, r1))
        ctx.strokePath()
    }

    // Fine minor ticks (yellow), majors (white), redline ticks (red) on the outer track.
    if detailed {
        for i in 0...Int(maxValue * 5) where i % 5 != 0 {
            let v = CGFloat(i) / 5
            tick(v, from: outer - 10, to: outer - 40, width: 4.5,
                 color: v >= redline ? redLit : yellow.withAlphaComponent(0.8))
        }
    }
    for i in 0...Int(maxValue) {
        let v = CGFloat(i)
        tick(v, from: outer - 8, to: ringOuter + 6, width: detailed ? 11 : 20, color: v > redline ? redLit : ink)
    }
    // Redline band along the outer edge.
    ctx.setLineCap(.butt)
    ctx.setLineWidth(detailed ? 10 : 22)
    ctx.setStrokeColor(redLit.cgColor)
    ctx.addArc(center: center, radius: outer - (detailed ? 6 : 12), startAngle: angle(redline), endAngle: angle(maxValue),
               clockwise: true)
    ctx.strokePath()

    // Red numeral ring with a little depth.
    let ring = NSBezierPath()
    ring.appendOval(in: circle(ringOuter))
    ring.appendOval(in: circle(ringInner))
    ring.windingRule = .evenOdd
    NSGradient(colors: [redLit, red, rgb(0x9E0C24)], atLocations: [0, 0.55, 1], colorSpace: .sRGB)!.draw(in: ring, angle: -90)

    // Black center.
    NSGradient(colors: [rgb(0x15171C), rgb(0x050608)])!
        .draw(fromCenter: CGPoint(x: center.x, y: center.y + 50), radius: 0, toCenter: center, radius: ringInner, options: [])

    // Numerals on the ring.
    if detailed {
        let font = NSFont.systemFont(ofSize: 60, weight: .bold)
        for n in 0...Int(maxValue) {
            let text = NSAttributedString(string: "\(n)", attributes: [.font: font, .foregroundColor: ink])
            let size = text.size()
            let at = point(CGFloat(n), (ringOuter + ringInner) / 2)
            text.draw(at: CGPoint(x: at.x - size.width / 2, y: at.y - size.height / 2 + 1))
        }

        // Digital readout in the lower center, where the car shows speed: a small activity trace.
        let bars: [CGFloat] = [0.30, 0.45, 0.35, 0.60, 0.50, 0.80, 0.65, 0.95]
        let barWidth: CGFloat = 11, gap: CGFloat = 7, height: CGFloat = 52
        let total = CGFloat(bars.count) * barWidth + CGFloat(bars.count - 1) * gap
        for (i, h) in bars.enumerated() {
            let bar = CGRect(x: center.x - total / 2 + CGFloat(i) * (barWidth + gap), y: center.y - 140,
                             width: barWidth, height: height * h)
            ink.withAlphaComponent(i == bars.count - 1 ? 1 : 0.7).setFill()
            NSBezierPath(roundedRect: bar, xRadius: 3, yRadius: 3).fill()
        }
    }

    // Needle: long, tapered, yellow, reaching over the outer ticks; short tail behind the hub.
    let value: CGFloat = 6.5
    let tipRadius = outer - 22
    let a = angle(value)
    let dir = CGPoint(x: cos(a), y: sin(a))
    let normal = CGPoint(x: -dir.y, y: dir.x)
    let baseHalf: CGFloat = detailed ? 14 : 24
    let tipHalf: CGFloat = detailed ? 4.5 : 10
    let tail: CGFloat = 64
    func at(_ along: CGFloat, _ across: CGFloat) -> CGPoint {
        CGPoint(x: center.x + dir.x * along + normal.x * across, y: center.y + dir.y * along + normal.y * across)
    }
    let needle = CGMutablePath()
    needle.move(to: at(-tail, baseHalf))
    needle.addLine(to: at(tipRadius, tipHalf))
    needle.addLine(to: at(tipRadius, -tipHalf))
    needle.addLine(to: at(-tail, -baseHalf))
    needle.closeSubpath()
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 14, color: NSColor.black.withAlphaComponent(0.6).cgColor)
    ctx.setFillColor(yellow.cgColor)
    ctx.addPath(needle)
    ctx.fillPath()
    ctx.restoreGState()

    // Hub: polished silver cap.
    let hub: CGFloat = detailed ? 40 : 62
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 10, color: NSColor.black.withAlphaComponent(0.6).cgColor)
    rgb(0x9CA3AF).setFill()
    disc(hub).fill()
    ctx.restoreGState()
    NSGradient(colors: [rgb(0xFFFFFF), rgb(0xC9CED6), rgb(0x7B828C), rgb(0xD1D5DB)],
               atLocations: [0, 0.35, 0.7, 1], colorSpace: .sRGB)!.draw(in: disc(hub), angle: -60)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try render(base * scale).representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}
try render(1024).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "Resources/AppIcon-1024.png"))

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")
