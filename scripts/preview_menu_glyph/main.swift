import AppKit

// Renders the Tessera menu bar glyph candidates next to the SF Symbols they
// need to sit beside, on both a light and a dark menu bar, and prints the
// measured ink metrics for each. Compiled together with AppIcon.swift so the
// drawing code under test is exactly what ships:
//
//   swiftc -O TesseraKit/Sources/TesseraMenu/AppIcon.swift \
//     scripts/preview_menu_glyph/main.swift -o /tmp/preview_menu_glyph

let canvas: CGFloat = 18
let scale = 2

struct Candidate {
    let name: String
    let metrics: TesseraGlyphMetrics
    let symbol: (name: String, pointSize: CGFloat)?
}

let candidates: [Candidate] = [
    Candidate(name: "current", metrics: .legacy, symbol: nil),
    Candidate(name: "E 13/2.00", metrics: .init(inkFraction: 13.0 / 18.0, gapFraction: 2.00 / 18.0,
                                                radiusFraction: 0.30, baselineBiasFraction: 0),
              symbol: nil),
    Candidate(name: "A 15/2.00", metrics: .init(inkFraction: 15.0 / 18.0, gapFraction: 2.00 / 18.0,
                                                radiusFraction: 0.28, baselineBiasFraction: 0),
              symbol: nil),
    Candidate(name: "B 15/2.25", metrics: .init(inkFraction: 15.0 / 18.0, gapFraction: 2.25 / 18.0,
                                                radiusFraction: 0.30, baselineBiasFraction: 0),
              symbol: nil),
    Candidate(name: "SF split 13", metrics: .legacy, symbol: ("square.split.2x2", 13)),
    Candidate(name: "SF split 15", metrics: .legacy, symbol: ("square.split.2x2", 15)),
    Candidate(name: "SF grid 15", metrics: .legacy, symbol: ("square.grid.2x2", 15)),
]

/// Renders one variant into an 18 pt canvas at 2× and measures its ink:
/// (ink height in pt, coverage as % of canvas, distance from the canvas top
/// to the top of the ink, distance from the canvas bottom to the ink bottom).
func measure(_ candidate: Candidate, color: NSColor)
    -> (ink: Double, coverage: Double, top: Double, bottom: Double) {
    let pixels = Int(canvas * CGFloat(scale))
    var bytes = [UInt8](repeating: 0, count: pixels * pixels * 4)
    guard let ctx = CGContext(data: &bytes, width: pixels, height: pixels,
                              bitsPerComponent: 8, bytesPerRow: pixels * 4,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return (0, 0, 0, 0) }
    ctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale))

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    let rect = NSRect(x: 0, y: 0, width: canvas, height: canvas)
    if let symbol = candidate.symbol {
        if let image = NSImage(systemSymbolName: symbol.name, accessibilityDescription: nil),
           let configured = image
            .withSymbolConfiguration(.init(pointSize: symbol.pointSize, weight: .regular))?
            .withSymbolConfiguration(.init(paletteColors: [color])) {
            let size = configured.size
            configured.draw(in: NSRect(x: (canvas - size.width) / 2, y: (canvas - size.height) / 2,
                                       width: size.width, height: size.height))
        }
    } else {
        TesseraMenuIcon.drawTiles(in: rect, metrics: candidate.metrics, color: color)
    }
    NSGraphicsContext.restoreGraphicsState()

    // CGContext rows run bottom-up, so y = 0 is the bottom of the canvas.
    var minY = pixels, maxY = -1, lit = 0
    for y in 0..<pixels {
        for x in 0..<pixels {
            if bytes[(y * pixels + x) * 4 + 3] > 128 {
                minY = min(minY, y)
                maxY = max(maxY, y)
                lit += 1
            }
        }
    }
    guard maxY >= 0 else { return (0, 0, 0, 0) }
    let unit = Double(scale)
    return (Double(maxY - minY + 1) / unit,
            100.0 * Double(lit) / Double(pixels * pixels),
            Double(pixels - maxY) / unit,
            Double(minY) / unit)
}

let light = NSColor(calibratedWhite: 0.96, alpha: 1)
let dark = NSColor(calibratedWhite: 0.12, alpha: 1)

print("variant              ink(pt)  cover%   topGap  bottomGap")
for candidate in candidates {
    let m = measure(candidate, color: .black)
    print(String(format: "%-18@ %6.2f  %5.1f   %5.2f   %5.2f",
                 candidate.name as NSString, m.ink, m.coverage, m.top, m.bottom))
}

// ---- comparison strips -----------------------------------------------------

let cellW: CGFloat = 60
let cellH: CGFloat = 44
let gapBetweenRows: CGFloat = 10
let rows = 2
let totalW = cellW * CGFloat(candidates.count)
let totalH = cellH * CGFloat(rows) + gapBetweenRows
let pixelsW = Int(totalW * CGFloat(scale))
let pixelsH = Int(totalH * CGFloat(scale))

guard let sheet = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixelsW, pixelsHigh: pixelsH,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
NSGraphicsContext.saveGraphicsState()
let sheetContext = NSGraphicsContext(bitmapImageRep: sheet)
NSGraphicsContext.current = sheetContext
sheetContext?.cgContext.scaleBy(x: CGFloat(scale), y: CGFloat(scale))

// AppKit origin is bottom-left: draw the dark strip first (bottom), light on top.
let strips: [(background: NSColor, ink: NSColor)] = [(dark, .white), (light, .black)]
for (index, strip) in strips.enumerated() {
    let y = CGFloat(index) * (cellH + gapBetweenRows)
    strip.background.setFill()
    NSRect(x: 0, y: y, width: totalW, height: cellH).fill()

    for (column, candidate) in candidates.enumerated() {
        let x = CGFloat(column) * cellW
        let glyphRect = NSRect(x: x + (cellW - canvas) / 2, y: y + 14, width: canvas, height: canvas)
        if let symbol = candidate.symbol,
           let image = NSImage(systemSymbolName: symbol.name, accessibilityDescription: nil),
           let configured = image
            .withSymbolConfiguration(.init(pointSize: symbol.pointSize, weight: .regular))?
            .withSymbolConfiguration(.init(paletteColors: [strip.ink])) {
            let size = configured.size
            configured.draw(in: NSRect(x: glyphRect.midX - size.width / 2,
                                       y: glyphRect.midY - size.height / 2,
                                       width: size.width, height: size.height))
        } else {
            TesseraMenuIcon.drawTiles(in: glyphRect, metrics: candidate.metrics, color: strip.ink)
        }

        let label = NSAttributedString(string: candidate.name, attributes: [
            .font: NSFont.systemFont(ofSize: 8.5),
            .foregroundColor: index == 0 ? NSColor(calibratedWhite: 0.75, alpha: 1)
                                         : NSColor(calibratedWhite: 0.35, alpha: 1),
        ])
        let size = label.size()
        label.draw(at: NSPoint(x: x + (cellW - size.width) / 2, y: y + 2))
    }
}
NSGraphicsContext.restoreGraphicsState()

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/tessera-menuglyph.png"
if let data = sheet.representation(using: .png, properties: [:]) {
    try? data.write(to: URL(fileURLWithPath: out))
    print("\nwrote \(out) (\(pixelsW)x\(pixelsH))")
}
