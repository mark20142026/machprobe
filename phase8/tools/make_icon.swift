// Builds the iOS app icon from the user's own installed game: takes the largest
// image in the game's AppIcon.icns, trims macOS's transparent padding (the
// squircle bounding box), fills the corners and writes the iOS sizes.
// The icon is read at build time from the user's copy; it is never stored in
// the repository. Usage: make_icon.swift <AppIcon.icns> <output-dir>
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count == 3, let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, nil) else {
    FileHandle.standardError.write("usage: make_icon.swift <AppIcon.icns> <output-dir>\n".data(using: .utf8)!); exit(2)
}
var best: CGImage?
for i in 0..<CGImageSourceGetCount(src) {
    if let im = CGImageSourceCreateImageAtIndex(src, i, nil), im.width > (best?.width ?? 0) { best = im }
}
guard let icon = best else { exit(1) }

// Opaque bounding box (alpha > 200) = the macOS squircle without padding.
let w = icon.width, h = icon.height
var rgba = [UInt8](repeating: 0, count: w * h * 4)
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let probe = CGContext(data: &rgba, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
probe.draw(icon, in: CGRect(x: 0, y: 0, width: w, height: h))
var minX = w, minY = h, maxX = 0, maxY = 0
for y in 0..<h { for x in 0..<w where rgba[(y * w + x) * 4 + 3] > 200 {
    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
} }
let side = max(maxX - minX, maxY - minY) + 1
// Rows in the bitmap run top-down; CGImage cropping uses the same origin.
let crop = icon.cropping(to: CGRect(x: minX, y: minY, width: side, height: side)) ?? icon
// Corner fill: the colour just inside the squircle's left edge, mid-height.
let mid = ((minY + side / 2) * w + minX + side / 20) * 4
let fill = CGColor(srgbRed: CGFloat(rgba[mid]) / 255, green: CGFloat(rgba[mid + 1]) / 255, blue: CGFloat(rgba[mid + 2]) / 255, alpha: 1)

let out = URL(fileURLWithPath: args[2])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for (name, px) in [("AppIcon60x60@2x", 120), ("AppIcon60x60@3x", 180), ("AppIcon76x76@2x", 152), ("AppIcon83.5x83.5@2x", 167)] {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!   // iOS icons must be opaque
    ctx.setFillColor(fill); ctx.fill(CGRect(x: 0, y: 0, width: px, height: px))
    ctx.interpolationQuality = .high
    ctx.draw(crop, in: CGRect(x: 0, y: 0, width: px, height: px))
    let dest = CGImageDestinationCreateWithURL(out.appendingPathComponent(name + ".png") as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil); CGImageDestinationFinalize(dest)
}
print("icon \(w)x\(h) -> squircle \(side)px, iOS sizes written to \(out.path)")
