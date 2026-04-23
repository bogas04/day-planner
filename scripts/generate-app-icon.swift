#!/usr/bin/env swift

import AppKit

enum IconGenerationError: Error {
    case missingOutputDirectory
    case failedToCreatePNGData(name: String)
}

let args = CommandLine.arguments
guard args.count >= 2 else {
    throw IconGenerationError.missingOutputDirectory
}

let outputDirectory = URL(fileURLWithPath: args[1], isDirectory: true)
let fileManager = FileManager.default

try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let iconDefinitions: [(name: String, size: CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for definition in iconDefinitions {
    let image = makeDockIcon(size: NSSize(width: definition.size, height: definition.size))
    let destination = outputDirectory.appendingPathComponent(definition.name)
    try writePNG(image: image, to: destination, name: definition.name)
}

func makeDockIcon(size: NSSize) -> NSImage {
    let image = NSImage(size: size)
    image.lockFocus()

    let rect = NSRect(origin: .zero, size: size).insetBy(dx: size.width * 0.08, dy: size.height * 0.08)
    let corner = size.width * 0.22

    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.13, green: 0.62, blue: 0.43, alpha: 1.0),
        NSColor(calibratedRed: 0.09, green: 0.49, blue: 0.35, alpha: 1.0)
    ])
    let roundedRect = NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner)
    gradient?.draw(in: roundedRect, angle: -90)

    NSColor.black.withAlphaComponent(0.1).setStroke()
    roundedRect.lineWidth = size.width * 0.015
    roundedRect.stroke()

    let checkPath = NSBezierPath()
    checkPath.move(to: NSPoint(x: rect.minX + rect.width * 0.23, y: rect.minY + rect.height * 0.52))
    checkPath.line(to: NSPoint(x: rect.minX + rect.width * 0.43, y: rect.minY + rect.height * 0.30))
    checkPath.line(to: NSPoint(x: rect.minX + rect.width * 0.77, y: rect.minY + rect.height * 0.68))
    checkPath.lineCapStyle = .round
    checkPath.lineJoinStyle = .round
    checkPath.lineWidth = size.width * 0.10

    NSColor.white.setStroke()
    checkPath.stroke()

    image.unlockFocus()
    return image
}

func writePNG(image: NSImage, to url: URL, name: String) throws {
    guard
        let tiffData = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiffData),
        let pngData = bitmap.representation(using: .png, properties: [:])
    else {
        throw IconGenerationError.failedToCreatePNGData(name: name)
    }

    try pngData.write(to: url)
}
