import AppKit
let args = CommandLine.arguments
let size = Int(args[3]) ?? 512
guard let img = NSImage(contentsOf: URL(fileURLWithPath: args[1])) else { print("NSImage could not load SVG"); exit(1) }
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: size, height: size)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high
img.draw(in: NSRect(x: 0, y: 0, width: size, height: size), from: .zero, operation: .copy, fraction: 1)
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
let c = rep.colorAt(x: 0, y: 0)!, m = rep.colorAt(x: size/2, y: size/2)!
print("corner alpha \(c.alphaComponent), center RGBA \(m.redComponent) \(m.greenComponent) \(m.blueComponent) \(m.alphaComponent)")
