#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation

let rootDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resourcesDir = rootDir.appendingPathComponent("Sources/UsageCenter/Resources", isDirectory: true)
let iconsetDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("UsageCenter.iconset", isDirectory: true)

try? FileManager.default.removeItem(at: iconsetDir)
try FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: resourcesDir, withIntermediateDirectories: true)

func renderIcon(pixelSize: Int) -> Data {
    let s = CGFloat(pixelSize)
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(
        data: nil,
        width: pixelSize,
        height: pixelSize,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!

    ctx.interpolationQuality = .high
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)

    let pad = s * 0.09765625 // 100 / 1024 standard macOS icon inset
    let rect = CGRect(x: pad, y: pad, width: s - pad * 2, height: s - pad * 2)
    let radius = rect.width * 0.225
    let squircle = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Outer soft drop shadow
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -s * 0.018),
        blur: s * 0.042,
        color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.42)
    )
    ctx.setFillColor(CGColor(srgbRed: 0.05, green: 0.10, blue: 0.18, alpha: 1.0))
    ctx.addPath(squircle)
    ctx.fillPath()
    ctx.restoreGState()

    // Clip to squircle for Liquid Glass interior
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()

    // Deep Liquid Glass gradient backdrop
    let bgColors = [
        CGColor(srgbRed: 0.10, green: 0.22, blue: 0.36, alpha: 1.0),
        CGColor(srgbRed: 0.05, green: 0.11, blue: 0.20, alpha: 1.0),
        CGColor(srgbRed: 0.03, green: 0.06, blue: 0.12, alpha: 1.0)
    ] as CFArray
    let bgGrad = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 0.55, 1.0])!
    ctx.drawLinearGradient(
        bgGrad,
        start: CGPoint(x: rect.minX, y: rect.maxY),
        end: CGPoint(x: rect.maxX, y: rect.minY),
        options: []
    )

    // Top-left cyan glass refraction glow
    let glowColors = [
        CGColor(srgbRed: 0.30, green: 0.84, blue: 0.96, alpha: 0.36),
        CGColor(srgbRed: 0.20, green: 0.62, blue: 0.95, alpha: 0.0)
    ] as CFArray
    let glowGrad = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: [0.0, 1.0])!
    ctx.drawRadialGradient(
        glowGrad,
        startCenter: CGPoint(x: rect.minX + rect.width * 0.24, y: rect.maxY - rect.height * 0.20),
        startRadius: 0,
        endCenter: CGPoint(x: rect.minX + rect.width * 0.24, y: rect.maxY - rect.height * 0.20),
        endRadius: rect.width * 0.72,
        options: []
    )

    let center = CGPoint(x: s * 0.5, y: s * 0.5)
    let outerR = rect.width * 0.305
    let outerW = rect.width * 0.072
    let innerR = rect.width * 0.195
    let innerW = rect.width * 0.056

    func strokeRing(radius: CGFloat, lineWidth: CGFloat, startDeg: CGFloat, endDeg: CGFloat, color: CGColor) {
        ctx.saveGState()
        ctx.setStrokeColor(color)
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.round)
        let path = CGMutablePath()
        path.addArc(
            center: center,
            radius: radius,
            startAngle: startDeg * .pi / 180.0,
            endAngle: endDeg * .pi / 180.0,
            clockwise: true
        )
        ctx.addPath(path)
        ctx.strokePath()
        ctx.restoreGState()
    }

    // Tracks
    strokeRing(
        radius: outerR,
        lineWidth: outerW,
        startDeg: 0,
        endDeg: 360,
        color: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.14)
    )
    strokeRing(
        radius: innerR,
        lineWidth: innerW,
        startDeg: 0,
        endDeg: 360,
        color: CGColor(srgbRed: 0.34, green: 0.76, blue: 1.0, alpha: 0.18)
    )

    // Luminous Outer Quota Arc (82% remaining)
    ctx.saveGState()
    ctx.setShadow(
        offset: .zero,
        blur: s * 0.025,
        color: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.45)
    )
    strokeRing(
        radius: outerR,
        lineWidth: outerW,
        startDeg: 90,
        endDeg: 90 - 295,
        color: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.98)
    )
    ctx.restoreGState()

    // Luminous Inner Time Arc (64% remaining)
    ctx.saveGState()
    ctx.setShadow(
        offset: .zero,
        blur: s * 0.022,
        color: CGColor(srgbRed: 0.34, green: 0.80, blue: 1.0, alpha: 0.55)
    )
    strokeRing(
        radius: innerR,
        lineWidth: innerW,
        startDeg: 90,
        endDeg: 90 - 232,
        color: CGColor(srgbRed: 0.36, green: 0.82, blue: 1.0, alpha: 1.0)
    )
    ctx.restoreGState()

    // Central 4-point star / pulse node symbolizing unified 4 AI providers
    let starR = rect.width * 0.082
    let starInner = starR * 0.34
    let starPath = CGMutablePath()
    for i in 0..<8 {
        let angle = CGFloat(i) * (.pi / 4.0) - (.pi / 2.0)
        let rad = (i % 2 == 0) ? starR : starInner
        let pt = CGPoint(x: center.x + cos(angle) * rad, y: center.y + sin(angle) * rad)
        if i == 0 {
            starPath.move(to: pt)
        } else {
            starPath.addLine(to: pt)
        }
    }
    starPath.closeSubpath()
    ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.96))
    ctx.addPath(starPath)
    ctx.fillPath()

    // Crisp Liquid Glass inner rim stroke
    ctx.addPath(squircle)
    ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.28))
    ctx.setLineWidth(max(1.0, s * 0.004))
    ctx.strokePath()

    ctx.restoreGState()

    let cgImg = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: cgImg)
    return rep.representation(using: .png, properties: [:])!
}

let specs: [(String, Int)] = [
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

for (name, px) in specs {
    let png = renderIcon(pixelSize: px)
    try png.write(to: iconsetDir.appendingPathComponent(name))
}

let icnsPath = resourcesDir.appendingPathComponent("AppIcon.icns")
let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", iconsetDir.path, "-o", icnsPath.path]
try proc.run()
proc.waitUntilExit()
guard proc.terminationStatus == 0 else {
    fputs("iconutil failed\n", stderr)
    exit(1)
}
print("Generated \(icnsPath.path)")
