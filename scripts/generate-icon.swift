import AppKit
import CoreGraphics
import Foundation

let outputDirPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/AppIcon.iconset"
let fm = FileManager.default
try? fm.removeItem(atPath: outputDirPath)
try fm.createDirectory(atPath: outputDirPath, withIntermediateDirectories: true)

struct IconSpec {
    let filename: String
    let pixelSize: Int
}

let specs: [IconSpec] = [
    IconSpec(filename: "icon_16x16.png", pixelSize: 16),
    IconSpec(filename: "icon_16x16@2x.png", pixelSize: 32),
    IconSpec(filename: "icon_32x32.png", pixelSize: 32),
    IconSpec(filename: "icon_32x32@2x.png", pixelSize: 64),
    IconSpec(filename: "icon_128x128.png", pixelSize: 128),
    IconSpec(filename: "icon_128x128@2x.png", pixelSize: 256),
    IconSpec(filename: "icon_256x256.png", pixelSize: 256),
    IconSpec(filename: "icon_256x256@2x.png", pixelSize: 512),
    IconSpec(filename: "icon_512x512.png", pixelSize: 512),
    IconSpec(filename: "icon_512x512@2x.png", pixelSize: 1024)
]

func renderIcon(size: Int) throws -> Data {
    let s = CGFloat(size)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw NSError(domain: "IconGen", code: 1)
    }

    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)

    // macOS squircle inset
    let inset = s * 0.08
    let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = rect.width * 0.225
    let squircle = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Deep slate-navy background gradient
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()
    let bgColors = [
        CGColor(red: 0.08, green: 0.12, blue: 0.19, alpha: 1.0),
        CGColor(red: 0.05, green: 0.08, blue: 0.13, alpha: 1.0)
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: s * 0.5, y: s - inset),
            end: CGPoint(x: s * 0.5, y: inset),
            options: []
        )
    }
    ctx.restoreGState()

    // Subtle crisp border
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.setStrokeColor(CGColor(red: 0.30, green: 0.45, blue: 0.65, alpha: 0.38))
    ctx.setLineWidth(max(1.0, s * 0.012))
    ctx.strokePath()
    ctx.restoreGState()

    // Precision storage gauge arc
    let center = CGPoint(x: s * 0.5, y: s * 0.5)
    let arcRadius = s * 0.26
    let strokeWidth = max(2.0, s * 0.072)

    // Track arc
    ctx.saveGState()
    ctx.setLineCap(.round)
    ctx.setLineWidth(strokeWidth)
    ctx.setStrokeColor(CGColor(red: 0.18, green: 0.25, blue: 0.35, alpha: 1.0))
    ctx.addArc(center: center, radius: arcRadius, startAngle: .pi * 0.78, endAngle: .pi * 2.22, clockwise: false)
    ctx.strokePath()
    ctx.restoreGState()

    // Reclaimed emerald-cyan arc
    ctx.saveGState()
    ctx.setLineCap(.round)
    ctx.setLineWidth(strokeWidth)
    ctx.setStrokeColor(CGColor(red: 0.16, green: 0.80, blue: 0.62, alpha: 1.0))
    ctx.addArc(center: center, radius: arcRadius, startAngle: .pi * 0.78, endAngle: .pi * 1.85, clockwise: false)
    ctx.strokePath()
    ctx.restoreGState()

    // Center geometric X / Spark mark
    let markHalf = s * 0.095
    let markWidth = max(1.5, s * 0.045)
    ctx.saveGState()
    ctx.setLineCap(.round)
    ctx.setLineWidth(markWidth)
    ctx.setStrokeColor(CGColor(red: 0.94, green: 0.97, blue: 1.0, alpha: 1.0))
    ctx.move(to: CGPoint(x: center.x - markHalf, y: center.y - markHalf))
    ctx.addLine(to: CGPoint(x: center.x + markHalf, y: center.y + markHalf))
    ctx.move(to: CGPoint(x: center.x - markHalf, y: center.y + markHalf))
    ctx.addLine(to: CGPoint(x: center.x + markHalf, y: center.y - markHalf))
    ctx.strokePath()
    ctx.restoreGState()

    guard let cgImage = ctx.makeImage() else {
        throw NSError(domain: "IconGen", code: 2)
    }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    guard let pngData = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "IconGen", code: 3)
    }
    return pngData
}

for spec in specs {
    let data = try renderIcon(size: spec.pixelSize)
    let url = URL(fileURLWithPath: outputDirPath).appendingPathComponent(spec.filename)
    try data.write(to: url)
}
