// Renders the GyroWheel app icon (1024x1024 PNG) using CoreGraphics + the
// `steeringwheel` SF Symbol. Run:  swift tools/gen_icon.swift <output.png>
// Not part of the app target — lives outside ios/ so it isn't compiled in.

import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let outPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "ios/Assets.xcassets/AppIcon.appiconset/icon-1024.png"

let dim = 1024
let space = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: dim, height: dim,
                          bitsPerComponent: 8, bytesPerRow: 0, space: space,
                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
    fatalError("Could not create CGContext")
}
let S = CGFloat(dim)
let full = CGRect(x: 0, y: 0, width: S, height: S)

// Background: diagonal dark gradient (icons must be opaque, full-bleed).
let bg = CGGradient(colorsSpace: space,
                    colors: [CGColor(red: 0.11, green: 0.12, blue: 0.17, alpha: 1),
                             CGColor(red: 0.02, green: 0.02, blue: 0.05, alpha: 1)] as CFArray,
                    locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: S), end: CGPoint(x: S, y: 0), options: [])

// Thin green accent ring (matches the app's "Connected" color).
ctx.setStrokeColor(CGColor(red: 0.20, green: 0.78, blue: 0.35, alpha: 0.9))
ctx.setLineWidth(S * 0.022)
let inset = S * 0.13
ctx.strokeEllipse(in: full.insetBy(dx: inset, dy: inset))

// White steering-wheel symbol, centered.
let conf = NSImage.SymbolConfiguration(pointSize: S * 0.46, weight: .regular)
    .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
guard let base = NSImage(systemSymbolName: "steeringwheel", accessibilityDescription: nil),
      let sym = base.withSymbolConfiguration(conf) else {
    fatalError("Could not load steeringwheel symbol")
}
var proposed = NSRect(x: 0, y: 0, width: S * 0.5, height: S * 0.5)
guard let glyph = sym.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else {
    fatalError("Could not rasterize symbol")
}
let maxDim = S * 0.52
let aspect = CGFloat(glyph.width) / CGFloat(glyph.height)
var gw = maxDim, gh = maxDim
if aspect >= 1 { gh = maxDim / aspect } else { gw = maxDim * aspect }
let gr = CGRect(x: (S - gw) / 2, y: (S - gh) / 2, width: gw, height: gh)
ctx.draw(glyph, in: gr)

// Write PNG.
guard let image = ctx.makeImage() else { fatalError("makeImage failed") }
let url = URL(fileURLWithPath: outPath)
guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("Could not create image destination at \(outPath)")
}
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("Could not write PNG") }
print("Wrote \(dim)x\(dim) icon -> \(outPath)")
