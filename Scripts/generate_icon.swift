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

/// Straight-edged macOS icon silhouette with G2-continuous superelliptical corners.
func makeSuperellipsePath(in rect: CGRect, exponent n: CGFloat = 5.0, stepsPerCorner: Int = 64) -> CGPath {
    let r = min(rect.width, rect.height) * 0.225
    let twoOverN = 2.0 / n
    let path = CGMutablePath()

    let corners: [(cx: CGFloat, cy: CGFloat, startAngle: CGFloat, endAngle: CGFloat)] = [
        (rect.maxX - r, rect.maxY - r, 0.0, .pi / 2.0),
        (rect.minX + r, rect.maxY - r, .pi / 2.0, .pi),
        (rect.minX + r, rect.minY + r, .pi, 1.5 * .pi),
        (rect.maxX - r, rect.minY + r, 1.5 * .pi, 2.0 * .pi)
    ]

    var isFirst = true
    for corner in corners {
        for i in 0...stepsPerCorner {
            let t = CGFloat(i) / CGFloat(stepsPerCorner)
            let theta = corner.startAngle + t * (corner.endAngle - corner.startAngle)
            let cosT = cos(theta)
            let sinT = sin(theta)
            let x = corner.cx + r * (cosT >= 0 ? 1 : -1) * pow(abs(cosT), twoOverN)
            let y = corner.cy + r * (sinT >= 0 ? 1 : -1) * pow(abs(sinT), twoOverN)
            if isFirst {
                path.move(to: CGPoint(x: x, y: y))
                isFirst = false
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
    }
    path.closeSubpath()
    return path
}

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

    let pad = s * 0.09765625 // 100 / 1024 standard macOS icon margin
    let cardRect = CGRect(x: pad, y: pad, width: s - pad * 2, height: s - pad * 2)
    let squircle = makeSuperellipsePath(in: cardRect, exponent: 4.6)

    // 1. Soft macOS elevation drop shadow
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -s * 0.020),
        blur: s * 0.040,
        color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.40)
    )
    ctx.setFillColor(CGColor(srgbRed: 0.06, green: 0.08, blue: 0.11, alpha: 1.0))
    ctx.addPath(squircle)
    ctx.fillPath()
    ctx.restoreGState()

    // 2. Clip to continuous superellipse
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()

    // Deep graphite-obsidian Liquid Glass surface
    let bgColors = [
        CGColor(srgbRed: 0.13, green: 0.16, blue: 0.20, alpha: 1.0),
        CGColor(srgbRed: 0.07, green: 0.09, blue: 0.12, alpha: 1.0),
        CGColor(srgbRed: 0.04, green: 0.05, blue: 0.07, alpha: 1.0)
    ] as CFArray
    let bgGrad = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 0.58, 1.0])!
    ctx.drawLinearGradient(
        bgGrad,
        start: CGPoint(x: cardRect.midX, y: cardRect.maxY),
        end: CGPoint(x: cardRect.midX, y: cardRect.minY),
        options: []
    )

    // Subtle top-left cyan glass ambient light
    let ambientColors = [
        CGColor(srgbRed: 0.24, green: 0.78, blue: 0.88, alpha: 0.22),
        CGColor(srgbRed: 0.14, green: 0.45, blue: 0.65, alpha: 0.0)
    ] as CFArray
    let ambientGrad = CGGradient(colorsSpace: colorSpace, colors: ambientColors, locations: [0.0, 1.0])!
    ctx.drawRadialGradient(
        ambientGrad,
        startCenter: CGPoint(x: cardRect.minX + cardRect.width * 0.26, y: cardRect.maxY - cardRect.height * 0.16),
        startRadius: 0,
        endCenter: CGPoint(x: cardRect.minX + cardRect.width * 0.26, y: cardRect.maxY - cardRect.height * 0.16),
        endRadius: cardRect.width * 0.78,
        options: []
    )

    // 3. Four Precision Vertical Telemetry Capsule Bars (Claude / ChatGPT / Antigravity / DeepSeek)
    let barCount = 4
    let barWidth = cardRect.width * 0.118
    let barGap = cardRect.width * 0.052
    let totalBarsWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barGap
    let startX = cardRect.midX - totalBarsWidth / 2.0
    let trackHeight = cardRect.height * 0.54
    let trackMinY = cardRect.midY - trackHeight / 2.0
    let pillRadius = barWidth / 2.0

    struct BarSpec {
        let fillFraction: CGFloat
        let topColor: CGColor
        let bottomColor: CGColor
        let glowColor: CGColor
    }

    let bars: [BarSpec] = [
        BarSpec(
            fillFraction: 0.76,
            topColor: CGColor(srgbRed: 0.99, green: 0.99, blue: 1.00, alpha: 1.0),
            bottomColor: CGColor(srgbRed: 0.82, green: 0.91, blue: 0.97, alpha: 1.0),
            glowColor: CGColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.22)
        ),
        BarSpec(
            fillFraction: 0.93,
            topColor: CGColor(srgbRed: 0.48, green: 0.94, blue: 0.99, alpha: 1.0),
            bottomColor: CGColor(srgbRed: 0.18, green: 0.73, blue: 0.84, alpha: 1.0),
            glowColor: CGColor(srgbRed: 0.36, green: 0.86, blue: 0.95, alpha: 0.34)
        ),
        BarSpec(
            fillFraction: 0.48,
            topColor: CGColor(srgbRed: 1.00, green: 0.88, blue: 0.32, alpha: 1.0),
            bottomColor: CGColor(srgbRed: 0.96, green: 0.66, blue: 0.14, alpha: 1.0),
            glowColor: CGColor(srgbRed: 1.00, green: 0.80, blue: 0.20, alpha: 0.30)
        ),
        BarSpec(
            fillFraction: 0.82,
            topColor: CGColor(srgbRed: 0.46, green: 0.82, blue: 1.00, alpha: 1.0),
            bottomColor: CGColor(srgbRed: 0.22, green: 0.58, blue: 0.96, alpha: 1.0),
            glowColor: CGColor(srgbRed: 0.34, green: 0.76, blue: 1.00, alpha: 0.28)
        )
    ]

    for (idx, spec) in bars.enumerated() {
        let bx = startX + CGFloat(idx) * (barWidth + barGap)
        let trackRect = CGRect(x: bx, y: trackMinY, width: barWidth, height: trackHeight)
        let trackPath = CGPath(roundedRect: trackRect, cornerWidth: pillRadius, cornerHeight: pillRadius, transform: nil)

        // Recessed frosted track
        ctx.saveGState()
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.085))
        ctx.addPath(trackPath)
        ctx.fillPath()
        ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.10))
        ctx.setLineWidth(max(0.8, s * 0.0022))
        ctx.addPath(trackPath)
        ctx.strokePath()
        ctx.restoreGState()

        // Active luminous fill bar
        let fillH = max(barWidth, trackHeight * spec.fillFraction)
        let fillRect = CGRect(x: bx, y: trackMinY, width: barWidth, height: fillH)
        let fillPath = CGPath(roundedRect: fillRect, cornerWidth: pillRadius, cornerHeight: pillRadius, transform: nil)

        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: s * 0.022, color: spec.glowColor)
        ctx.addPath(fillPath)
        ctx.setFillColor(spec.topColor)
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(fillPath)
        ctx.clip()
        let barGrad = CGGradient(
            colorsSpace: colorSpace,
            colors: [spec.topColor, spec.bottomColor] as CFArray,
            locations: [0.0, 1.0]
        )!
        ctx.drawLinearGradient(
            barGrad,
            start: CGPoint(x: fillRect.midX, y: fillRect.maxY),
            end: CGPoint(x: fillRect.midX, y: fillRect.minY),
            options: []
        )
        ctx.restoreGState()
    }

    // 4. Top-lit Liquid Glass specular border
    let insetBorder = cardRect.insetBy(dx: max(0.75, s * 0.0025), dy: max(0.75, s * 0.0025))
    let borderSquircle = makeSuperellipsePath(in: insetBorder, exponent: 4.6)
    ctx.saveGState()
    ctx.addPath(borderSquircle)
    ctx.setLineWidth(max(1.2, s * 0.005))
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    let rimColors = [
        CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.36),
        CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.12),
        CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.05)
    ] as CFArray
    let rimGrad = CGGradient(colorsSpace: colorSpace, colors: rimColors, locations: [0.0, 0.5, 1.0])!
    ctx.drawLinearGradient(
        rimGrad,
        start: CGPoint(x: cardRect.midX, y: cardRect.maxY),
        end: CGPoint(x: cardRect.midX, y: cardRect.minY),
        options: []
    )
    ctx.restoreGState()

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
