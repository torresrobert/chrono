// Renders Resources/AppIcon.icns: a tachometer dial with a redline zone, on the Torres Labs dark
// background. Run from the repo root: swift scripts/make-icon.swift
import AppKit

let red = NSColor(srgbRed: 0xC8 / 255.0, green: 0x10 / 255.0, blue: 0x2E / 255.0, alpha: 1)
let redBright = NSColor(srgbRed: 0xF0 / 255.0, green: 0x47 / 255.0, blue: 0x5A / 255.0, alpha: 1)
let ink = NSColor(srgbRed: 0xF3 / 255.0, green: 0xF4 / 255.0, blue: 0xF6 / 255.0, alpha: 1)

func render(_ px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let s = CGFloat(px) / 1024
    ctx.scaleBy(x: s, y: s)

    // macOS icon grid: 824pt body centered on a 1024 canvas, continuous corners.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: body, xRadius: 186, yRadius: 186)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    NSColor(srgbRed: 0x0F / 255.0, green: 0x12 / 255.0, blue: 0x1A / 255.0, alpha: 1).setFill()
    shape.fill()
    ctx.restoreGState()

    ctx.saveGState()
    shape.addClip()
    // Subtle top-down sheen plus the branded red glow (BrandedGradientBackground, in icon form).
    NSGradient(colors: [NSColor(srgbRed: 0x1F / 255.0, green: 0x25 / 255.0, blue: 0x33 / 255.0, alpha: 1),
                        NSColor(srgbRed: 0x0F / 255.0, green: 0x12 / 255.0, blue: 0x1A / 255.0, alpha: 1)])!
        .draw(in: body, angle: -90)
    NSGradient(colors: [red.withAlphaComponent(0.28), red.withAlphaComponent(0)])!
        .draw(fromCenter: CGPoint(x: 512, y: 560), radius: 0, toCenter: CGPoint(x: 512, y: 560), radius: 420, options: [])
    ctx.restoreGState()

    let center = CGPoint(x: 512, y: 500)
    let radius: CGFloat = 300
    // Dial sweeps 270°, from 225° (bottom-left) clockwise to -45° (bottom-right).
    func angle(_ t: CGFloat) -> CGFloat { (225 - 270 * t) * .pi / 180 }
    func point(_ t: CGFloat, _ r: CGFloat) -> CGPoint {
        CGPoint(x: center.x + cos(angle(t)) * r, y: center.y + sin(angle(t)) * r)
    }

    // Track
    ctx.setLineCap(.round)
    ctx.setLineWidth(34)
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.10).cgColor)
    ctx.addArc(center: center, radius: radius, startAngle: angle(0), endAngle: angle(1), clockwise: true)
    ctx.strokePath()
    // Redline zone
    ctx.setStrokeColor(red.cgColor)
    ctx.addArc(center: center, radius: radius, startAngle: angle(0.78), endAngle: angle(1), clockwise: true)
    ctx.strokePath()

    // Ticks
    for i in 0...20 {
        let t = CGFloat(i) / 20
        let major = i % 5 == 0
        ctx.setLineCap(.round)
        ctx.setLineWidth(major ? 14 : 7)
        ctx.setStrokeColor((t >= 0.78 ? redBright : ink.withAlphaComponent(major ? 0.95 : 0.55)).cgColor)
        ctx.move(to: point(t, radius - 52))
        ctx.addLine(to: point(t, radius - (major ? 112 : 84)))
        ctx.strokePath()
    }

    // Needle, sitting just short of the redline
    let needle = point(0.70, radius - 40)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 30, color: red.withAlphaComponent(0.8).cgColor)
    ctx.setLineCap(.round)
    ctx.setLineWidth(26)
    ctx.setStrokeColor(redBright.cgColor)
    ctx.move(to: point(0.70 - 0.5, 60))  // short tail behind the hub
    ctx.addLine(to: needle)
    ctx.strokePath()
    ctx.restoreGState()

    // Hub
    ctx.setFillColor(ink.cgColor)
    ctx.fillEllipse(in: CGRect(x: center.x - 46, y: center.y - 46, width: 92, height: 92))
    ctx.setFillColor(red.cgColor)
    ctx.fillEllipse(in: CGRect(x: center.x - 20, y: center.y - 20, width: 40, height: 40))

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
