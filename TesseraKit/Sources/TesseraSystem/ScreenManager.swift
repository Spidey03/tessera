import AppKit
import CoreGraphics
import Foundation
import TesseraKit

/// Immutable snapshot of one display in both coordinate spaces.
public struct DisplayInfo: Sendable {
    public let id: CGDirectDisplayID
    public let name: String
    /// Full display frame in bottom-left (NSScreen) coordinates.
    public let frame: CGRect
    /// Visible frame (excludes menu bar / dock) in bottom-left coordinates.
    public let visibleFrame: CGRect
    /// Full display frame in top-left AX coordinates (for wallpaper detection).
    public let fullRect: Rect
    /// Visible frame in top-left AX coordinates (the BSP monitor rect).
    public let rect: Rect

    public init(id: CGDirectDisplayID, name: String, frame: CGRect, visibleFrame: CGRect, fullRect: Rect, rect: Rect) {
        self.id = id
        self.name = name
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.fullRect = fullRect
        self.rect = rect
    }
}

/// Central provider of display geometry and window-to-display assignment.
/// All window positions from AX are global top-left coordinates, so every
/// lookup here works in top-left space.
public enum ScreenManager {
    /// Live displays derived from `NSScreen.screens`.
    public static var displays: [DisplayInfo] {
        let mainTop = mainDisplayTop()
        return NSScreen.screens.compactMap { screen in
            let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            let fullRect = rect(from: screen.frame, visible: screen.frame, mainDisplayTop: mainTop)
            let rect = rect(from: screen.frame, visible: screen.visibleFrame, mainDisplayTop: mainTop)
            return DisplayInfo(
                id: id,
                name: screen.localizedName,
                frame: screen.frame,
                visibleFrame: screen.visibleFrame,
                fullRect: fullRect,
                rect: rect
            )
        }
    }

    /// ID of the main display (menu bar display), falling back to the first display.
    public static var mainDisplayID: CGDirectDisplayID? {
        if let main = NSScreen.main {
            return (main.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        }
        return displays.first?.id
    }

    /// Top edge (bottom-left y) of the main display. AX positions are global
    /// top-left coordinates anchored to the main display's top-left corner,
    /// so every display's rect must be converted against this edge.
    private static func mainDisplayTop() -> Double {
        if let main = NSScreen.main {
            return main.frame.origin.y + main.frame.height
        }
        return (NSScreen.screens.first?.frame.maxY).map { Double($0) } ?? 0
    }

    /// Convert an NSScreen frame + visible-frame pair (bottom-left origin)
    /// into a Rect in top-left AX coordinates, anchored to the main display's top edge.
    public static func rect(from frame: CGRect, visible: CGRect, mainDisplayTop: Double) -> Rect {
        let topInset = mainDisplayTop - (visible.origin.y + visible.height)
        return Rect(
            x: Double(visible.origin.x),
            y: Double(topInset),
            width: Double(visible.size.width),
            height: Double(visible.size.height)
        )
    }

    public static func display(byID id: CGDirectDisplayID) -> DisplayInfo? {
        displays.first { $0.id == id }
    }

    public static func display(containing point: CGPoint) -> DisplayInfo? {
        display(containing: point, in: displays)
    }

    public static func display(containing rect: CGRect) -> DisplayInfo? {
        display(containing: rect, in: displays)
    }

    /// Find the display whose visible rect contains the given point (top-left AX space).
    public static func display(containing point: CGPoint, in displays: [DisplayInfo]) -> DisplayInfo? {
        displays.first { d in
            let r = d.rect
            return point.x >= r.x && point.x < r.x + r.width
                && point.y >= r.y && point.y < r.y + r.height
        }
    }

    /// Find the display containing the center of the given rect (top-left AX space).
    public static func display(containing rect: CGRect, in displays: [DisplayInfo]) -> DisplayInfo? {
        display(containing: CGPoint(x: rect.midX, y: rect.midY), in: displays)
    }

    /// Desktop wallpaper detection: an empty-title window that exactly matches a
    /// display's frame, or fully covers it (desktop windows can span several displays).
    public static func isDesktopWallpaper(title: String, position: CGPoint, size: CGSize, in displays: [DisplayInfo]) -> Bool {
        guard title.isEmpty else { return false }
        let winRect = CGRect(x: position.x, y: position.y, width: size.width, height: size.height)
        return displays.contains { d in
            let frameRect = CGRect(x: d.fullRect.x, y: d.fullRect.y,
                                   width: d.fullRect.width, height: d.fullRect.height)
            return winRect == frameRect || winRect.contains(frameRect)
        }
    }
}
