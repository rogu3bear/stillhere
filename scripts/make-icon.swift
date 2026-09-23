// Draws the 1024 px master app icon with CoreGraphics (shapes only, no fonts),
// so the output is the same on every run.
// Usage: swift scripts/make-icon.swift <output.png>
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let canvas = CGFloat(size)

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <output.png>\n".utf8))
    exit(2)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1])

guard
    let space = CGColorSpace(name: CGColorSpace.sRGB),
    let ctx = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
else {
    FileHandle.standardError.write(Data("could not create bitmap context\n".utf8))
    exit(1)
}

// Background: the macOS icon grid's rounded square (824 px inside 1024 px).
let inset: CGFloat = 100
let tile = CGRect(x: inset, y: inset, width: canvas - 2 * inset, height: canvas - 2 * inset)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0, 0, 0, 0.35))
ctx.addPath(tilePath)
ctx.setFillColor(rgb(20, 24, 38))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(tilePath)
ctx.clip()
let background = CGGradient(
    colorsSpace: space,
    colors: [rgb(38, 46, 74), rgb(16, 20, 34)] as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(
    background, start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.minY), options: []
)
ctx.restoreGState()

// Terminal window title bar with three dots.
let barY = tile.maxY - 150
ctx.setFillColor(rgb(255, 255, 255, 0.08))
ctx.fill(CGRect(x: tile.minX, y: barY, width: tile.width, height: 6))
let dotColors = [rgb(255, 95, 87), rgb(254, 188, 46), rgb(40, 200, 64)]
for (index, color) in dotColors.enumerated() {
    let center = CGPoint(x: tile.minX + 110 + CGFloat(index) * 72, y: tile.maxY - 78)
    ctx.setFillColor(color)
    ctx.fillEllipse(in: CGRect(x: center.x - 24, y: center.y - 24, width: 48, height: 48))
}

// Prompt: a chevron and a cursor bar.
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.setLineWidth(64)
ctx.setStrokeColor(rgb(94, 234, 212))
ctx.move(to: CGPoint(x: 260, y: 600))
ctx.addLine(to: CGPoint(x: 400, y: 490))
ctx.addLine(to: CGPoint(x: 260, y: 380))
ctx.strokePath()
ctx.setFillColor(rgb(226, 232, 240))
ctx.addPath(CGPath(
    roundedRect: CGRect(x: 460, y: 350, width: 210, height: 60),
    cornerWidth: 30, cornerHeight: 30, transform: nil
))
ctx.fillPath()

// Listening indicator: a green "live" dot with two signal arcs.
let live = CGPoint(x: 770, y: 230)
ctx.setFillColor(rgb(40, 200, 64))
ctx.fillEllipse(in: CGRect(x: live.x - 30, y: live.y - 30, width: 60, height: 60))
ctx.setStrokeColor(rgb(40, 200, 64, 0.8))
ctx.setLineWidth(22)
for radius in [70.0, 115.0] {
    ctx.addArc(
        center: live, radius: radius,
        startAngle: .pi * 0.15, endAngle: .pi * 0.85, clockwise: false
    )
    ctx.strokePath()
}

guard
    let image = ctx.makeImage(),
    let destination = CGImageDestinationCreateWithURL(
        output as CFURL, UTType.png.identifier as CFString, 1, nil
    )
else {
    FileHandle.standardError.write(Data("could not create PNG destination\n".utf8))
    exit(1)
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else {
    FileHandle.standardError.write(Data("could not write \(output.path)\n".utf8))
    exit(1)
}
