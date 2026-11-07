// Renders DockPeek's app icon with CoreGraphics and writes an .iconset (all macOS sizes).
// Usage: swiftc Tools/make-icon/main.swift -o build/make-icon && build/make-icon build/AppIcon.iconset
//        iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
import AppKit

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func roundedRect(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func fillGradient(_ ctx: CGContext, _ path: CGPath, _ colors: [CGColor], from: CGPoint, to: CGPoint) {
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: nil)!
    ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}

/// Draws the icon on a 1024×1024 canvas (origin bottom-left), using Apple's icon grid:
/// an 824×824 rounded square centred with 100 px margins.
func drawIcon(_ ctx: CGContext) {
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = roundedRect(tile, 185)

    // Soft drop shadow under the whole tile.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0x000000, 0.35))
    ctx.addPath(tilePath)
    ctx.setFillColor(rgb(0x1B2A4E))
    ctx.fillPath()
    ctx.restoreGState()

    // Background: deep navy with a teal glow from the top.
    fillGradient(ctx, tilePath, [rgb(0x34508F), rgb(0x16224A), rgb(0x0C1430)],
                 from: CGPoint(x: 512, y: 924), to: CGPoint(x: 512, y: 100))
    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                          colors: [rgb(0x4FD1C5, 0.35), rgb(0x4FD1C5, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 600), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 600), endRadius: 420, options: [])
    ctx.restoreGState()

    // Dock: frosted bar near the bottom with three app tiles; the middle one is "hovered".
    let dock = CGRect(x: 214, y: 196, width: 596, height: 132)
    ctx.addPath(roundedRect(dock, 40))
    ctx.setFillColor(rgb(0xFFFFFF, 0.16))
    ctx.fillPath()
    ctx.addPath(roundedRect(dock.insetBy(dx: 1.5, dy: 1.5), 39))
    ctx.setStrokeColor(rgb(0xFFFFFF, 0.28))
    ctx.setLineWidth(3)
    ctx.strokePath()

    let appSize: CGFloat = 96
    let centers: [CGFloat] = [512 - 150, 512, 512 + 150]
    let appColors: [(UInt32, UInt32)] = [(0xFF8A65, 0xF4511E), (0x4FD1C5, 0x2C9C93), (0xFFD166, 0xF2A900)]
    for (i, cx) in centers.enumerated() {
        let r = CGRect(x: cx - appSize / 2, y: dock.midY - appSize / 2 + 8, width: appSize, height: appSize)
        let p = roundedRect(r, 24)
        fillGradient(ctx, p, [rgb(appColors[i].0), rgb(appColors[i].1)],
                     from: CGPoint(x: r.midX, y: r.maxY), to: CGPoint(x: r.midX, y: r.minY))
    }
    // "Running" dot under the hovered app.
    ctx.setFillColor(rgb(0xFFFFFF, 0.9))
    ctx.fillEllipse(in: CGRect(x: 512 - 7, y: dock.minY + 3, width: 14, height: 14))

    // Preview card floating above the middle app, with a pointer down to it.
    let card = CGRect(x: 512 - 250, y: 392, width: 500, height: 340)
    let pointer = CGMutablePath()
    pointer.move(to: CGPoint(x: 512 - 34, y: card.minY + 2))
    pointer.addLine(to: CGPoint(x: 512, y: card.minY - 38))
    pointer.addLine(to: CGPoint(x: 512 + 34, y: card.minY + 2))
    pointer.closeSubpath()
    let cardShape = CGMutablePath()
    cardShape.addPath(roundedRect(card, 44))
    cardShape.addPath(pointer)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 34, color: rgb(0x000000, 0.45))
    ctx.addPath(cardShape)
    ctx.setFillColor(rgb(0xF7F9FC))
    ctx.fillPath()
    ctx.restoreGState()
    fillGradient(ctx, cardShape, [rgb(0xFFFFFF), rgb(0xE6ECF5)],
                 from: CGPoint(x: 512, y: card.maxY), to: CGPoint(x: 512, y: card.minY - 38))

    // Mini window inside the card: title bar with traffic lights, then content lines.
    let win = card.insetBy(dx: 34, dy: 34)
    ctx.addPath(roundedRect(win, 22))
    ctx.setFillColor(rgb(0xFFFFFF))
    ctx.fillPath()
    ctx.addPath(roundedRect(win, 22))
    ctx.setStrokeColor(rgb(0x1B2A4E, 0.10))
    ctx.setLineWidth(3)
    ctx.strokePath()

    let barH: CGFloat = 52
    let bar = CGRect(x: win.minX, y: win.maxY - barH, width: win.width, height: barH)
    ctx.saveGState()
    ctx.addPath(roundedRect(win, 22))
    ctx.clip()
    ctx.setFillColor(rgb(0xEEF2F8))
    ctx.fill(bar)
    ctx.restoreGState()
    for (i, c) in [0xFF5F57, 0xFEBC2E, 0x28C840].enumerated() {
        ctx.setFillColor(rgb(UInt32(c)))
        ctx.fillEllipse(in: CGRect(x: win.minX + 22 + CGFloat(i) * 34, y: bar.midY - 11, width: 22, height: 22))
    }

    let lineX = win.minX + 30
    let widths: [CGFloat] = [0.78, 0.62, 0.52, 0.40]
    for (i, w) in widths.enumerated() {
        let y = bar.minY - 44 - CGFloat(i) * 42
        ctx.addPath(roundedRect(CGRect(x: lineX, y: y, width: (win.width - 60) * w, height: 18), 9))
        ctx.setFillColor(i == 0 ? rgb(0x34508F, 0.55) : rgb(0x1B2A4E, 0.16))
        ctx.fillPath()
    }
    // Accent block on the right, like an image in the window.
    let img = CGRect(x: win.maxX - 30 - 112, y: win.minY + 28, width: 112, height: 84)
    fillGradient(ctx, roundedRect(img, 14), [rgb(0x4FD1C5), rgb(0x34508F)],
                 from: CGPoint(x: img.minX, y: img.maxY), to: CGPoint(x: img.maxX, y: img.minY))
}

func render(px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let gc = NSGraphicsContext(bitmapImageRep: rep)!
    let ctx = gc.cgContext
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: CGFloat(px) / 1024, y: CGFloat(px) / 1024)
    drawIcon(ctx)
    gc.flushGraphics()
    return rep.representation(using: .png, properties: [:])!
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try render(px: base).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base).png"))
    try render(px: base * 2).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base)@2x.png"))
}
print("Wrote \(out)")
