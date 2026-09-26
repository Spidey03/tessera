#!/usr/bin/env swift
//
// Generate Tessera's macOS app icon (Big Sur+ squircle style) and produce the
// .icns bundle icon plus an optional PNG preview.
//
// Design: Tessera's signature is its tiling — four rounded tiles in a 2×2 grid
// with uniform gaps. The icon wraps that glyph in a macOS squircle and ships
// two appearances so it sits naturally in both modes:
//
//   light  near-white cool body, vivid blue tiles
//   dark   deep slate body, near-white tiles
//
// Both variants share identical geometry (squircle radius, tile inset, gap
// ratio) so the icon does not appear to jump when the system appearance flips.
//
// Usage:
//   swift scripts/make_icon.swift                    # writes Resources/Tessera.icns
//   swift scripts/make_icon.swift --preview <png>    # also write a light/dark 2-up PNG
//
// Requires macOS (AppKit).
import AppKit

let canvasSide: CGFloat = 1024

enum Appearance: String {
    case light
    case dark

    /// Body (squircle) gradient, top-left → bottom-right.
    var bodyColors: [NSColor] {
        switch self {
        case .light:
            return [
                NSColor(calibratedRed: 0.99, green: 0.99, blue: 1.00, alpha: 1.0),
                NSColor(calibratedRed: 0.90, green: 0.92, blue: 0.96, alpha: 1.0),
                NSColor(calibratedRed: 0.80, green: 0.85, blue: 0.93, alpha: 1.0),
            ]
        case .dark:
            return [
                NSColor(calibratedRed: 0.35, green: 0.38, blue: 0.48, alpha: 1.0),
                NSColor(calibratedRed: 0.20, green: 0.22, blue: 0.30, alpha: 1.0),
                NSColor(calibratedRed: 0.09, green: 0.10, blue: 0.15, alpha: 1.0),
            ]
        }
    }

    /// Tile grid gradient.
    var tileColors: [NSColor] {
        switch self {
        case .light:
            return [
                NSColor(calibratedRed: 0.33, green: 0.58, blue: 0.98, alpha: 1.0),
                NSColor(calibratedRed: 0.13, green: 0.36, blue: 0.86, alpha: 1.0),
            ]
        case .dark:
            return [
                NSColor(calibratedRed: 0.97, green: 0.98, blue: 1.00, alpha: 1.0),
                NSColor(calibratedRed: 0.79, green: 0.85, blue: 0.95, alpha: 1.0),
            ]
        }
    }

    /// Hairline that keeps the squircle edge crisp against the desktop.
    var rimColor: NSColor {
        switch self {
        case .light: return NSColor.black.withAlphaComponent(0.10)
        case .dark: return NSColor.white.withAlphaComponent(0.14)
        }
    }

    /// Specular sheen strength across the upper half.
    var sheenAlpha: CGFloat {
        switch self {
        case .light: return 0.55
        case .dark: return 0.14
        }
    }

    /// Soft drop shadow under the body (helps the light variant float).
    var shadowAlpha: CGFloat {
        switch self {
        case .light: return 0.16
        case .dark: return 0.34
        }
    }
}

func squircle(_ rect: NSRect, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

/// Four rounded tiles in a 2×2 grid with uniform gaps (Tessera's tiling).
func drawTileGrid(in rect: NSRect, gap: CGFloat, cornerRadius: CGFloat, colors: [NSColor]) {
    let side = (rect.width - gap * 3) / 2
    let gradient = NSGradient(colors: colors)!
    for row in 0..<2 {
        for col in 0..<2 {
            let tile = NSRect(x: rect.minX + CGFloat(col) * (side + gap),
                              y: rect.minY + CGFloat(row) * (side + gap),
                              width: side, height: side)
            gradient.draw(in: squircle(tile, cornerRadius), angle: 135)
        }
    }
}

func drawIcon(in canvas: NSRect, appearance: Appearance) {
    let body = canvas.insetBy(dx: canvas.width * 0.024, dy: canvas.height * 0.024)
    let bodyRadius = body.width * 0.2237
    let bodyPath = squircle(body, bodyRadius)

    // Soft shadow beneath the squircle.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowBlurRadius = canvas.width * 0.018
    shadow.shadowOffset = NSSize(width: 0, height: -canvas.width * 0.006)
    shadow.shadowColor = NSColor.black.withAlphaComponent(appearance.shadowAlpha)
    shadow.set()
    NSColor.black.setFill()
    bodyPath.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Body gradient.
    NSGradient(colors: appearance.bodyColors)!.draw(in: bodyPath, angle: 135)

    // Specular sheen across the upper half.
    NSGraphicsContext.saveGraphicsState()
    bodyPath.addClip()
    NSGradient(colors: [
        NSColor.white.withAlphaComponent(appearance.sheenAlpha),
        NSColor.white.withAlphaComponent(0.0),
    ])!.draw(in: NSRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2),
             angle: 90)
    NSGraphicsContext.restoreGraphicsState()

    // The tile grid: ~47% of the icon, like a typical macOS glyph, with gaps
    // echoing the app's outerGap ratio.
    let glyph = canvas.insetBy(dx: canvas.width * 0.266, dy: canvas.height * 0.266)
    drawTileGrid(in: glyph,
                 gap: glyph.width * 0.050,
                 cornerRadius: glyph.width * 0.092,
                 colors: appearance.tileColors)

    // Hairline rim for edge definition.
    let rim = squircle(body.insetBy(dx: 0.5, dy: 0.5), bodyRadius)
    rim.lineWidth = 2
    appearance.rimColor.setStroke()
    rim.stroke()
}

