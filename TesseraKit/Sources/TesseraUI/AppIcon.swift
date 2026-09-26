import AppKit

/// Proportions of the Tessera tile-grid glyph, expressed as fractions of the
/// canvas so the menu bar and Settings renderings are the same shape at two
/// sizes instead of two hand-tuned copies.
///
/// Apple menu bar glyphs are optically sized, not geometrically sized: the ink
/// is ~13 pt inside the 18 pt canvas so it lines up with the SF Symbols beside
/// it, and the gaps have to stay wide enough (≥1.75 pt) to survive 1× rendering
/// instead of closing into one solid square.
public struct TesseraGlyphMetrics: Sendable {
    /// Side of the 2×2 tile block as a fraction of the canvas.
    public var inkFraction: CGFloat
    /// Gap between tiles as a fraction of the canvas.
    public var gapFraction: CGFloat
    /// Tile corner radius as a fraction of the tile side.
    public var radiusFraction: CGFloat
    /// Optical vertical bias as a fraction of the canvas; positive sits higher.
    public var baselineBiasFraction: CGFloat

    public init(inkFraction: CGFloat, gapFraction: CGFloat,
                radiusFraction: CGFloat, baselineBiasFraction: CGFloat) {
        self.inkFraction = inkFraction
        self.gapFraction = gapFraction
        self.radiusFraction = radiusFraction
        self.baselineBiasFraction = baselineBiasFraction
    }

    /// Tuned menu bar metrics: 13 pt ink, 2 pt gaps in an 18 pt canvas. That
    /// lands between the neighbouring SF Symbols (11.5 pt of ink, 3.5 pt gaps
    /// either side) and the previous 12 pt drawing, without the filled tiles
    /// reading as heavy as they do at 15 pt.
    public static let menuBar = TesseraGlyphMetrics(
        inkFraction: 13.0 / 18.0,
        gapFraction: 2.0 / 18.0,
        radiusFraction: 0.30,
        baselineBiasFraction: 0
    )

    /// The previous hand-tuned drawing (12 pt ink, 1 pt gaps), kept so the
    /// before/after can be compared directly.
    public static let legacy = TesseraGlyphMetrics(
        inkFraction: 12.0 / 18.0,
        gapFraction: 1.0 / 18.0,
        radiusFraction: 0.25,
        baselineBiasFraction: 0
    )
}

/// Measured optical properties of a rendered glyph.
public struct TesseraGlyphInk: Sendable {
    /// Ink bounding box in points, relative to the top-left of the canvas.
    public let box: CGRect
    /// Fraction of the canvas covered by ink, 0...1.
    public let coverage: Double

    public init(box: CGRect, coverage: Double) {
        self.box = box
        self.coverage = coverage
    }
}

/// Draws the Tessera glyph: a 2×2 grid of rounded tiles (all toggled = on).
///
/// The menu bar version is a template image, so the menu bar's foreground
/// colour — including a wallpaper-following menu bar, the inactive and
/// highlighted states — is applied by the system, exactly as it does for the
/// other icons in the bar. Only the alpha channel is used, so the fill colour
/// is irrelevant there.
public enum TesseraMenuIcon {
    /// Draws the tile grid into `rect` using `color`, in the current context.
    public static func drawTiles(in rect: NSRect, metrics: TesseraGlyphMetrics, color: NSColor) {
        let side = min(rect.width, rect.height)
        let ink = side * metrics.inkFraction
        let gap = side * metrics.gapFraction
        let tile = (ink - gap) / 2
        let radius = tile * metrics.radiusFraction
        let originX = rect.minX + (rect.width - ink) / 2
        let originY = rect.minY + (rect.height - ink) / 2 + side * metrics.baselineBiasFraction

        color.setFill()
        for row in 0..<2 {
            for col in 0..<2 {
                let tileRect = NSRect(
                    x: originX + CGFloat(col) * (tile + gap),
                    y: originY + CGFloat(row) * (tile + gap),
                    width: tile,
                    height: tile
                )
                NSBezierPath(roundedRect: tileRect, xRadius: radius, yRadius: radius).fill()
            }
        }
    }

