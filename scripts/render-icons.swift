// Rebuild with: swift scripts/render-icons.swift
// Original DockMate artwork, drawn with AppKit; no external assets or dependencies.
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resources = root.appendingPathComponent("Resources")
let iconset = root.appendingPathComponent("build/AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func rounded(_ rect: NSRect, radius: CGFloat, color: NSColor) {
    color.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}

func png(size: Int, logicalSize: CGFloat, draw: () -> Void) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let context = NSGraphicsContext.current!.cgContext
    context.clear(CGRect(x: 0, y: 0, width: logicalSize, height: logicalSize))
    context.scaleBy(x: CGFloat(size) / logicalSize, y: CGFloat(size) / logicalSize)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

let navy = NSColor(srgbRed: 0.08, green: 0.17, blue: 0.25, alpha: 1)
let white = NSColor(srgbRed: 0.96, green: 0.99, blue: 1, alpha: 1)

func drawAppIcon() {
    rounded(NSRect(x: 64, y: 64, width: 896, height: 896), radius: 200, color: navy)
    // One monitor outline, no extra symbols or detail.
    rounded(NSRect(x: 488, y: 292, width: 48, height: 118), radius: 8, color: white)
    rounded(NSRect(x: 396, y: 272, width: 232, height: 40), radius: 20, color: white)
    rounded(NSRect(x: 216, y: 380, width: 592, height: 372), radius: 36, color: white)
    rounded(NSRect(x: 256, y: 420, width: 512, height: 292), radius: 8, color: navy)
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 2 ? "@2x" : ""
        let data = png(size: points * scale, logicalSize: 1024, draw: drawAppIcon)
        try data.write(to: iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
    }
}
try png(size: 1024, logicalSize: 1024, draw: drawAppIcon)
    .write(to: resources.appendingPathComponent("AppIcon.png"))

func drawMenuIcon() {
    // Filled geometry stays crisp at menu bar sizes; rendered as a template.
    rounded(NSRect(x: 2, y: 6, width: 16, height: 11), radius: 1.5, color: .black)
    NSColor.clear.setFill()
    let context = NSGraphicsContext.current!.cgContext
    context.saveGState()
    context.setBlendMode(.clear)
    context.fill(CGRect(x: 3.5, y: 7.5, width: 13, height: 8))
    context.restoreGState()
    rounded(NSRect(x: 9, y: 3.5, width: 2, height: 3), radius: 0.5, color: .black)
    rounded(NSRect(x: 6, y: 3, width: 8, height: 1.5), radius: 0.75, color: .black)
}
for scale in [1, 2] {
    let suffix = scale == 2 ? "@2x" : ""
    try png(size: 20 * scale, logicalSize: 20, draw: drawMenuIcon)
        .write(to: resources.appendingPathComponent("MenuBarIcon\(suffix).png"))
}

let converter = Process()
converter.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
converter.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path]
try converter.run()
converter.waitUntilExit()
guard converter.terminationStatus == 0 else { exit(converter.terminationStatus) }
print("Generated DockMate app and menu bar icons.")