func makeRep(pixels: Int) -> NSBitmapImageRep {
    NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                     isPlanar: false, colorSpaceName: .calibratedRGB,
                     bytesPerRow: 0, bitsPerPixel: 0)!
}

func renderIcon(appearance: Appearance, pixels: Int) -> NSBitmapImageRep {
    let rep = makeRep(pixels: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    drawIcon(in: NSRect(x: 0, y: 0, width: CGFloat(pixels), height: CGFloat(pixels)),
             appearance: appearance)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// MARK: - Main

let args = CommandLine.arguments
let repoRoot = URL(fileURLWithPath: args[0]).deletingLastPathComponent().deletingLastPathComponent()
let resources = repoRoot.appendingPathComponent("Resources")
try? FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)

// MARK: - icns container
//
// `iconutil` has no convention for alternate-appearance artwork: point it at
// `…dark@2x.png` files and it still fills ic11–ic14 (the dark slots) with the
// light artwork, so the icon never follows the system appearance. The .icns
// format is just a header plus (type, length, payload) records, so we emit it
// ourselves and place the dark renders in the dark slots:
//
//   ic04 16    ic05 32     light  (1×, 16 pt @2×)
//   ic07 128   ic08 256    ic09 512    ic10 1024
//   ic11 32    ic12 64     dark   (16 pt @2×, 32 pt @2×)
//   ic13 256   ic14 512    dark   (128 pt @2×, 256 pt @2×)
//
// The dark slot sizes are fixed by the format (Apple's own icons ship only
// ic11 + ic13). There is no dark 1024 slot: getting this wrong leaves macOS
// with no dark 256, so it falls back to the light artwork and the icon stops
// following the system appearance at the sizes Finder and Dock actually use.

struct IcnRecord {
    let type: String
    let png: Data
}

func writeICNS(_ records: [IcnRecord], to url: URL) throws {
    var body = Data()
    for record in records {
        body.append(contentsOf: Array(record.type.utf8))
        var length = UInt32(record.png.count + 8).bigEndian
        withUnsafeBytes(of: &length) { body.append(contentsOf: $0) }
        body.append(record.png)
    }
    var out = Data("icns".utf8)
    var total = UInt32(body.count + 8).bigEndian
    withUnsafeBytes(of: &total) { out.append(contentsOf: $0) }
    out.append(body)
    try out.write(to: url)
}

let lightSlots: [(String, Int)] = [("ic04", 16), ("ic05", 32), ("ic07", 128), ("ic08", 256), ("ic09", 512), ("ic10", 1024)]
let darkSlots: [(String, Int)] = [("ic11", 32), ("ic12", 64), ("ic13", 256), ("ic14", 512)]

var records: [IcnRecord] = []
for (type, px) in lightSlots {
    records.append(IcnRecord(type: type,
                             png: renderIcon(appearance: .light, pixels: px).representation(using: .png, properties: [:])!))
}
for (type, px) in darkSlots {
    records.append(IcnRecord(type: type,
                             png: renderIcon(appearance: .dark, pixels: px).representation(using: .png, properties: [:])!))
}

let icnsURL = resources.appendingPathComponent("Tessera.icns")
try writeICNS(records, to: icnsURL)
print("wrote \(icnsURL.path) (\(records.count) records, light + dark)")

if let idx = args.firstIndex(of: "--preview"), args.count > idx + 1 {
    // Side-by-side light/dark sheet so both appearances can be eyeballed at once.
    let side = 512
    let sheet = makeRep(pixels: side * 2)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: sheet)
    let light = renderIcon(appearance: .light, pixels: side)
    let dark = renderIcon(appearance: .dark, pixels: side)
    light.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
    dark.draw(in: NSRect(x: side, y: 0, width: side, height: side))
    NSGraphicsContext.restoreGraphicsState()
    try sheet.representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: args[idx + 1]))
    print("preview (light | dark): \(args[idx + 1])")
}
