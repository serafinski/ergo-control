// Original vector artwork for Ergo Control. MIT licensed with this repository.
// Regenerate: swift tools/render_icons.swift resources
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "resources", isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
    NSColor(srgbRed: red / 255, green: green / 255, blue: blue / 255, alpha: 1)
}

func roundRect(_ rect: NSRect, radius: CGFloat, fill: NSColor) {
    fill.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}

func keyboardHalf(left: Bool, template: Bool) {
    NSGraphicsContext.saveGraphicsState()
    let transform = NSAffineTransform()
    let center = NSPoint(x: left ? 340 : 684, y: 440)
    transform.translateX(by: center.x, yBy: center.y)
    transform.rotate(byDegrees: left ? -10 : 10)
    transform.translateX(by: -center.x, yBy: -center.y)
    transform.concat()
    let x: CGFloat = left ? 174 : 540
    let outline = template ? NSColor.black : color(194, 232, 216)
    let panel = NSBezierPath(roundedRect: NSRect(x: x, y: 270, width: 310, height: 340), xRadius: 42, yRadius: 42)
    if !template {
        color(29, 63, 55).setFill(); panel.fill()
    }
    outline.setStroke(); panel.lineWidth = template ? 36 : 12; panel.stroke()
    for row in 0..<3 {
        for column in 0..<3 {
            let fill = template ? NSColor.black : (row == 2 && column == (left ? 2 : 0) ? color(87, 226, 172) : color(225, 245, 234))
            roundRect(NSRect(x: x + 38 + CGFloat(column) * 82, y: 362 + CGFloat(row) * 72,
                             width: 64, height: 50), radius: template ? 8 : 12, fill: fill)
        }
    }
    roundRect(NSRect(x: x + 38, y: 303, width: 228, height: 36), radius: 12,
              fill: template ? .black : color(87, 226, 172))
    NSGraphicsContext.restoreGraphicsState()
}

func artwork(template: Bool) {
    if !template {
        let base = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 200, yRadius: 200)
        NSGradient(starting: color(40, 80, 68), ending: color(12, 30, 27))!.draw(in: base, angle: -75)
        color(84, 137, 114).withAlphaComponent(0.35).setStroke()
        base.lineWidth = 3; base.stroke()
    }
    keyboardHalf(left: true, template: template)
    keyboardHalf(left: false, template: template)
    let dial = NSBezierPath(ovalIn: NSRect(x: 674, y: 672, width: 148, height: 148))
    if !template { color(87, 226, 172).setFill(); dial.fill() }
    (template ? NSColor.black : color(151, 255, 208)).setStroke()
    dial.lineWidth = template ? 36 : 12; dial.stroke()
    let notch = NSBezierPath()
    notch.move(to: NSPoint(x: 748, y: 780)); notch.line(to: NSPoint(x: 748, y: 802))
    notch.lineCapStyle = .round; notch.lineWidth = template ? 34 : 13
    (template ? NSColor.black : color(20, 56, 45)).setStroke(); notch.stroke()
    if !template {
        let center = NSBezierPath(ovalIn: NSRect(x: 719, y: 717, width: 58, height: 58))
        color(34, 99, 74).setStroke(); center.lineWidth = 8; center.stroke()
    }
}

func png(size: Int, template: Bool = false) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                                  samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                  bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let scale = NSAffineTransform()
    scale.scale(by: CGFloat(size) / 1024)
    scale.concat()
    artwork(template: template)
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}


try png(size: 1024).write(to: output.appendingPathComponent("AppIcon.png"))
let iconset = output.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 2 ? "@2x" : ""
        try png(size: points * scale).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
    }
}
let converter = Process()
converter.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
converter.arguments = ["-c", "icns", iconset.path, "-o", output.appendingPathComponent("AppIcon.icns").path]
try converter.run(); converter.waitUntilExit()
guard converter.terminationStatus == 0 else { fatalError("Could not package AppIcon.icns") }
try FileManager.default.removeItem(at: iconset)
try png(size: 18, template: true).write(to: output.appendingPathComponent("ErgoMarkTemplate.png"))
try png(size: 36, template: true).write(to: output.appendingPathComponent("ErgoMarkTemplate@2x.png"))
print("Rendered app and menu-bar icons in \(output.path)")
