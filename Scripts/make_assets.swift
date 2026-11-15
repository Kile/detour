// Generates the debug test photos (the app icon comes from Design/brand/).
// Usage: swift Scripts/make_assets.swift <repo-root>
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)

func makeBitmap(width: Int, height: Int, draw: (CGContext) -> Void) -> NSBitmapImageRep {
    // Opaque (no alpha), which App Store icons require.
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    draw(ctx)
    NSGraphicsContext.restoreGraphicsState()
    return NSBitmapImageRep(cgImage: ctx.makeImage()!)
}

func write(_ rep: NSBitmapImageRep, to path: String, type: NSBitmapImageRep.FileType) {
    let url = root.appendingPathComponent(path)
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let props: [NSBitmapImageRep.PropertyKey: Any] = type == .jpeg ? [.compressionFactor: 0.85] : [:]
    try! rep.representation(using: type, properties: props)!.write(to: url)
    print("wrote \(path)")
}

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(red: r, green: g, blue: b, alpha: a) }

func text(_ string: String, at point: CGPoint, size: CGFloat, color: NSColor, weight: NSFont.Weight = .bold, rotate: CGFloat = 0, ctx: CGContext) {
    ctx.saveGState()
    ctx.translateBy(x: point.x, y: point.y)
    ctx.rotate(by: rotate)
    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color]
    NSAttributedString(string: string, attributes: attributes).draw(at: .zero)
    ctx.restoreGState()
}

// The app icon is rendered from Design/brand/detour-app-icon.svg (see README → Brand).

// MARK: Test photos (1200×900)

func vase(in ctx: CGContext, center: CGFloat, base: CGFloat, scale: CGFloat) {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: center - 70 * scale, y: base))
    path.addCurve(to: CGPoint(x: center - 45 * scale, y: base + 330 * scale),
                  control1: CGPoint(x: center - 230 * scale, y: base + 120 * scale),
                  control2: CGPoint(x: center - 150 * scale, y: base + 260 * scale))
    path.addLine(to: CGPoint(x: center - 60 * scale, y: base + 400 * scale))
    path.addLine(to: CGPoint(x: center + 60 * scale, y: base + 400 * scale))
    path.addLine(to: CGPoint(x: center + 45 * scale, y: base + 330 * scale))
    path.addCurve(to: CGPoint(x: center + 70 * scale, y: base),
                  control1: CGPoint(x: center + 150 * scale, y: base + 260 * scale),
                  control2: CGPoint(x: center + 230 * scale, y: base + 120 * scale))
    path.closeSubpath()
    ctx.addPath(path)
    ctx.setFillColor(color(0.93, 0.92, 0.86))
    ctx.fillPath()
    // Blue willow-style bands and flowers.
    ctx.setStrokeColor(color(0.15, 0.27, 0.6))
    ctx.setLineWidth(10 * scale)
    for y in [base + 60 * scale, base + 300 * scale] {
        ctx.move(to: CGPoint(x: center - 130 * scale, y: y))
        ctx.addLine(to: CGPoint(x: center + 130 * scale, y: y))
    }
    ctx.strokePath()
    ctx.setFillColor(color(0.15, 0.27, 0.6))
    for (dx, dy) in [(-60, 160), (40, 200), (0, 120), (70, 130), (-20, 230)] {
        ctx.fillEllipse(in: CGRect(x: center + CGFloat(dx) * scale - 18 * scale, y: base + CGFloat(dy) * scale - 18 * scale,
                                   width: 36 * scale, height: 36 * scale))
    }
    // Crazing / age marks.
    ctx.setStrokeColor(color(0.55, 0.5, 0.4, 0.5))
    ctx.setLineWidth(2)
    for i in 0..<14 {
        let x = center - 110 * scale + CGFloat(i) * 16 * scale
        ctx.move(to: CGPoint(x: x, y: base + 80 * scale))
        ctx.addLine(to: CGPoint(x: x + 12 * scale, y: base + 180 * scale))
    }
    ctx.strokePath()
}

func shelf(in ctx: CGContext) {
    ctx.setFillColor(color(0.36, 0.24, 0.16))
    ctx.fill(CGRect(x: 0, y: 0, width: 1200, height: 300))
    ctx.setFillColor(color(0.46, 0.31, 0.2))
    ctx.fill(CGRect(x: 0, y: 260, width: 1200, height: 40))
    ctx.setFillColor(color(0.83, 0.78, 0.68))
    ctx.fill(CGRect(x: 0, y: 300, width: 1200, height: 600))
}

let pass = makeBitmap(width: 1200, height: 900) { ctx in
    shelf(in: ctx)
    vase(in: ctx, center: 520, base: 290, scale: 1.25)
    // Paper price tag on a string.
    ctx.setStrokeColor(color(0.3, 0.3, 0.3))
    ctx.setLineWidth(3)
    ctx.move(to: CGPoint(x: 600, y: 760))
    ctx.addLine(to: CGPoint(x: 800, y: 560))
    ctx.strokePath()
    ctx.setFillColor(color(0.98, 0.96, 0.88))
    ctx.fill(CGRect(x: 760, y: 420, width: 250, height: 150))
    text("c. 1950s", at: CGPoint(x: 785, y: 505), size: 40, color: .black, ctx: ctx)
    text("Willow vase", at: CGPoint(x: 785, y: 465), size: 30, color: .darkGray, weight: .medium, ctx: ctx)
    text("£24", at: CGPoint(x: 785, y: 428), size: 34, color: NSColor(red: 0.7, green: 0.1, blue: 0.1, alpha: 1), ctx: ctx)
}
write(pass, to: "SideQuest/Resources/DebugTestPhotos/debug_test_pass.jpg", type: .jpeg)

let unsure = makeBitmap(width: 1200, height: 900) { ctx in
    shelf(in: ctx)
    vase(in: ctx, center: 1080, base: 290, scale: 1.1)   // mostly out of frame
    // Dim, low-contrast "bad lighting" wash plus motion streaks.
    ctx.setFillColor(color(0.05, 0.05, 0.08, 0.55))
    ctx.fill(CGRect(x: 0, y: 0, width: 1200, height: 900))
    ctx.setStrokeColor(color(1, 1, 1, 0.08))
    ctx.setLineWidth(30)
    for i in 0..<12 {
        ctx.move(to: CGPoint(x: -100 + i * 120, y: 0))
        ctx.addLine(to: CGPoint(x: 100 + i * 120, y: 900))
    }
    ctx.strokePath()
}
write(unsure, to: "SideQuest/Resources/DebugTestPhotos/debug_test_unsure.jpg", type: .jpeg)

let fail = makeBitmap(width: 1200, height: 900) { ctx in
    // A plain office wall with a light switch: clearly not the quest.
    ctx.setFillColor(color(0.9, 0.88, 0.84))
    ctx.fill(CGRect(x: 0, y: 0, width: 1200, height: 900))
    ctx.setFillColor(color(0.75, 0.73, 0.7))
    ctx.fill(CGRect(x: 0, y: 0, width: 1200, height: 90))
    ctx.setFillColor(color(0.98, 0.98, 0.97))
    ctx.fill(CGRect(x: 540, y: 400, width: 120, height: 180))
    ctx.setFillColor(color(0.85, 0.85, 0.84))
    ctx.fill(CGRect(x: 580, y: 450, width: 40, height: 80))
}
write(fail, to: "SideQuest/Resources/DebugTestPhotos/debug_test_fail.jpg", type: .jpeg)
