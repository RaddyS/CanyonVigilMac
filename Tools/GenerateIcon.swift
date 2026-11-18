import AppKit

// Original vector artwork, drawn locally without external assets.
let output = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)

func drawIcon(size: Int, path: String) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let context = NSGraphicsContext.current!.cgContext
    context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)

    let tile = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 200, yRadius: 200)
    NSGradient(starting: NSColor(srgbRed: 0.16, green: 0.18, blue: 0.23, alpha: 1),
        ending: NSColor(srgbRed: 0.045, green: 0.055, blue: 0.08, alpha: 1))!.draw(in: tile, angle: -90)
    NSColor.white.withAlphaComponent(0.13).setStroke()
    tile.lineWidth = 3; tile.stroke()

    let cable = NSBezierPath()
    cable.move(to: NSPoint(x: 512, y: 763))
    cable.curve(to: NSPoint(x: 638, y: 891), controlPoint1: NSPoint(x: 507, y: 868), controlPoint2: NSPoint(x: 614, y: 824))
    cable.lineWidth = 17; cable.lineCapStyle = .round
    NSColor(srgbRed: 1, green: 0.49, blue: 0.19, alpha: 1).setStroke(); cable.stroke()

    let body = NSBezierPath()
    body.move(to: NSPoint(x: 512, y: 791))
    body.curve(to: NSPoint(x: 320, y: 603), controlPoint1: NSPoint(x: 387, y: 791), controlPoint2: NSPoint(x: 320, y: 720))
    body.line(to: NSPoint(x: 303, y: 411))
    body.curve(to: NSPoint(x: 512, y: 215), controlPoint1: NSPoint(x: 292, y: 285), controlPoint2: NSPoint(x: 386, y: 215))
    body.curve(to: NSPoint(x: 721, y: 411), controlPoint1: NSPoint(x: 638, y: 215), controlPoint2: NSPoint(x: 732, y: 285))
    body.line(to: NSPoint(x: 704, y: 603))
    body.curve(to: NSPoint(x: 512, y: 791), controlPoint1: NSPoint(x: 704, y: 720), controlPoint2: NSPoint(x: 637, y: 791))
    body.close()
    NSGradient(starting: NSColor(srgbRed: 1, green: 0.66, blue: 0.31, alpha: 1),
        ending: NSColor(srgbRed: 0.97, green: 0.30, blue: 0.09, alpha: 1))!.draw(in: body, angle: -90)

    let dark = NSColor(srgbRed: 0.105, green: 0.115, blue: 0.15, alpha: 1)
    dark.setStroke()
    let seam = NSBezierPath(); seam.move(to: NSPoint(x: 512, y: 785)); seam.line(to: NSPoint(x: 512, y: 562))
    seam.lineWidth = 14; seam.stroke()
    let split = NSBezierPath(); split.move(to: NSPoint(x: 324, y: 548))
    split.curve(to: NSPoint(x: 700, y: 548), controlPoint1: NSPoint(x: 437, y: 514), controlPoint2: NSPoint(x: 587, y: 514))
    split.lineWidth = 14; split.stroke()
    dark.setFill()
    NSBezierPath(roundedRect: NSRect(x: 481, y: 620, width: 62, height: 115), xRadius: 30, yRadius: 30).fill()
    NSColor(srgbRed: 1, green: 0.87, blue: 0.63, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 503, y: 645, width: 18, height: 65), xRadius: 9, yRadius: 9).fill()

    // A small V for Vigil, distinct from the manufacturer's logo.
    let mark = NSBezierPath(); mark.move(to: NSPoint(x: 451, y: 419)); mark.line(to: NSPoint(x: 512, y: 343)); mark.line(to: NSPoint(x: 573, y: 419))
    mark.lineWidth = 21; mark.lineCapStyle = .round; mark.lineJoinStyle = .round
    dark.setStroke(); mark.stroke()
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

for size in [16, 32, 128, 256, 512] {
    try drawIcon(size: size, path: "\(output)/icon_\(size)x\(size).png")
    try drawIcon(size: size * 2, path: "\(output)/icon_\(size)x\(size)@2x.png")
}
