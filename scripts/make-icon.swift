import AppKit

// Original vector artwork for Mikro MIDI. No external image assets.
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "macos/AppIcon.iconset"
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: 1)
}

func drawIcon(size: Int, destination: String) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let transform = NSAffineTransform()
    transform.scale(by: CGFloat(size) / 1024)
    transform.concat()
    let body = NSBezierPath(roundedRect: NSRect(x: 56, y: 56, width: 912, height: 912), xRadius: 204, yRadius: 204)
    NSGradient(starting: color(0x253139), ending: color(0x10171C))!.draw(in: body, angle: -90)
    color(0x3E4B51).withAlphaComponent(0.75).setStroke()
    body.lineWidth = 5
    body.stroke()

    let palette: [UInt32] = [0xE8AD6B, 0xDE9B62, 0xDCA170, 0xC99674,
                             0x87C49E, 0x84CEA8, 0x82BFA6, 0x7FB8AC,
                             0x76D2BD, 0x76C6B8, 0x74BAAF, 0x76B4AC,
                             0xA0E8CE, 0x8DDFC5, 0x87C9C4, 0x83B8C5]
    let edge: CGFloat = 143, gap: CGFloat = 26, origin: CGFloat = 187
    for row in 0..<4 {
        for column in 0..<4 {
            let rect = NSRect(x: origin + CGFloat(column) * (edge + gap),
                              y: origin + CGFloat(row) * (edge + gap), width: edge, height: edge)
            let path = NSBezierPath(roundedRect: rect, xRadius: 25, yRadius: 25)
            let fill = color(palette[row * 4 + column])
            NSGradient(starting: fill, ending: fill.blended(withFraction: 0.17, of: .black)!)!.draw(in: path, angle: -90)
            fill.blended(withFraction: 0.28, of: .white)!.withAlphaComponent(0.8).setStroke()
            path.lineWidth = 2
            path.stroke()
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: destination))
}

for size in [16, 32, 128, 256, 512] {
    try drawIcon(size: size, destination: "\(output)/icon_\(size)x\(size).png")
    try drawIcon(size: size * 2, destination: "\(output)/icon_\(size)x\(size)@2x.png")
}
