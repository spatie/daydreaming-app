import AppKit

let size = 1024
let output = CommandLine.arguments[1]
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let bounds = NSRect(x: 0, y: 0, width: size, height: size)
let frame = NSBezierPath(roundedRect: bounds.insetBy(dx: 28, dy: 28), xRadius: 224, yRadius: 224)
frame.addClip()

let sky = NSGradient(colorsAndLocations:
    (NSColor(calibratedRed: 0.08, green: 0.14, blue: 0.20, alpha: 1), 0),
    (NSColor(calibratedRed: 0.25, green: 0.31, blue: 0.39, alpha: 1), 0.53),
    (NSColor(calibratedRed: 0.79, green: 0.47, blue: 0.31, alpha: 1), 1)
)!
sky.draw(in: frame, angle: 90)

let sun = NSBezierPath(ovalIn: NSRect(x: 360, y: 330, width: 365, height: 365))
NSGradient(starting: NSColor(calibratedRed: 1, green: 0.90, blue: 0.67, alpha: 1),
           ending: NSColor(calibratedRed: 0.96, green: 0.65, blue: 0.40, alpha: 1))!
    .draw(in: sun, angle: 90)

func ridge(_ points: [NSPoint], color: NSColor) {
    let path = NSBezierPath()
    path.move(to: points[0])
    for point in points.dropFirst() { path.line(to: point) }
    path.close()
    color.setFill()
    path.fill()
}

ridge([
    NSPoint(x: 0, y: 370), NSPoint(x: 235, y: 478),
    NSPoint(x: 420, y: 395), NSPoint(x: 680, y: 510),
    NSPoint(x: 1024, y: 375), NSPoint(x: 1024, y: 0),
    NSPoint(x: 0, y: 0),
], color: NSColor(calibratedRed: 0.18, green: 0.25, blue: 0.29, alpha: 1))

ridge([
    NSPoint(x: 0, y: 220), NSPoint(x: 255, y: 330),
    NSPoint(x: 485, y: 245), NSPoint(x: 760, y: 380),
    NSPoint(x: 1024, y: 280), NSPoint(x: 1024, y: 0),
    NSPoint(x: 0, y: 0),
], color: NSColor(calibratedRed: 0.07, green: 0.13, blue: 0.16, alpha: 1))

NSColor(calibratedWhite: 1, alpha: 0.55).setFill()
for (x, y, radius) in [(224.0, 750.0, 5.0), (316, 835, 3), (748, 777, 4)] {
    NSBezierPath(ovalIn: NSRect(x: x, y: y, width: radius * 2, height: radius * 2)).fill()
}

image.unlockFocus()
let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size,
    pixelsHigh: size,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
