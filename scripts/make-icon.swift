// Renders Resources/AppIcon.icns: a simplified sports-car center tachometer (aluminum bezel,
// black face, upright 0–9 numerals, red zone from 7.5, red needle). Small sizes drop the numerals
// and minor ticks so the dial still reads at 16–32 px. Run from the repo root: swift scripts/make-icon.swift
import AppKit

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

let red = rgb(0xC8102E)
let redBright = rgb(0xF0475A)
let ink = rgb(0xF3F4F6)

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
    rgb(0x111318).setFill()
    shape.fill()
    ctx.restoreGState()
    ctx.saveGState()
    shape.addClip()
    NSGradient(colors: [rgb(0x2A2F3A), rgb(0x111318)])!.draw(in: body, angle: -90)
    ctx.restoreGState()

    let center = CGPoint(x: 512, y: 512)
    let face: CGFloat = 340       // face radius
    let bezel: CGFloat = 30       // aluminum ring width

    func circle(_ r: CGFloat) -> CGRect { CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2) }

    // Bezel: brushed aluminum, lit from above, with a dark seam where it meets the face.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 18, color: NSColor.black.withAlphaComponent(0.5).cgColor)
    rgb(0x9CA3AF).setFill()
    NSBezierPath(ovalIn: circle(face + bezel)).fill()
    ctx.restoreGState()
    NSGradient(colors: [rgb(0xF3F4F6), rgb(0xA1A7B0), rgb(0x5B616B), rgb(0xB8BEC7)],
               atLocations: [0, 0.45, 0.8, 1], colorSpace: .sRGB)!
        .draw(in: NSBezierPath(ovalIn: circle(face + bezel)), angle: -90)
    rgb(0x05060A).setFill()
    NSBezierPath(ovalIn: circle(face + 4)).fill()

    // Face: near-black with a soft center lift.
    NSGradient(colors: [rgb(0x1C1F26), rgb(0x0A0B0F)])!
        .draw(fromCenter: CGPoint(x: center.x, y: center.y + 60), radius: 0, toCenter: center, radius: face, options: [])

    // Scale 0–9 over a 270° sweep: 0 at lower left, 9 at lower right.
    let maxValue: CGFloat = 9
    let redline: CGFloat = 7.5
    func angle(_ v: CGFloat) -> CGFloat { (225 - 270 * v / maxValue) * .pi / 180 }
    func point(_ v: CGFloat, _ r: CGFloat) -> CGPoint {
        CGPoint(x: center.x + cos(angle(v)) * r, y: center.y + sin(angle(v)) * r)
    }

    // Red zone: a band along the outer edge, under the ticks.
    ctx.setLineCap(.butt)
    ctx.setLineWidth(detailed ? 16 : 30)
    ctx.setStrokeColor(red.cgColor)
    ctx.addArc(center: center, radius: face - (detailed ? 12 : 18), startAngle: angle(redline), endAngle: angle(maxValue),
               clockwise: true)
    ctx.strokePath()

    // Ticks: majors at every 1,000, minors at the half.
    for i in 0...Int(maxValue * 2) {
        let v = CGFloat(i) / 2
        let major = i % 2 == 0
        if !major && !detailed { continue }
        ctx.setLineCap(.butt)
        ctx.setLineWidth(major ? (detailed ? 12 : 20) : 6)
        ctx.setStrokeColor((v >= redline ? redBright : ink.withAlphaComponent(major ? 1 : 0.7)).cgColor)
        ctx.move(to: point(v, face - 18))
        ctx.addLine(to: point(v, face - (major ? 78 : 50)))
        ctx.strokePath()
    }

    // Upright numerals.
    if detailed {
        let font = NSFont.systemFont(ofSize: 74, weight: .medium)
        for n in 0...Int(maxValue) {
            let v = CGFloat(n)
            let text = NSAttributedString(string: "\(n)", attributes: [
                .font: font, .foregroundColor: v >= 8 ? redBright : ink,
            ])
            let size = text.size()
            let at = point(v, face - 130)
            text.draw(at: CGPoint(x: at.x - size.width / 2, y: at.y - size.height / 2 + 2))
        }
    }

    // Digital window in the lower face, where the car shows speed; here, a small activity trace.
    if detailed {
        let window = CGRect(x: center.x - 92, y: center.y - 222, width: 184, height: 74)
        let path = NSBezierPath(roundedRect: window, xRadius: 14, yRadius: 14)
        rgb(0x050608).setFill()
        path.fill()
        rgb(0x2A2F3A).setStroke()
        path.lineWidth = 3
        path.stroke()
        let bars: [CGFloat] = [0.30, 0.45, 0.35, 0.60, 0.50, 0.80, 0.65, 0.95]
        let barWidth: CGFloat = 12, gap: CGFloat = 7
        let total = CGFloat(bars.count) * barWidth + CGFloat(bars.count - 1) * gap
        for (i, h) in bars.enumerated() {
            let x = window.midX - total / 2 + CGFloat(i) * (barWidth + gap)
            let bar = CGRect(x: x, y: window.minY + 14, width: barWidth, height: (window.height - 28) * h)
            ink.withAlphaComponent(i == bars.count - 1 ? 1 : 0.75).setFill()
            NSBezierPath(roundedRect: bar, xRadius: 3, yRadius: 3).fill()
        }
    }

    // Needle: tapered, red, with a short counterweight tail.
    let value: CGFloat = 5.6
    let tipRadius = face - 34
    let a = angle(value)
    let dir = CGPoint(x: cos(a), y: sin(a))
    let normal = CGPoint(x: -dir.y, y: dir.x)
    let baseHalf: CGFloat = detailed ? 18 : 26
    let tipHalf: CGFloat = detailed ? 6 : 11
    let tail: CGFloat = 70
    let needle = CGMutablePath()
    needle.move(to: CGPoint(x: center.x - dir.x * tail + normal.x * baseHalf, y: center.y - dir.y * tail + normal.y * baseHalf))
    needle.addLine(to: CGPoint(x: center.x + dir.x * tipRadius + normal.x * tipHalf, y: center.y + dir.y * tipRadius + normal.y * tipHalf))
    needle.addLine(to: CGPoint(x: center.x + dir.x * tipRadius - normal.x * tipHalf, y: center.y + dir.y * tipRadius - normal.y * tipHalf))
    needle.addLine(to: CGPoint(x: center.x - dir.x * tail - normal.x * baseHalf, y: center.y - dir.y * tail - normal.y * baseHalf))
    needle.closeSubpath()
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 14, color: NSColor.black.withAlphaComponent(0.6).cgColor)
    ctx.setFillColor(redBright.cgColor)
    ctx.addPath(needle)
    ctx.fillPath()
    ctx.restoreGState()

    // Hub: black cap with a machined edge.
    let hub: CGFloat = detailed ? 52 : 76
    NSGradient(colors: [rgb(0x6B7280), rgb(0x1F2329)])!.draw(in: NSBezierPath(ovalIn: circle(hub)), angle: -90)
    NSGradient(colors: [rgb(0x2A2E36), rgb(0x0B0C0F)])!.draw(in: NSBezierPath(ovalIn: circle(hub - 8)), angle: -90)

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
