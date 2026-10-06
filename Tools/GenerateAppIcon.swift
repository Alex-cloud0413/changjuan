import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: GenerateAppIcon.swift OUTPUT.png\n", stderr)
    exit(2)
}

let canvas = NSSize(width: 1024, height: 1024)
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvas.width),
    pixelsHigh: Int(canvas.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 32
) else {
    fatalError("Could not create icon bitmap")
}

bitmap.size = canvas
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

let background = NSBezierPath(rect: NSRect(origin: .zero, size: canvas))
let gradient = NSGradient(colors: [
    NSColor(red: 0.04, green: 0.48, blue: 0.98, alpha: 1),
    NSColor(red: 0.27, green: 0.15, blue: 0.82, alpha: 1)
])!
gradient.draw(in: background, angle: -52)

NSColor(calibratedWhite: 0, alpha: 0.16).setFill()
NSBezierPath(
    roundedRect: NSRect(x: 235, y: 123, width: 594, height: 744),
    xRadius: 104,
    yRadius: 104
).fill()

NSColor.white.setFill()
NSBezierPath(
    roundedRect: NSRect(x: 205, y: 153, width: 594, height: 744),
    xRadius: 104,
    yRadius: 104
).fill()

let ink = NSColor(red: 0.08, green: 0.39, blue: 0.93, alpha: 1)
ink.setStroke()

for y in [730.0, 630.0, 530.0] {
    let line = NSBezierPath()
    line.lineWidth = 30
    line.lineCapStyle = .round
    line.move(to: NSPoint(x: 315, y: y))
    line.line(to: NSPoint(x: y == 630 ? 620 : 690, y: y))
    line.stroke()
}

let arrow = NSBezierPath()
arrow.lineWidth = 38
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
arrow.move(to: NSPoint(x: 502, y: 445))
arrow.line(to: NSPoint(x: 502, y: 287))
arrow.move(to: NSPoint(x: 415, y: 364))
arrow.line(to: NSPoint(x: 502, y: 277))
arrow.line(to: NSPoint(x: 589, y: 364))
arrow.stroke()

NSGraphicsContext.restoreGraphicsState()

guard let jpeg = bitmap.representation(
    using: .jpeg,
    properties: [.compressionFactor: 1.0]
), let opaqueBitmap = NSBitmapImageRep(data: jpeg),
   let png = opaqueBitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode icon PNG")
}
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