    /// Menu bar canvas. The status item's clickable width is separate: the air
    /// around the glyph is `(statusItemLength - ink) / 2` on each side, so
    /// shrinking the canvas on its own just moves padding from inside the image
    /// to outside it and changes nothing on screen.
    public static let statusItemCanvas: CGFloat = 18

    /// Clickable width of the status item, in points. `NSSquareStatusItemLength`
    /// (22 pt) left 4.5 pt of dead space either side of 13 pt of ink; 18 pt
    /// brings that down to 2.5 pt while keeping a full-size hit target. It must
    /// stay >= `statusItemCanvas`, or AppKit scales the image down to fit.
    public static let statusItemLength: CGFloat = 18

    /// Menu bar status glyph: 18 pt canvas, 1× and 2× reps, template.
    public static func statusImage(metrics: TesseraGlyphMetrics = .menuBar,
                            pointSize: CGFloat = statusItemCanvas) -> NSImage {
        image(pointSize: pointSize, isTemplate: true) { rect in
            drawTiles(in: rect, metrics: metrics, color: .black)
        }
    }

    /// Larger, accent-tinted tile grid used at the top of the Settings window.
    public static func settingsHeaderImage(pointSize: CGFloat = 40) -> NSImage {
        image(pointSize: pointSize, isTemplate: false) { rect in
            drawTiles(in: rect, metrics: .menuBar,
                      color: .controlAccentColor.withAlphaComponent(0.9))
        }
    }

    /// Rasterises the glyph and measures its ink, so the optical metrics can be
    /// asserted in tests and eyeballed by the preview harness instead of being
    /// eyeballed once and never checked again.
    public static func inkMetrics(pointSize: CGFloat = 18,
                           scale: Int = 2,
                           metrics: TesseraGlyphMetrics = .menuBar,
                           color: NSColor = .black) -> TesseraGlyphInk? {
        let pixels = Int(pointSize * CGFloat(scale))
        var bytes = [UInt8](repeating: 0, count: pixels * pixels * 4)
        guard let context = CGContext(data: &bytes, width: pixels, height: pixels,
                                      bitsPerComponent: 8, bytesPerRow: pixels * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        drawTiles(in: NSRect(x: 0, y: 0, width: pointSize, height: pointSize),
                  metrics: metrics, color: color)
        NSGraphicsContext.restoreGraphicsState()

        var minX = pixels, maxX = -1, minY = pixels, maxY = -1, lit = 0
        for y in 0..<pixels {
            for x in 0..<pixels where bytes[(y * pixels + x) * 4 + 3] > 128 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
                lit += 1
            }
        }
        guard maxX >= 0 else { return nil }
        let unit = CGFloat(scale)
        // CGContext rows run bottom-up; report in AppKit's top-left coordinates.
        return TesseraGlyphInk(
            box: CGRect(x: CGFloat(minX) / unit,
                        y: CGFloat(pixels - maxY - 1) / unit,
                        width: CGFloat(maxX - minX + 1) / unit,
                        height: CGFloat(maxY - minY + 1) / unit),
            coverage: Double(lit) / Double(pixels * pixels)
        )
    }

    private static func image(pointSize: CGFloat, isTemplate: Bool,
                              draw: (NSRect) -> Void) -> NSImage {
        let image = NSImage(size: NSSize(width: pointSize, height: pointSize))
        for scale in [1, 2] {
            let pixels = Int(pointSize * CGFloat(scale))
            guard let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: pixels,
                pixelsHigh: pixels,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ) else { continue }
            rep.size = NSSize(width: pointSize, height: pointSize)
            NSGraphicsContext.saveGraphicsState()
            // A bitmap rep's context already maps points to pixels via
            // `rep.size`; scaling it again double-scales and clips the glyph.
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            draw(NSRect(x: 0, y: 0, width: pointSize, height: pointSize))
            NSGraphicsContext.restoreGraphicsState()
            image.addRepresentation(rep)
        }
        image.isTemplate = isTemplate
        return image
    }
}
