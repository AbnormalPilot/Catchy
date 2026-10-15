// Draws Catchy's logo: a "C" arc catching a dot.
// Regenerate with: swift Tools/make-icons.swift
import AppKit

let assets = URL(fileURLWithPath: "Catchy/Resources/Assets.xcassets")

/// The mark, drawn in a unit square (0...1, origin bottom-left).
func drawMark(in ctx: CGContext, size: CGFloat, arc: CGColor, dot: CGColor, weight: CGFloat) {
    let center = CGPoint(x: size * 0.47, y: size * 0.5)
    let radius = size * 0.29
    ctx.setLineCap(.round)
    ctx.setLineWidth(size * weight)
    ctx.setStrokeColor(arc)
    // Open on the right, like a hand about to close.
    ctx.addArc(center: center, radius: radius, startAngle: .pi * 0.27, endAngle: -.pi * 0.27, clockwise: false)
    ctx.strokePath()
    ctx.setFillColor(dot)
    let r = size * 0.085
    ctx.fillEllipse(in: CGRect(x: center.x + radius * 0.62 - r, y: center.y - r, width: r * 2, height: r * 2))
}

func png(_ pixels: Int, draw: (CGContext, CGFloat) -> Void) -> Data {
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    draw(ctx, CGFloat(pixels))
    return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
}

func appIcon(_ ctx: CGContext, _ size: CGFloat) {
    // macOS icon grid: the body is 824/1024 of the canvas.
    let inset = size * 100 / 1024
    let body = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let path = CGPath(roundedRect: body, cornerWidth: body.width * 0.225, cornerHeight: body.width * 0.225, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.01), blur: size * 0.03, color: CGColor(gray: 0, alpha: 0.35))
    ctx.addPath(path); ctx.setFillColor(CGColor(gray: 0.1, alpha: 1)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [
        CGColor(srgbRed: 0.17, green: 0.17, blue: 0.22, alpha: 1),
        CGColor(srgbRed: 0.07, green: 0.07, blue: 0.10, alpha: 1),
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])
    ctx.translateBy(x: body.minX, y: body.minY)
    drawMark(in: ctx, size: body.width,
             arc: CGColor(gray: 1, alpha: 1),
             dot: CGColor(srgbRed: 1.0, green: 0.36, blue: 0.30, alpha: 1),
             weight: 0.115)
    ctx.restoreGState()
}

func write(_ data: Data, _ path: String) { try! data.write(to: assets.appendingPathComponent(path)) }

// App icon
var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        write(png(points * scale, draw: appIcon), "AppIcon.appiconset/\(name)")
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}
let iconJSON: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
write(try! JSONSerialization.data(withJSONObject: iconJSON, options: [.prettyPrinted, .sortedKeys]), "AppIcon.appiconset/Contents.json")

// Menu bar template icon (18pt), black on clear so macOS tints it.
try? FileManager.default.createDirectory(at: assets.appendingPathComponent("MenuBarIcon.imageset"), withIntermediateDirectories: true)
for scale in [1, 2] {
    write(png(18 * scale) { ctx, size in
        drawMark(in: ctx, size: size, arc: CGColor(gray: 0, alpha: 1), dot: CGColor(gray: 0, alpha: 1), weight: 0.14)
    }, "MenuBarIcon.imageset/menubar\(scale == 2 ? "@2x" : "").png")
}
let barJSON: [String: Any] = [
    "images": [["idiom": "universal", "scale": "1x", "filename": "menubar.png"],
               ["idiom": "universal", "scale": "2x", "filename": "menubar@2x.png"]],
    "info": ["author": "xcode", "version": 1],
    "properties": ["template-rendering-intent": "template"],
]
write(try! JSONSerialization.data(withJSONObject: barJSON, options: [.prettyPrinted, .sortedKeys]), "MenuBarIcon.imageset/Contents.json")
print("Icons written")
