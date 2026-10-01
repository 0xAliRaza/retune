// Renders Resources/AppIcon.icns: a rounded gradient tile with a play glyph.
import AppKit

let sizes = [16, 32, 64, 128, 256, 512, 1024]
let iconset = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(_ pixels: Int) -> Data {
    let size = CGFloat(pixels)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let inset = size * 0.09
    let tile = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let path = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)
    NSGradient(colors: [NSColor(red: 0.42, green: 0.25, blue: 0.95, alpha: 1), NSColor(red: 0.10, green: 0.45, blue: 0.98, alpha: 1)])!
        .draw(in: path, angle: -50)
    let glyph = NSBezierPath()
    let c = NSPoint(x: tile.midX + tile.width * 0.04, y: tile.midY)
    let r = tile.width * 0.24
    glyph.move(to: NSPoint(x: c.x - r * 0.75, y: c.y + r))
    glyph.line(to: NSPoint(x: c.x + r, y: c.y))
    glyph.line(to: NSPoint(x: c.x - r * 0.75, y: c.y - r))
    glyph.close()
    NSColor.white.withAlphaComponent(0.95).setFill()
    glyph.fill()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for size in sizes where size <= 512 {
    try render(size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
