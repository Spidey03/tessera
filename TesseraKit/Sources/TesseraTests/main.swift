import CoreGraphics
import Foundation
import TesseraKit
import TesseraSystem

// MARK: - Local KeyBinding (duplicated from TesseraDaemon for testability)

struct KeyBinding: Sendable {
    let keyCode: CGKeyCode
    let flags: CGEventFlags
    let action: String

    func matches(event: CGEvent) -> Bool {
        let eventKeyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard eventKeyCode == keyCode else { return false }
        return flags.isSubset(of: event.flags)
    }
}

// MARK: - Test utilities

enum TestError: Error, CustomStringConvertible {
    case assertionFailed(String)
    var description: String {
        switch self {
        case .assertionFailed(let msg): "FAIL: \(msg)"
        }
    }
}

func assert(_ condition: Bool, _ message: String = "") throws {
    guard condition else { throw TestError.assertionFailed(message) }
}

func assertEqual<T: Equatable>(_ a: T, _ b: T, file: String = #file, line: Int = #line) throws {
    try assert(a == b, "Expected \(b), got \(a) (\(file):\(line))")
}

func assertNotEqual<T: Equatable>(_ a: T, _ b: T, file: String = #file, line: Int = #line) throws {
    try assert(a != b, "Expected not \(b), got \(a) (\(file):\(line))")
}

func assertNil<T>(_ a: T?, file: String = #file, line: Int = #line) throws {
    try assert(a == nil, "Expected nil, got \(String(describing: a)) (\(file):\(line))")
}

func assertLessThan(_ a: Double, _ b: Double, file: String = #file, line: Int = #line) throws {
    try assert(a < b, "Expected \(a) < \(b) (\(file):\(line))")
}

// MARK: - Tests

func testAddFirstWindowFillsUsableArea() throws {
    let ws = Workspace(monitorRect: Rect(x: 0, y: 0, width: 1920, height: 1080))
    ws.addWindow(Window(id: "A"))
    let layout = ws.getLayout()
    try assertEqual(layout.count, 1)
    try assertEqual(layout[0].0.id, "A")
    try assertEqual(layout[0].1.width, 1904)
    try assertEqual(layout[0].1.height, 1064)
}

func testSecondWindowSplitsVerticallyByDefault() throws {
    let ws = Workspace(monitorRect: Rect(x: 0, y: 0, width: 1920, height: 1080))
    ws.addWindow(Window(id: "A"))
    ws.addWindow(Window(id: "B"))
    let layout = ws.getLayout()
    try assertEqual(layout.count, 2)
    let aRect = layout.first { $0.0.id == "A" }!.1
    let bRect = layout.first { $0.0.id == "B" }!.1
    try assertLessThan(aRect.x, bRect.x)
}

func testThirdWindowSplitsHorizontalOnFocused() throws {
    let ws = Workspace(monitorRect: Rect(x: 0, y: 0, width: 1920, height: 1080))
    ws.addWindow(Window(id: "A"))
    ws.addWindow(Window(id: "B"))
    ws.addWindow(Window(id: "C"))
    let layout = ws.getLayout()
    try assertEqual(layout.count, 3)
    let aRect = layout.first { $0.0.id == "A" }!.1
    let cRect = layout.first { $0.0.id == "C" }!.1
    try assertLessThan(aRect.y, cRect.y)
}

func testFocusStaysOnExistingWindow() throws {
    let ws = Workspace(monitorRect: Rect(x: 0, y: 0, width: 1920, height: 1080),
                       config: TesseraConfig(newWindowFocus: false))
    ws.addWindow(Window(id: "A"))
    ws.addWindow(Window(id: "B"))
    let focused = ws.findFocusedLeaf(ws.root!)
    try assertEqual(focused.window?.id, "A")
}

func testNewWindowCanGetFocus() throws {
    let ws = Workspace(monitorRect: Rect(x: 0, y: 0, width: 1920, height: 1080),
                       config: TesseraConfig(newWindowFocus: true))
    ws.addWindow(Window(id: "A"))
    ws.addWindow(Window(id: "B"))
    let focused = ws.findFocusedLeaf(ws.root!)
    try assertEqual(focused.window?.id, "B")
}

func testRemoveWindowCollapsesTree() throws {
    let ws = Workspace(monitorRect: Rect(x: 0, y: 0, width: 1920, height: 1080))
    ws.addWindow(Window(id: "A"))
    ws.addWindow(Window(id: "B"))
    let removed = ws.removeWindow(id: "B")
    try assertEqual(removed?.id, "B")
    try assertEqual(ws.getLayout().count, 1)
    try assertEqual(ws.getLayout()[0].0.id, "A")
}

func testRemoveFocusedWindowCollapsesAndRefocuses() throws {
    let ws = Workspace(monitorRect: Rect(x: 0, y: 0, width: 1920, height: 1080))
    ws.addWindow(Window(id: "A"))
    ws.addWindow(Window(id: "B"))
    ws.focusWindow(id: "B")
    ws.removeWindow(id: "B")
    let focused = ws.findFocusedLeaf(ws.root!)
    try assertEqual(focused.window?.id, "A")
}

func testFocusWindowByID() throws {
    let ws = Workspace(monitorRect: Rect(x: 0, y: 0, width: 1920, height: 1080))
    ws.addWindow(Window(id: "A"))
    ws.addWindow(Window(id: "B"))
    ws.focusWindow(id: "B")
    let focused = ws.findFocusedLeaf(ws.root!)
    try assertEqual(focused.window?.id, "B")
}

func testFocusNonexistentWindowReturnsFalse() throws {
    let ws = Workspace(monitorRect: Rect(x: 0, y: 0, width: 1920, height: 1080))
    ws.addWindow(Window(id: "A"))
    let result = ws.focusWindow(id: "NONEXISTENT")
    try assertEqual(result, false)
}

func testRemovingLastWindowEmptiesWorkspace() throws {
    let ws = Workspace(monitorRect: Rect(x: 0, y: 0, width: 1920, height: 1080))
    ws.addWindow(Window(id: "A"))
    ws.removeWindow(id: "A")
    try assertNil(ws.root)
    try assert(ws.getLayout().isEmpty)
}

func testRemoveFromEmptyWorkspaceReturnsNil() throws {
    let ws = Workspace(monitorRect: Rect(x: 0, y: 0, width: 1920, height: 1080))
    let result = ws.removeWindow(id: "NONEXISTENT")
    try assertNil(result)
}

func testRemoveMiddleWindowFromThree() throws {
    let ws = Workspace(monitorRect: Rect(x: 0, y: 0, width: 1920, height: 1080))
    ws.addWindow(Window(id: "A"))
    ws.addWindow(Window(id: "B"))
    ws.addWindow(Window(id: "C"))
    ws.removeWindow(id: "B")
    let layout = ws.getLayout()
    try assertEqual(layout.count, 2)
    let ids = layout.map { $0.0.id }.sorted()
    try assertEqual(ids, ["A", "C"])
}

func testDeeplyNestedTreeSevenWindows() throws {
    let ws = Workspace(monitorRect: Rect(x: 0, y: 0, width: 1920, height: 1080))
    for i in 0..<7 {
        ws.addWindow(Window(id: String(UnicodeScalar(65 + i)!)))
    }
    let layout = ws.getLayout()
    try assertEqual(layout.count, 7)
    for (_, r) in layout {
        try assert(r.x >= 0)
        try assert(r.y >= 0)
        try assert(r.x + r.width <= 1920)
        try assert(r.y + r.height <= 1080)
    }
}

func testAddRemoveCyclePreservesCorrectness() throws {
    let ws = Workspace(monitorRect: Rect(x: 0, y: 0, width: 1920, height: 1080))
    ws.addWindow(Window(id: "A"))
    ws.addWindow(Window(id: "B"))
    ws.removeWindow(id: "B")
    ws.addWindow(Window(id: "C"))
    ws.removeWindow(id: "A")
    ws.addWindow(Window(id: "D"))
    let layout = ws.getLayout()
    try assertEqual(layout.count, 2)
    let ids = layout.map { $0.0.id }.sorted()
    try assertEqual(ids, ["C", "D"])
}

func testLargeMonitorRect() throws {
    let config = TesseraConfig(gapSize: 16, outerGap: 32)
    let ws = Workspace(monitorRect: Rect(x: 0, y: 0, width: 7680, height: 4320), config: config)
    ws.addWindow(Window(id: "A"))
    ws.addWindow(Window(id: "B"))
    ws.addWindow(Window(id: "C"))
    try assertEqual(ws.getLayout().count, 3)
}

func testTotalAreaInvariantNoGaps() throws {
    let config = TesseraConfig(gapSize: 0, outerGap: 0)
    let ws = Workspace(monitorRect: Rect(x: 0, y: 0, width: 1920, height: 1080), config: config)
    ws.addWindow(Window(id: "A"))
    ws.addWindow(Window(id: "B"))
    ws.addWindow(Window(id: "C"))
    let totalArea = ws.getLayout().reduce(0.0) { $0 + $1.1.width * $1.1.height }
    try assertEqual(totalArea, 1920.0 * 1080.0)
}

// MARK: - Focus navigation

func testFocusedWindowIDOnEmptyWorkspace() throws {
    let ws = Workspace(monitorRect: Rect(x: 0, y: 0, width: 1920, height: 1080))
    try assertNil(ws.focusedWindowID)
}

func testFocusedWindowIDAfterAdd() throws {
    let ws = Workspace(monitorRect: Rect(x: 0, y: 0, width: 1920, height: 1080))
    ws.addWindow(Window(id: "A"))
    try assertEqual(ws.focusedWindowID, "A")
}

func testFocusedWindowIDAfterFocusRight() throws {
    let ws = Workspace(monitorRect: Rect(x: 0, y: 0, width: 1920, height: 1080))
    ws.addWindow(Window(id: "A"))
    ws.addWindow(Window(id: "B"))
    // Order: A (focused), B
    ws.focusRight()
    try assertEqual(ws.focusedWindowID, "B")
}

func testFocusedWindowIDAfterFocusLeft() throws {
    let ws = Workspace(monitorRect: Rect(x: 0, y: 0, width: 1920, height: 1080))
    ws.addWindow(Window(id: "A"))
    ws.addWindow(Window(id: "B"))
    ws.focusRight()
    ws.focusLeft()
    try assertEqual(ws.focusedWindowID, "A")
}

func testFocusLeftAtEdgeReturnsFalse() throws {
    let ws = Workspace(monitorRect: Rect(x: 0, y: 0, width: 1920, height: 1080))
    ws.addWindow(Window(id: "A"))
    // A is the only window — already at leftmost
    let result = ws.focusLeft()
    try assertEqual(result, false)
    try assertEqual(ws.focusedWindowID, "A")
}

func testFocusRightAtEdgeReturnsFalse() throws {
    let ws = Workspace(monitorRect: Rect(x: 0, y: 0, width: 1920, height: 1080))
    ws.addWindow(Window(id: "A"))
    ws.addWindow(Window(id: "B"))
    ws.focusRight()
    // B is the rightmost
    let result = ws.focusRight()
    try assertEqual(result, false)
    try assertEqual(ws.focusedWindowID, "B")
}

func testFocusRightMovesToRightmostWindow() throws {
    let ws = Workspace(monitorRect: Rect(x: 0, y: 0, width: 1920, height: 1080))
    ws.addWindow(Window(id: "A"))
    ws.addWindow(Window(id: "B"))
    ws.addWindow(Window(id: "C"))
    // Layout: A (top-left, focused), C (bottom-left), B (right)
    // Spatial: A→focusRight→B (B is to the right of A)
    ws.focusRight()
    try assertEqual(ws.focusedWindowID, "B")
    let last = ws.focusRight()
    try assertEqual(last, false)
    try assertEqual(ws.focusedWindowID, "B")
}

func testFocusLeftMovesToLeftmostWindow() throws {
    let ws = Workspace(monitorRect: Rect(x: 0, y: 0, width: 1920, height: 1080))
    ws.addWindow(Window(id: "A"))
    ws.addWindow(Window(id: "B"))
    ws.addWindow(Window(id: "C"))
    // Layout: A (top-left), C (bottom-left), B (right, focused)
    // Spatial: B→focusLeft→A (A and C are equally left, A wins as first-encountered)
    ws.focusRight() // A → B
    try assertEqual(ws.focusedWindowID, "B")
    ws.focusLeft()  // B → A
    try assertEqual(ws.focusedWindowID, "A")
    let last = ws.focusLeft()
    try assertEqual(last, false)
    try assertEqual(ws.focusedWindowID, "A")
}

func testFocusRightAfterRemoveReturnsFalseWhenStacked() throws {
    let ws = Workspace(monitorRect: Rect(x: 0, y: 0, width: 1920, height: 1080))
    ws.addWindow(Window(id: "A"))
    ws.addWindow(Window(id: "B"))
    ws.addWindow(Window(id: "C"))
    // Layout: A (top-left, focused), C (bottom-left), B (right)
    ws.removeWindow(id: "B")
    // Now only A and C remain, stacked vertically (same column)
    try assertEqual(ws.focusedWindowID, "A")
    // No window is to the right of A
    let result = ws.focusRight()
    try assertEqual(result, false)
    try assertEqual(ws.focusedWindowID, "A")
}

func testFocusLeftOnEmptyWorkspaceReturnsFalse() throws {
    let ws = Workspace(monitorRect: Rect(x: 0, y: 0, width: 1920, height: 1080))
    let result = ws.focusLeft()
    try assertEqual(result, false)
}

func testFocusRightOnEmptyWorkspaceReturnsFalse() throws {
    let ws = Workspace(monitorRect: Rect(x: 0, y: 0, width: 1920, height: 1080))
    let result = ws.focusRight()
    try assertEqual(result, false)
}

// MARK: - KeyBinding (pure logic, no AX dependency)

func testKeyBindingTileMatchesCorrectly() throws {
    let event = CGEvent(keyboardEventSource: nil, virtualKey: 36, keyDown: true)!
    event.flags = [.maskCommand, .maskAlternate]
    let binding = KeyBinding(keyCode: 36, flags: [.maskCommand, .maskAlternate], action: "tile")
    try assert(binding.matches(event: event))
}

func testKeyBindingWrongKeyCodeDoesNotMatch() throws {
    let event = CGEvent(keyboardEventSource: nil, virtualKey: 4, keyDown: true)!
    event.flags = [.maskCommand, .maskAlternate]
    let binding = KeyBinding(keyCode: 36, flags: [.maskCommand, .maskAlternate], action: "tile")
    try assert(!binding.matches(event: event))
}

func testKeyBindingMissingFlagsDoesNotMatch() throws {
    let event = CGEvent(keyboardEventSource: nil, virtualKey: 36, keyDown: true)!
    event.flags = [.maskCommand] // missing alternate
    let binding = KeyBinding(keyCode: 36, flags: [.maskCommand, .maskAlternate], action: "tile")
    try assert(!binding.matches(event: event))
}

func testKeyBindingExtraFlagsStillMatches() throws {
    let event = CGEvent(keyboardEventSource: nil, virtualKey: 36, keyDown: true)!
    event.flags = [.maskCommand, .maskAlternate, .maskNonCoalesced, .maskAlphaShift]
    let binding = KeyBinding(keyCode: 36, flags: [.maskCommand, .maskAlternate], action: "tile")
    try assert(binding.matches(event: event))
}

// MARK: - Fullscreen binding

func testKeyBindingFullscreenMatches() throws {
    let event = CGEvent(keyboardEventSource: nil, virtualKey: 3, keyDown: true)!
    event.flags = [.maskCommand, .maskAlternate]
    let binding = KeyBinding(keyCode: 3, flags: [.maskCommand, .maskAlternate], action: "fullscreen")
    try assert(binding.matches(event: event))
}

func testKeyBindingFullscreenWrongKeyCode() throws {
    let event = CGEvent(keyboardEventSource: nil, virtualKey: 36, keyDown: true)!  // Return, not F
    event.flags = [.maskCommand, .maskAlternate]
    let binding = KeyBinding(keyCode: 3, flags: [.maskCommand, .maskAlternate], action: "fullscreen")
    try assert(!binding.matches(event: event))
}

func testKeyBindingFullscreenMissingFlags() throws {
    let event = CGEvent(keyboardEventSource: nil, virtualKey: 3, keyDown: true)!
    event.flags = [.maskCommand]  // missing alternate
    let binding = KeyBinding(keyCode: 3, flags: [.maskCommand, .maskAlternate], action: "fullscreen")
    try assert(!binding.matches(event: event))
}

// MARK: - ScreenManager (pure logic, no live NSScreen dependency)

func makeDisplay(id: UInt32, x: Double, y: Double, w: Double, h: Double, menuBar: Double = 50, mainTop: Double = 1080) -> DisplayInfo {
    let frame = CGRect(x: x, y: y, width: w, height: h)
    let visible = CGRect(x: x, y: y + menuBar, width: w, height: h - menuBar)
    return DisplayInfo(
        id: id,
        name: "Display \(id)",
        frame: frame,
        visibleFrame: visible,
        fullRect: ScreenManager.rect(from: frame, visible: frame, mainDisplayTop: mainTop),
        rect: ScreenManager.rect(from: frame, visible: visible, mainDisplayTop: mainTop)
    )
}

func testScreenManagerRectConversionMainDisplay() throws {
    let rect = ScreenManager.rect(from: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                                  visible: CGRect(x: 0, y: 50, width: 1920, height: 1030),
                                  mainDisplayTop: 1080)
    try assertEqual(rect.x, 0)
    try assertEqual(rect.y, 0)
    try assertEqual(rect.width, 1920)
    try assertEqual(rect.height, 1030)
}

func testScreenManagerRectConversionDisplayAbove() throws {
    // Display stacked above the main one: bottom-left frame origin y = 1080
    let rect = ScreenManager.rect(from: CGRect(x: 0, y: 1080, width: 1920, height: 1080),
                                  visible: CGRect(x: 0, y: 1113, width: 1920, height: 1047),
                                  mainDisplayTop: 1080)
    // y = 1080 - (1113 + 1047) = -1080 → visible top edge in AX space
    try assertEqual(rect.x, 0)
    try assertEqual(rect.y, -1080)
    try assertEqual(rect.width, 1920)
    try assertEqual(rect.height, 1047)
}

func testScreenManagerRectConversionDisplayAboveMisalignedHeights() throws {
    // Regression: main display 1512x982, secondary mounted above at y=982 with a
    // DIFFERENT height (1080). The AX top of the secondary must be anchored to the
    // main display's top edge (982), not its own frame height (old bug: -982).
    let rect = ScreenManager.rect(from: CGRect(x: 0, y: 982, width: 1920, height: 1080),
                                  visible: CGRect(x: 0, y: 982, width: 1920, height: 1080),
                                  mainDisplayTop: 982)
    try assertEqual(rect.x, 0)
    try assertEqual(rect.y, -1080)
    try assertEqual(rect.width, 1920)
    try assertEqual(rect.height, 1080)
}

func testScreenManagerRectConversionDisplayRight() throws {
    // Bottom-aligned secondary: its top edge sits 280pt below the main display's top
    let rect = ScreenManager.rect(from: CGRect(x: 1920, y: 0, width: 1280, height: 800),
                                  visible: CGRect(x: 1920, y: 50, width: 1280, height: 750),
                                  mainDisplayTop: 1080)
    try assertEqual(rect.x, 1920)
    try assertEqual(rect.y, 280)
    try assertEqual(rect.width, 1280)
    try assertEqual(rect.height, 750)
}

func testDisplayContainingPoint() throws {
    let displays = [
        makeDisplay(id: 1, x: 0, y: 0, w: 1920, h: 1080),
        makeDisplay(id: 2, x: 1920, y: 0, w: 1280, h: 800),
    ]
    let onMain = ScreenManager.display(containing: CGPoint(x: 100, y: 100), in: displays)
    try assertEqual(onMain?.id, 1)
    // Secondary's AX visible rect starts at y=280 (bottom-aligned, shorter)
    let onSecondary = ScreenManager.display(containing: CGPoint(x: 2000, y: 500), in: displays)
    try assertEqual(onSecondary?.id, 2)
    // Physically between the two displays (above secondary's top edge, past main's right edge)
    let inGap = ScreenManager.display(containing: CGPoint(x: 2000, y: 100), in: displays)
    try assertNil(inGap)
}

func testDisplayContainingWindowCenter() throws {
    let displays = [
        makeDisplay(id: 1, x: 0, y: 0, w: 1920, h: 1080),
        makeDisplay(id: 2, x: 1920, y: 0, w: 1280, h: 800),
    ]
    // Window straddling both displays — center (1700+200=1900) on main
    let straddle = CGRect(x: 1700, y: 100, width: 400, height: 400)
    let display = ScreenManager.display(containing: straddle, in: displays)
    try assertEqual(display?.id, 1)
    // Window fully on secondary
    let onRight = CGRect(x: 2000, y: 200, width: 400, height: 300)
    try assertEqual(ScreenManager.display(containing: onRight, in: displays)?.id, 2)
}

func testDisplayContainingOffScreenReturnsNil() throws {
    let displays = [makeDisplay(id: 1, x: 0, y: 0, w: 1920, h: 1080)]
    let offScreen = ScreenManager.display(containing: CGPoint(x: 5000, y: 5000), in: displays)
    try assertNil(offScreen)
}

func testDesktopWallpaperDetection() throws {
    let displays = [
        makeDisplay(id: 1, x: 0, y: 0, w: 1920, h: 1080),
        makeDisplay(id: 2, x: 1920, y: 0, w: 1280, h: 800),
    ]
    // Main wallpaper at origin
    try assert(ScreenManager.isDesktopWallpaper(title: "", position: CGPoint(x: 0, y: 0),
                                                size: CGSize(width: 1920, height: 1080), in: displays))
    // Secondary wallpaper at its corrected AX origin (280pt below main's top, bottom-aligned)
    try assert(ScreenManager.isDesktopWallpaper(title: "", position: CGPoint(x: 1920, y: 280),
                                                size: CGSize(width: 1280, height: 800), in: displays))
    // A real window with a title is never a wallpaper
    try assert(!ScreenManager.isDesktopWallpaper(title: "Terminal", position: CGPoint(x: 0, y: 0),
                                                 size: CGSize(width: 1920, height: 1080), in: displays))
    // Wrong size is not a wallpaper
    try assert(!ScreenManager.isDesktopWallpaper(title: "", position: CGPoint(x: 0, y: 0),
                                                 size: CGSize(width: 100, height: 100), in: displays))
}

func testDesktopWallpaperSpansMultipleDisplays() throws {
    // Real-world regression: main 1512x982 (menu bar 33), HP 1920x1080 mounted above.
    // The Finder desktop window reports a frame spanning BOTH displays
    // (1920x2062 at -209,-1080) — it must still be recognized as wallpaper.
    let displays = [
        makeDisplay(id: 1, x: 0, y: 0, w: 1512, h: 982, menuBar: 33, mainTop: 982),
        makeDisplay(id: 3, x: -209, y: 982, w: 1920, h: 1080, menuBar: 0, mainTop: 982),
    ]
    let spanning = ScreenManager.isDesktopWallpaper(title: "", position: CGPoint(x: -209, y: -1080),
                                                    size: CGSize(width: 1920, height: 2062), in: displays)
    try assert(spanning)
    // A genuine window overlapping the boundary is NOT wallpaper
    let realWindow = ScreenManager.isDesktopWallpaper(title: "", position: CGPoint(x: -209, y: -500),
                                                      size: CGSize(width: 955, height: 535), in: displays)
    try assert(!realWindow)
}

// MARK: - Split direction toggle

func testToggleSplitVerticalToHorizontal() throws {
    let ws = Workspace(monitorRect: Rect(x: 0, y: 0, width: 1920, height: 1080))
    ws.addWindow(Window(id: "A"))
    ws.addWindow(Window(id: "B"))
    ws.focusWindow(id: "B")
    try assertEqual(ws.toggleSplitDirection(), true)
    let layout = ws.getLayout()
    let aRect = layout.first { $0.0.id == "A" }!.1
    let bRect = layout.first { $0.0.id == "B" }!.1
    try assertEqual(aRect.x, bRect.x)      // stacked → same left edge
    try assertLessThan(aRect.y, bRect.y)   // A on top, B below
    try assertEqual(aRect.width, 1904)     // full usable width
    try assertEqual(aRect.height, 528)     // half height minus gaps
}

func testToggleSplitRoundTrip() throws {
    let ws = Workspace(monitorRect: Rect(x: 0, y: 0, width: 1920, height: 1080))
    ws.addWindow(Window(id: "A"))
    ws.addWindow(Window(id: "B"))
    ws.focusWindow(id: "B")
    ws.toggleSplitDirection()
    ws.toggleSplitDirection()
    let layout = ws.getLayout()
    let aRect = layout.first { $0.0.id == "A" }!.1
    let bRect = layout.first { $0.0.id == "B" }!.1
    try assertEqual(aRect.y, bRect.y)
    try assertLessThan(aRect.x, bRect.x)
    try assertEqual(aRect, Rect(x: 8, y: 8, width: 948, height: 1064))
    try assertEqual(bRect, Rect(x: 964, y: 8, width: 948, height: 1064))
}

func testToggleSplitSingleWindowReturnsFalse() throws {
    let ws = Workspace(monitorRect: Rect(x: 0, y: 0, width: 1920, height: 1080))
    ws.addWindow(Window(id: "A"))
    try assertEqual(ws.toggleSplitDirection(), false)
    try assertEqual(ws.getLayout().count, 1)
}

func testToggleSplitNestedOnlyAffectsFocusedSplit() throws {
    let ws = Workspace(monitorRect: Rect(x: 0, y: 0, width: 1920, height: 1080))
    ws.addWindow(Window(id: "A"))
    ws.addWindow(Window(id: "B"))
    ws.addWindow(Window(id: "C"))
    ws.focusWindow(id: "C")
    try assertEqual(ws.toggleSplitDirection(), true)
    let layout = ws.getLayout()
    let aRect = layout.first { $0.0.id == "A" }!.1
    let bRect = layout.first { $0.0.id == "B" }!.1
    let cRect = layout.first { $0.0.id == "C" }!.1
    // A and C are now side-by-side inside the left half
    try assertEqual(aRect.y, cRect.y)
    try assertLessThan(aRect.x, cRect.x)
    // B stays untouched in the right half
    try assertEqual(bRect, Rect(x: 964, y: 8, width: 948, height: 1064))
}

func testToggleSplitPreservesGapInset() throws {
    let ws = Workspace(monitorRect: Rect(x: 0, y: 0, width: 1920, height: 1080))
    ws.addWindow(Window(id: "A"))
    ws.addWindow(Window(id: "B"))
    ws.focusWindow(id: "B")
    ws.toggleSplitDirection()
    for (_, rect) in ws.getLayout() {
        // outerGap 4 + gapSize/2 4 → 8px from the monitor edge
        try assertEqual(rect.x, 8)
        try assertEqual(rect.height, 528)
    }
}

// MARK: - Resize split (weights)

func testResizeSplitSingleWindowReturnsFalse() throws {
    let ws = Workspace(monitorRect: Rect(x: 0, y: 0, width: 1920, height: 1080))
    ws.addWindow(Window(id: "A"))
    try assertEqual(ws.resizeSplit(delta: 0.10), false)
    try assertEqual(ws.getLayout().count, 1)
}

func testResizeSplitGrowsFocusedRightChild() throws {
    let ws = Workspace(monitorRect: Rect(x: 0, y: 0, width: 1920, height: 1080))
    ws.addWindow(Window(id: "A"))
    ws.addWindow(Window(id: "B"))
    ws.focusWindow(id: "B")
    // Positive delta grows the FOCUSED side (B, the right child) → A's share 0.6→0.4
    ws.resizeSplit(delta: 0.10)
    let layout = ws.getLayout()
    let aRect = layout.first { $0.0.id == "A" }!.1
    let bRect = layout.first { $0.0.id == "B" }!.1
    try assertEqual(Int(aRect.width.rounded()), 757) // 1912*0.4 - 8
    try assertEqual(Int(bRect.width.rounded()), 1139) // 1912*0.6 - 8
    try assertLessThan(aRect.width, bRect.width)
}

func testResizeSplitShrinksFocusedRightChild() throws {
    let ws = Workspace(monitorRect: Rect(x: 0, y: 0, width: 1920, height: 1080))
    ws.addWindow(Window(id: "A"))
    ws.addWindow(Window(id: "B"))
    ws.focusWindow(id: "B")
    ws.resizeSplit(delta: -0.10)
    let layout = ws.getLayout()
    let aRect = layout.first { $0.0.id == "A" }!.1
    let bRect = layout.first { $0.0.id == "B" }!.1
    try assertEqual(Int(aRect.width.rounded()), 1139) // A took 0.6
    try assertEqual(Int(bRect.width.rounded()), 757)
    try assertLessThan(bRect.width, aRect.width)
}

func testResizeSplitRoundTripRestoresEqualSplit() throws {
    let ws = Workspace(monitorRect: Rect(x: 0, y: 0, width: 1920, height: 1080))
    ws.addWindow(Window(id: "A"))
    ws.addWindow(Window(id: "B"))
    ws.focusWindow(id: "B")
    ws.resizeSplit(delta: 0.10)
    ws.resizeSplit(delta: -0.10)
    let layout = ws.getLayout()
    let aRect = layout.first { $0.0.id == "A" }!.1
    let bRect = layout.first { $0.0.id == "B" }!.1
    try assertEqual(aRect.width, bRect.width)
    try assertEqual(Int(aRect.width.rounded()), 948)
}

func testResizeSplitClampsToMinMax() throws {
    let ws = Workspace(monitorRect: Rect(x: 0, y: 0, width: 1920, height: 1080))
    ws.addWindow(Window(id: "A"))
    ws.addWindow(Window(id: "B"))
    ws.focusWindow(id: "A")
    // Focus is on A (left child). Grow A hard → clamps at splitMaxRatio 0.8.
    for _ in 0..<10 { ws.resizeSplit(delta: 0.10) }
    var layout = ws.getLayout()
    var aRect = layout.first { $0.0.id == "A" }!.1
    try assertEqual(Int(aRect.width.rounded()), 1522) // 1912*0.8 - 8
    // Shrink A hard → clamps at splitMinRatio 0.2.
    for _ in 0..<10 { ws.resizeSplit(delta: -0.10) }
    layout = ws.getLayout()
    aRect = layout.first { $0.0.id == "A" }!.1
    try assertEqual(Int(aRect.width.rounded()), 374) // 1912*0.2 - 8
}

func testResizeSplitRatioSurvivesToggleDirection() throws {
    let ws = Workspace(monitorRect: Rect(x: 0, y: 0, width: 1920, height: 1080))
    ws.addWindow(Window(id: "A"))
    ws.addWindow(Window(id: "B"))
    ws.focusWindow(id: "B")
    ws.resizeSplit(delta: 0.10) // ratio → 0.4 (A side)
    ws.toggleSplitDirection()   // vertical → horizontal, ratio kept
    let layout = ws.getLayout()
    let aRect = layout.first { $0.0.id == "A" }!.1
    let bRect = layout.first { $0.0.id == "B" }!.1
    // A now holds 40% of the height (was the left child, still first child).
    try assertEqual(Int(aRect.height.rounded()), 421) // 1072*0.4 - 8
    try assertEqual(Int(bRect.height.rounded()), 635) // 1072*0.6 - 8
}

// MARK: - WindowOrdering (slot preservation)

func testWindowOrderingPreservesPreviousOrder() throws {
    let current = ["A", "B", "C", "D"]
    let ordered = WindowOrdering.reorder(current, previousKeyOrder: ["C", "A"], matchingKey: { $0 }, sortNew: { $0 < $1 })
    try assertEqual(ordered, ["C", "A", "B", "D"])
}

func testWindowOrderingSortsEverythingWhenNoPreviousOrder() throws {
    let current = ["D", "B", "C", "A"]
    let ordered = WindowOrdering.reorder(current, previousKeyOrder: [], matchingKey: { $0 }, sortNew: { $0 < $1 })
    try assertEqual(ordered, ["A", "B", "C", "D"])
}

func testWindowOrderingDropsRemovedWindowsFromPreviousOrder() throws {
    let current = ["A", "C", "D"]
    let ordered = WindowOrdering.reorder(current, previousKeyOrder: ["D", "B", "A"], matchingKey: { $0 }, sortNew: { $0 < $1 })
    // "D" and "A" survive from the previous order; "B" is gone; "C" is new → tail
    try assertEqual(ordered, ["D", "A", "C"])
}

func testWindowOrderingMatchesEachItemOnce() throws {
    let current = ["X", "X", "Y"]
    let ordered = WindowOrdering.reorder(current, previousKeyOrder: ["X"], matchingKey: { $0 }, sortNew: { $0 < $1 })
    // The first "X" keeps its previous rank; the second is a new window → tail
    try assertEqual(ordered, ["X", "X", "Y"])
}

// MARK: - Slot preservation (reassignLayoutOrder)

func testRebuildWithSameSetKeepsIdenticalSlots() throws {
    let ws1 = Workspace(monitorRect: Rect(x: 0, y: 0, width: 1920, height: 1080))
    for id in ["A", "B", "C", "D"] { ws1.addWindow(Window(id: id)) }
    let layout1 = ws1.getLayout()

    // Rebuild with a scrambled insertion order, then restore the previous ranks
    let ws2 = Workspace(monitorRect: Rect(x: 0, y: 0, width: 1920, height: 1080))
    for id in ["D", "C", "B", "A"] { ws2.addWindow(Window(id: id)) }
    ws2.reassignLayoutOrder(layout1.map { $0.0.id })

    let layout2 = ws2.getLayout()
    try assertEqual(layout2.map { $0.0.id }, layout1.map { $0.0.id })
    for ((w1, r1), (w2, r2)) in zip(layout1, layout2) {
        try assertEqual(w1.id, w2.id)
        try assertEqual(r1, r2)
    }
}

func testNewWindowTakesTailSlot() throws {
    let ws1 = Workspace(monitorRect: Rect(x: 0, y: 0, width: 1920, height: 1080))
    for id in ["A", "B", "C"] { ws1.addWindow(Window(id: id)) }
    let previousOrder = ws1.getLayout().map { $0.0.id }

    // Rebuild with the same windows plus a new window "D" appended at the tail
    let ws2 = Workspace(monitorRect: Rect(x: 0, y: 0, width: 1920, height: 1080))
    for id in previousOrder + ["D"] { ws2.addWindow(Window(id: id)) }
    ws2.reassignLayoutOrder(previousOrder + ["D"])

    // Existing windows keep their slots; D lands in the last one
    try assertEqual(ws2.getLayout().map { $0.0.id }, previousOrder + ["D"])
}

func testStickyWindowKeepsLeftmostSlotDespiteDiscoveryOrder() throws {
    let ws1 = Workspace(monitorRect: Rect(x: 0, y: 0, width: 1920, height: 1080))
    for id in ["B", "A", "C"] { ws1.addWindow(Window(id: id)) }
    let previousOrder = ws1.getLayout().map { $0.0.id }
    try assertEqual(previousOrder.first, "B")

    // Discovery now returns windows scrambled; the previous ranks keep B in slot 0
    let ws2 = Workspace(monitorRect: Rect(x: 0, y: 0, width: 1920, height: 1080))
    for id in ["A", "C", "B"] { ws2.addWindow(Window(id: id)) }
    ws2.reassignLayoutOrder(previousOrder)

    let result = ws2.getLayout().map { $0.0.id }
    try assertEqual(result.first, "B")
    try assertEqual(result, previousOrder)
}

func testReassignLayoutOrderKeepsFocus() throws {
    let ws = Workspace(monitorRect: Rect(x: 0, y: 0, width: 1920, height: 1080))
    ws.addWindow(Window(id: "A"))
    ws.addWindow(Window(id: "B"))
    ws.focusWindow(id: "B")
    ws.reassignLayoutOrder(["B", "A"])
    try assertEqual(ws.focusedWindowID, "B")
    try assertEqual(ws.getLayout().map { $0.0.id }, ["B", "A"])
}

func testAppTilingRuleDecodesSticky() throws {
    let decoder = JSONDecoder()
    let rule = try decoder.decode(AppTilingRule.self, from: Data("\"sticky\"".utf8))
    try assertEqual(rule, .sticky)
    try assertEqual(rule.excludesFromLayout, false)
}

func testAppTilingRuleDecodesFromConfigDict() throws {
    let decoder = JSONDecoder()
    let data = Data(#"{"com.spotify.client": "float", "com.apple.Notes": "sticky", "com.apple.Safari": "normal"}"#.utf8)
    let rules = try decoder.decode([String: AppTilingRule].self, from: data)
    try assertEqual(rules["com.spotify.client"], .float)
    try assertEqual(rules["com.apple.Notes"], .sticky)
    try assertEqual(rules["com.apple.Safari"], .normal)
    try assertEqual(rules["com.apple.Notes"]?.excludesFromLayout, false)
}

// MARK: - WindowFilter (role/subrole classification)

func testWindowFilterStandardWindowPasses() throws {
    let result = WindowFilter.isTileable(
        role: "AXWindow",
        subrole: "AXStandardWindow",
        size: CGSize(width: 800, height: 600),
        excludedSubroles: AXSubrole.excludedDefaults
    )
    try assertEqual(result, true)
}

func testWindowFilterRejectsNonWindowRole() throws {
    let result = WindowFilter.isTileable(
        role: "AXMenu",
        subrole: nil,
        size: CGSize(width: 800, height: 600),
        excludedSubroles: AXSubrole.excludedDefaults
    )
    try assertEqual(result, false)
}

func testWindowFilterRejectsNilRole() throws {
    let result = WindowFilter.isTileable(
        role: nil,
        subrole: "AXStandardWindow",
        size: CGSize(width: 800, height: 600),
        excludedSubroles: AXSubrole.excludedDefaults
    )
    try assertEqual(result, false)
}

func testWindowFilterNilSubroleAccepted() throws {
    let result = WindowFilter.isTileable(
        role: "AXWindow",
        subrole: nil,
        size: CGSize(width: 800, height: 600),
        excludedSubroles: AXSubrole.excludedDefaults
    )
    try assertEqual(result, true)
}

func testWindowFilterRejectsEachDefaultExcludedSubrole() throws {
    for subrole in AXSubrole.excludedDefaults {
        let result = WindowFilter.isTileable(
            role: "AXWindow",
            subrole: subrole,
            size: CGSize(width: 800, height: 600),
            excludedSubroles: AXSubrole.excludedDefaults
        )
        try assert(!result, "expected \(subrole) to be excluded")
    }
}

func testWindowFilterConfigOverrideReplacesDefaults() throws {
    let overrides: Set<String> = ["AXPopover"]
    try assertEqual(
        WindowFilter.isTileable(role: "AXWindow", subrole: "AXDialog", size: CGSize(width: 800, height: 600), excludedSubroles: overrides),
        true
    )
    try assertEqual(
        WindowFilter.isTileable(role: "AXWindow", subrole: "AXPopover", size: CGSize(width: 800, height: 600), excludedSubroles: overrides),
        false
    )
}

func testWindowFilterEmptyOverrideTilesEverythingStandard() throws {
    let result = WindowFilter.isTileable(
        role: "AXWindow",
        subrole: "AXDialog",
        size: CGSize(width: 800, height: 600),
        excludedSubroles: []
    )
    try assertEqual(result, true)
}

func testWindowFilterRejectsZeroSize() throws {
    let zeroWidth = WindowFilter.isTileable(
        role: "AXWindow", subrole: "AXStandardWindow", size: CGSize(width: 0, height: 600),
        excludedSubroles: AXSubrole.excludedDefaults
    )
    let zeroHeight = WindowFilter.isTileable(
        role: "AXWindow", subrole: "AXStandardWindow", size: CGSize(width: 800, height: 0),
        excludedSubroles: AXSubrole.excludedDefaults
    )
    try assertEqual(zeroWidth, false)
    try assertEqual(zeroHeight, false)
}

func testTesseraConfigDefaultExcludedSubroles() throws {
    let config = TesseraConfig()
    try assertEqual(config.excludedSubroles, Array(AXSubrole.excludedDefaults).sorted())
}

// MARK: - Layout presets (masterStack / columns)

private let presetRect = Rect(x: 0, y: 0, width: 1920, height: 1080)
private let presetConfig = TesseraConfig(layoutMode: .masterStack, masterRatio: 0.6)
private func layoutFor(_ ids: [String], mode: LayoutMode = .masterStack) -> [(Window, Rect)] {
    let ws = Workspace(monitorRect: presetRect, config: mode == .masterStack ? presetConfig : TesseraConfig(layoutMode: mode))
    ws.applyPreset(mode, orderedIDs: ids)
    return ws.getLayout()
}
private func rounded(_ r: Rect) -> [Int] {
    [Int(r.x.rounded()), Int(r.y.rounded()), Int(r.width.rounded()), Int(r.height.rounded())]
}

func testLayoutModeCycleOrder() throws {
    let sequence = [LayoutMode.bsp, LayoutMode.columns, LayoutMode.masterStack]
    for mode in sequence {
        try assertEqual(mode.next(), LayoutMode.allCases[(LayoutMode.allCases.firstIndex(of: mode)! + 1) % LayoutMode.allCases.count])
    }
    try assertEqual(LayoutMode(rawValue: "masterStack"), .masterStack)
    try assertEqual(LayoutMode(rawValue: "columns"), .columns)
    try assertNil(LayoutMode(rawValue: "unknown"))
    try assertEqual(TesseraConfig().layoutMode, .bsp)
}

func testMasterStackSingleWindowFillsArea() throws {
    let layout = layoutFor(["A"])
    try assertEqual(layout.count, 1)
    try assertEqual(rounded(layout[0].1), [8, 8, 1904, 1064])
}

func testMasterStackTwoWindowsMasterBetterThanCrisscross() throws {
    let layout = layoutFor(["A", "B"])
    try assertEqual(layout.count, 2)
    let a = layout.first { $0.0.id == "A" }!.1
    let b = layout.first { $0.0.id == "B" }!.1
    try assertEqual(rounded(a), [8, 8, 1139, 1064]) // master = 60% of usable width
    try assertEqual(rounded(b), [1155, 8, 757, 1064]) // stack column on the right
}

func testMasterStackThreeWindowsStackAsRows() throws {
    let layout = layoutFor(["A", "B", "C"])
    try assertEqual(layout.count, 3)
    let a = layout.first { $0.0.id == "A" }!.1
    let b = layout.first { $0.0.id == "B" }!.1
    let c = layout.first { $0.0.id == "C" }!.1
    try assertEqual(rounded(a), [8, 8, 1139, 1064]) // master keeps full height
    try assertEqual(rounded(b), [1155, 8, 757, 528]) // row 1
    try assertEqual(rounded(c), [1155, 544, 757, 528]) // row 2 below row 1
    try assertEqual(Int(b.width), Int(c.width))
    try assertLessThan(b.y, c.y)
}

func testMasterStackSlotPreservedAcrossRetile() throws {
    let first = layoutFor(["A", "B", "C"])
    let second = layoutFor(["A", "B", "C"])
    try assertEqual(second.first { $0.0.id == "A" }!.1, first.first { $0.0.id == "A" }!.1)
    try assertEqual(second.first { $0.0.id == "C" }!.1, first.first { $0.0.id == "C" }!.1)
}

func testMasterStackMasterIsFirstWindow() throws {
    let layout = layoutFor(["B", "A"])
    let b = layout.first { $0.0.id == "B" }!.1
    try assertEqual(rounded(b), [8, 8, 1139, 1064])
}

func testMasterStackRemoveWindowSucceeds() throws {
    let ws = Workspace(monitorRect: presetRect, config: presetConfig)
    ws.applyPreset(.masterStack, orderedIDs: ["A", "B", "C"])
    let removed = ws.removeWindow(id: "B")
    try assertEqual(removed?.id, "B")
    try assertEqual(ws.getLayout().count, 2)
}

func testColumnsGetEqualWidth() throws {
    let layout = layoutFor(["A", "B", "C"], mode: .columns)
    try assertEqual(layout.count, 3)
    let sorted = layout.sorted { $0.1.x < $1.1.x }
    let widths = Set(sorted.map { Int($0.1.width.rounded()) })
    try assertEqual(widths.count, 1)
    let heights = Set(sorted.map { Int($0.1.height.rounded()) })
    try assertEqual(heights.count, 1)
    try assertEqual(Int(sorted[0].1.y.rounded()), 8)
}

func testColumnsSplitAdjustsWithCount() throws {
    let two = layoutFor(["A", "B"], mode: .columns).sorted { $0.1.x < $1.1.x }
    let three = layoutFor(["A", "B", "C"], mode: .columns).sorted { $0.1.x < $1.1.x }
    try assertEqual(Int(two[0].1.width.rounded()), 948)
    try assertLessThan(three[0].1.width, two[0].1.width)
    try assertEqual(two[0].1.x, three[0].1.x)
    try assertLessThan(three[0].1.x, three[1].1.x)
}

func testApplyPresetEmptyClearsTree() throws {
    let ws = Workspace(monitorRect: presetRect, config: presetConfig)
    ws.applyPreset(.masterStack, orderedIDs: ["A"])
    try assert(ws.root != nil, "expected tree after adding A")
    ws.applyPreset(.masterStack, orderedIDs: [])
    try assertNil(ws.root)
}

// MARK: - Per-display layout state (LayoutState)

private func temporaryStateFile() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("tessera-layout-\(UUID().uuidString).json")
}

func testLayoutStateDefaultsToNoOverrides() throws {
    let state = LayoutState()
    try assertEqual(state.displayModes.count, 0)
    try assertEqual(state.mode(for: 1001, fallback: .bsp), .bsp)
    try assertEqual(state.mode(for: 1001, fallback: .masterStack), .masterStack)
}

func testLayoutStateOverrideResolutionAndClear() throws {
    var state = LayoutState()
    state.setMode(.masterStack, for: 1001)
    try assertEqual(state.mode(for: 1001, fallback: .bsp), .masterStack)
    try assertEqual(state.mode(for: 1002, fallback: .bsp), .bsp)
    state.setMode(nil, for: 1001)
    try assertEqual(state.mode(for: 1001, fallback: .bsp), .bsp)
    state.setMode(.columns, for: 1003)
    state.setMode(nil, for: 1003)
    try assertEqual(state.displayModes.count, 0)
}

func testLayoutStatePruneDropsUnpluggedDisplays() throws {
    var state = LayoutState(displayModes: ["1001": .masterStack, "1002": .columns, "1003": .bsp])
    state.prune(liveDisplayIDs: [1001, 1003])
    try assertEqual(state.mode(for: 1001, fallback: .bsp), .masterStack)
    try assertEqual(state.mode(for: 1002, fallback: .bsp), .bsp) // pruned → fallback
    try assertEqual(state.displayModes.count, 2)
}

func testLayoutStateStoreRoundTrip() throws {
    let url = temporaryStateFile()
    defer { try? FileManager.default.removeItem(at: url) }
    var state = LayoutState()
    state.setMode(.columns, for: 1001)
    state.setMode(.masterStack, for: 1002)
    try LayoutStateStore.save(state, to: url)
    let loaded = LayoutStateStore.load(from: url)
    try assertEqual(loaded, state)
    try assertEqual(loaded.mode(for: 1001, fallback: .bsp), .columns)
    try assertEqual(loaded.mode(for: 1002, fallback: .bsp), .masterStack)
}

func testLayoutStateStoreMissingAndCorruptFiles() throws {
    let missing = temporaryStateFile()
    defer { try? FileManager.default.removeItem(at: missing) }
    try assertEqual(LayoutStateStore.load(from: missing), LayoutState())

    let corrupt = temporaryStateFile()
    defer { try? FileManager.default.removeItem(at: corrupt) }
    try Data("not json at all {{{".utf8).write(to: corrupt)
    try assertEqual(LayoutStateStore.load(from: corrupt), LayoutState())
}

func testLayoutStateSurvivesDaemonStyleReload() throws {
    // Simulates the daemon boot + reload: save persistable state to disk,
    // "restart" by loading from the same file, and confirm the override
    // (and the fallback for unset displays) come back.
    let url = temporaryStateFile()
    defer { try? FileManager.default.removeItem(at: url) }
    var before = LayoutState()
    before.setMode(.masterStack, for: 1001)
    try LayoutStateStore.save(before, to: url)

    let boot = LayoutStateStore.load(from: url)
    try assertEqual(boot.mode(for: 1001, fallback: .bsp), .masterStack)
    try assertEqual(boot.mode(for: 9999, fallback: .bsp), .bsp)

    let reloaded = LayoutStateStore.load(from: url)
    try assertEqual(reloaded.mode(for: 1001, fallback: .bsp), .masterStack)
    try assertEqual(reloaded, before)
}

func testLayoutStateRoundTripsFullState() throws {
    let url = temporaryStateFile()
    defer { try? FileManager.default.removeItem(at: url) }
    var state = LayoutState()
    state.setMode(.masterStack, for: 1001)
    state.setSplitStates(["A|B": SplitState(ratio: 0.7, orientation: .vertical)], for: 1001)
    state.setFloatRects(["Music|Tracks": FloatRect(x: 20, y: 40, width: 800, height: 600, displayID: 1001)])
    try LayoutStateStore.save(state, to: url)
    let loaded = LayoutStateStore.load(from: url)
    try assertEqual(loaded, state)
    try assertEqual(loaded.splitStates(for: 1001)["A|B"]?.ratio, 0.7)
    try assertEqual(loaded.floatRect(for: "Music|Tracks")?.width, 800)
}

func testLayoutStateOldFileStillDecodes() throws {
    // A state.json written before splitStates/floatRects existed must still
    // load (both new sections default to empty).
    let url = temporaryStateFile()
    defer { try? FileManager.default.removeItem(at: url) }
    try Data(#"{"displayModes":{"1":"columns"}}"#.utf8).write(to: url)
    let loaded = LayoutStateStore.load(from: url)
    try assertEqual(loaded.mode(for: 1, fallback: .bsp), .columns)
    try assertEqual(loaded.splitStates(for: 1).count, 0)
    try assertEqual(loaded.floatRects.count, 0)
}

func testLayoutStateSetSplitStatesEmptyRemovesEntry() throws {
    var state = LayoutState()
    state.setSplitStates(["A|B": SplitState(ratio: 0.7, orientation: .vertical)], for: 1001)
    try assertEqual(state.splitStates.count, 1)
    state.setSplitStates([:], for: 1001)
    try assertEqual(state.splitStates.count, 0)
}

// MARK: - Split state persistence (captureSplitState / applySplitState)

func testCaptureApplyRatiosRoundTripPreservesGeometry() throws {
    let ws = Workspace(monitorRect: Rect(x: 0, y: 0, width: 1920, height: 1080))
    ws.applyPreset(.bsp, orderedIDs: ["A", "B"])
    ws.focusWindow(id: "A")
    ws.resizeSplit(delta: 0.2) // A grows → ratio 0.7
    let before = ws.getLayout().first { $0.0.id == "A" }!.1
    try assertEqual(Int(before.width.rounded()), 1330) // 1912*0.7 - 8

    let captured = ws.captureSplitState()
    try assertEqual(captured["A|B"]?.ratio, 0.7)
    try assertEqual(captured["A|B"]?.orientation, .vertical)

    // Simulate the daemon re-tile: full tree rebuild + ratio restore.
    let rebuilt = Workspace(monitorRect: Rect(x: 0, y: 0, width: 1920, height: 1080))
    rebuilt.applyPreset(.bsp, orderedIDs: ["A", "B"])
    try assertEqual(Int(rebuilt.getLayout().first { $0.0.id == "A" }!.1.width.rounded()), 948) // 50/50
    rebuilt.applySplitState(captured)
    let after = rebuilt.getLayout().first { $0.0.id == "A" }!.1
    try assertEqual(Int(after.width.rounded()), 1330)
    try assertEqual(Int(after.x.rounded()), Int(before.x.rounded()))
}

func testApplySplitStateKeepsSurvivingSplitsAcrossAdds() throws {
    // 1. User tree: A|B at 0.7.
    let before = Workspace(monitorRect: Rect(x: 0, y: 0, width: 1920, height: 1080))
    before.applyPreset(.bsp, orderedIDs: ["A", "B"])
    before.focusWindow(id: "A")
    before.resizeSplit(delta: 0.2)
    let persisted = before.captureSplitState()
    try assertEqual(persisted["A|B"]?.ratio, 0.7)

    // 2. C window arrives → daemon re-tiles [A,B,C] with the persisted state.
    //    The rebuild re-shapes (A is now narrower, so it splits horizontally),
    //    but the surviving A|B grouping keeps its weight via the pair key.
    let retiled = Workspace(monitorRect: Rect(x: 0, y: 0, width: 1920, height: 1080))
    retiled.applyPreset(.bsp, orderedIDs: ["A", "B", "C"])
    retiled.applySplitState(persisted)
    let afterAdd = retiled.getLayout().map { "\($0.0.id):\(Int($0.1.x.rounded()))" }
    try assertEqual(afterAdd, ["A:8", "B:677", "C:964"]) // A|B pair holds 0.7 of the left split

    // 3. Daemon persists the retiled state; a restart must reproduce it exactly.
    let retiledState = retiled.captureSplitState()
    try assertEqual(retiledState["A|B"]?.ratio, 0.7)
    let restart = Workspace(monitorRect: Rect(x: 0, y: 0, width: 1920, height: 1080))
    restart.applyPreset(.bsp, orderedIDs: ["A", "B", "C"])
    restart.applySplitState(retiledState)
    let afterRestart = restart.getLayout().map { "\($0.0.id):\(Int($0.1.x.rounded()))" }
    try assertEqual(afterRestart, afterAdd)
}

func testApplySplitStateIgnoresUnknownKeys() throws {
    let ws = Workspace(monitorRect: Rect(x: 0, y: 0, width: 1920, height: 1080))
    ws.applyPreset(.bsp, orderedIDs: ["A", "B"])
    ws.applySplitState(["X|Y": SplitState(ratio: 0.9, orientation: .vertical),
                                 "A|B": SplitState(ratio: 0.65, orientation: .vertical)])
    // Matching key applies, unmatched keys are ignored.
    let a = ws.getLayout().first { $0.0.id == "A" }!.1
    try assertEqual(Int(a.width.rounded()), 1235) // 1912*0.65 - 8 = 1234.8 → 1235
}

// MARK: - Hotkey model (HotkeyBinding / HotkeyBindings)

func testHotkeyDefaultsCarryDocumentedCombos() throws {
    try assertEqual(HotkeyBindings.defaultDisplay(for: "tile"), "⌘⌥⏎")
    try assertEqual(HotkeyBindings.defaultDisplay(for: "quit"), "⌘⌥⇧Q")
    try assertEqual(HotkeyBindings.defaultDisplay(for: "focusLeft"), "⌘⌥H")
    try assertEqual(HotkeyBindings.defaultDisplay(for: "focusRight"), "⌘⌥L")
    try assertEqual(HotkeyBindings.defaultDisplay(for: "cycleNext"), "⌘⌥↓")
    try assertEqual(HotkeyBindings.defaultDisplay(for: "resizeShrink"), "⌘⌥[")
}

func testHotkeyNormalizedFlagsAliasesAndOrder() throws {
    try assertEqual(HotkeyBindings.normalizedFlags(["alt", "command", "CTRL"]), ["cmd", "opt", "ctrl"])
    try assertEqual(HotkeyBindings.normalizedFlags(["opt", "cmd", "opt", "shift", "unknown"]), ["cmd", "opt", "shift"])
    try assertEqual(HotkeyBindings.normalizedFlags([]), [])
    try assertEqual(HotkeyBindings.normalizedFlags(["capslock", "fn"]), ["fn", "caps"])
}

func testHotkeyMergeKeepsDefaultsWithoutOverrides() throws {
    try assert(HotkeyBindings.merge(defaults: HotkeyBindings.defaults, overrides: nil) == HotkeyBindings.defaults)
    try assert(HotkeyBindings.merge(defaults: HotkeyBindings.defaults, overrides: [:]) == HotkeyBindings.defaults)
}

func testHotkeyMergeOverrideAddsComboAndKeepsAliases() throws {
    // Overriding focusLeft onto ⌘⌥T (17) adds the new combo while the H (4)
    // and K (40) aliases survive; T was otherwise unclaimed so nothing frees.
    let merged = HotkeyBindings.merge(defaults: HotkeyBindings.defaults,
                                      overrides: ["focusLeft": HotkeySpec(keyCode: 17, flags: ["cmd", "opt"])])
    try assertEqual(merged.filter { $0.action == "focusLeft" }.count, 3)
    try assert(merged.contains { $0.action == "focusLeft" && $0.keyCode == 17 })
    try assert(merged.contains { $0.action == "focusLeft" && $0.keyCode == 4 })
    try assert(merged.contains { $0.action == "focusLeft" && $0.keyCode == 40 })
    try assert(merged.contains { $0.action == "tile" && $0.keyCode == 36 }) // tile untouched
}

func testHotkeyMergeOverrideFreesOnlyTheClaimedKey() throws {
    // Rebind "remove" onto L (37): focusRight loses its L but keeps J (38).
    let merged = HotkeyBindings.merge(defaults: HotkeyBindings.defaults,
                                      overrides: ["remove": HotkeySpec(keyCode: 37, flags: ["cmd", "opt"])])
    try assert(merged.contains { $0.action == "remove" && $0.keyCode == 37 })
    try assert(!merged.contains { $0.action == "focusRight" && $0.keyCode == 37 })
    try assert(merged.contains { $0.action == "focusRight" && $0.keyCode == 38 })
}

func testHotkeyMergeActiveCombos() throws {
    try assertEqual(HotkeyBindings.activeCombos(HotkeyBindings.defaults, action: "focusLeft"), ["⌘⌥H", "⌘⌥K"])
    try assertEqual(HotkeyBindings.activeCombos(HotkeyBindings.defaults, action: "quit"), ["⌘⌥⇧Q"])
    let merged = HotkeyBindings.merge(defaults: HotkeyBindings.defaults,
                                      overrides: ["focusRight": HotkeySpec(keyCode: 18, flags: ["cmd", "opt"])])
    try assertEqual(HotkeyBindings.activeCombos(merged, action: "focusRight"), ["⌘⌥1", "⌘⌥L", "⌘⌥J"])
}

func testHotkeyMergePreservesUnknownAction() throws {
    let merged = HotkeyBindings.merge(defaults: HotkeyBindings.defaults,
                                      overrides: ["shutdown": HotkeySpec(keyCode: 44, flags: ["cmd", "opt"])])
    try assert(merged.contains { $0.action == "shutdown" && $0.keyCode == 44 })
    try assertEqual(merged.count, HotkeyBindings.defaults.count + 1)
}

func testHotkeyKeySymbols() throws {
    try assertEqual(HotkeyBindings.keySymbol(for: 36), "⏎")
    try assertEqual(HotkeyBindings.keySymbol(for: 4), "H")
    try assertEqual(HotkeyBindings.keySymbol(for: 3), "F")
    try assertEqual(HotkeyBindings.keySymbol(for: 125), "↓")
    try assertEqual(HotkeyBindings.keySymbol(for: 49), "Space")
    try assert(HotkeyBindings.keySymbol(for: 255).hasPrefix("Key 0x"))
}

func testHotkeyDisplayUsesCanonicalModifierOrder() throws {
    try assertEqual(HotkeyBinding(action: "tile", keyCode: 36, flags: ["opt", "cmd"]).display, "⌘⌥⏎")
    try assertEqual(HotkeyBinding(action: "quit", keyCode: 12, flags: ["shift", "cmd", "opt"]).display, "⌘⌥⇧Q")
}

func testHotkeyCanonicalActionsCoverDefaults() throws {
    let defaultActions = Set(HotkeyBindings.defaults.map { $0.action })
    let canonical = Set(HotkeyBindings.canonicalActions)
    try assert(defaultActions.isSubset(of: canonical))
    try assertEqual(HotkeyBindings.canonicalActions.count, 14)
}

// MARK: - Update model (ReleaseVersion / UpdateAppcast)

func testVersionCompareAcceptsAlphanumericComponents() throws {
    try assert(ReleaseVersion.isNewer("v0.5.0", than: "0.4.0"))
    try assert(ReleaseVersion.isNewer("0.5", than: "v0.4.9"))
    try assert(ReleaseVersion.isNewer("1.0.0", than: "0.99.99"))
    try assert(!ReleaseVersion.isNewer("0.4.0", than: "v0.4.0"))
    try assert(!ReleaseVersion.isNewer("v0.4.0", than: "0.4.0"))
    try assert(!ReleaseVersion.isNewer("0.3.9", than: "0.4.0"))
    try assert(!ReleaseVersion.isNewer("0.4.0-beta1", than: "0.4.0")) // prerelease < release
}

func testVersionCompareShorterForms() throws {
    try assert(ReleaseVersion.isNewer("0.5", than: "0.4"))
    try assertEqual(ReleaseVersion.compare("0.5", "0.5.0"), 0)
    try assertEqual(ReleaseVersion.compare("v1", "0.1.0"), 1)
    try assertEqual(ReleaseVersion.compare("0.4.0", "0.4"), 0)
}

func testAppcastParseReturnsNewer() throws {
    let appcast = """
    {"version":"0.5.0","tag":"v0.5.0","url":"https://example.com/x.zip","sha256":"abc","size":1234567}
    """.data(using: .utf8)!
    let info = try UpdateAppcast.parse(appcast, currentVersion: "0.4.0")
    try assert(info != nil, "expected an update to be reported")
    try assertEqual(info?.version, "0.5.0")
    try assertEqual(info?.size, 1234567)
}

func testAppcastParseNilWhenOlderOrEqual() throws {
    let appcast = """
    {"version":"0.4.0","tag":"v0.4.0","url":"https://example.com/x.zip","sha256":"abc","size":1}
    """.data(using: .utf8)!
    try assertNil(try UpdateAppcast.parse(appcast, currentVersion: "0.4.0"))
    try assertNil(try UpdateAppcast.parse(appcast, currentVersion: "0.5.0"))
}

func testAppcastParseThrowsOnMalformedData() throws {
    let bad = "{not json".data(using: .utf8)!
    do {
        _ = try UpdateAppcast.parse(bad, currentVersion: "0.4.0")
        throw TestError.assertionFailed("expected decode failure")
    } catch is DecodingError {
        // expected
    }
}

// MARK: - Runner

let tests: [(String, () throws -> Void)] = [
    ("Add first window fills usable area", testAddFirstWindowFillsUsableArea),
    ("Second window splits vertically by default", testSecondWindowSplitsVerticallyByDefault),
    ("Third window splits horizontal on focused", testThirdWindowSplitsHorizontalOnFocused),
    ("Focus stays on existing window", testFocusStaysOnExistingWindow),
    ("New window can get focus", testNewWindowCanGetFocus),
    ("Remove window collapses tree", testRemoveWindowCollapsesTree),
    ("Remove focused window collapses and refocuses", testRemoveFocusedWindowCollapsesAndRefocuses),
    ("Focus window by ID", testFocusWindowByID),
    ("Focus nonexistent window returns false", testFocusNonexistentWindowReturnsFalse),
    ("Removing last window empties workspace", testRemovingLastWindowEmptiesWorkspace),
    ("Remove from empty workspace returns nil", testRemoveFromEmptyWorkspaceReturnsNil),
    ("Remove middle window from three", testRemoveMiddleWindowFromThree),
    ("Deeply nested tree seven windows", testDeeplyNestedTreeSevenWindows),
    ("Add/remove cycle preserves correctness", testAddRemoveCyclePreservesCorrectness),
    ("Large monitor rect", testLargeMonitorRect),
    ("Total area invariant no gaps", testTotalAreaInvariantNoGaps),
    // Focus navigation
    ("FocusedWindowID on empty workspace is nil", testFocusedWindowIDOnEmptyWorkspace),
    ("FocusedWindowID after add", testFocusedWindowIDAfterAdd),
    ("FocusedWindowID after focusRight", testFocusedWindowIDAfterFocusRight),
    ("FocusedWindowID after focusLeft round-trip", testFocusedWindowIDAfterFocusLeft),
    ("FocusLeft at edge returns false", testFocusLeftAtEdgeReturnsFalse),
    ("FocusRight at edge returns false", testFocusRightAtEdgeReturnsFalse),
    ("FocusRight moves to rightmost window", testFocusRightMovesToRightmostWindow),
    ("FocusLeft moves to leftmost window", testFocusLeftMovesToLeftmostWindow),
    ("FocusRight after remove returns false when stacked", testFocusRightAfterRemoveReturnsFalseWhenStacked),
    ("FocusLeft on empty workspace returns false", testFocusLeftOnEmptyWorkspaceReturnsFalse),
    ("FocusRight on empty workspace returns false", testFocusRightOnEmptyWorkspaceReturnsFalse),
    // KeyBinding
    ("KeyBinding tile matches correctly", testKeyBindingTileMatchesCorrectly),
    ("KeyBinding wrong keyCode does not match", testKeyBindingWrongKeyCodeDoesNotMatch),
    ("KeyBinding missing flags does not match", testKeyBindingMissingFlagsDoesNotMatch),
    ("KeyBinding extra flags still matches", testKeyBindingExtraFlagsStillMatches),
    // Fullscreen binding
    ("KeyBinding fullscreen matches", testKeyBindingFullscreenMatches),
    ("KeyBinding fullscreen wrong keyCode", testKeyBindingFullscreenWrongKeyCode),
    ("KeyBinding fullscreen missing flags", testKeyBindingFullscreenMissingFlags),
    // ScreenManager
    ("ScreenManager rect conversion main display", testScreenManagerRectConversionMainDisplay),
    ("ScreenManager rect conversion display above", testScreenManagerRectConversionDisplayAbove),
    ("ScreenManager rect conversion display above misaligned heights", testScreenManagerRectConversionDisplayAboveMisalignedHeights),
    ("ScreenManager rect conversion display right", testScreenManagerRectConversionDisplayRight),
    ("Display containing point", testDisplayContainingPoint),
    ("Display containing window center", testDisplayContainingWindowCenter),
    ("Display containing off-screen returns nil", testDisplayContainingOffScreenReturnsNil),
    ("Desktop wallpaper detection across displays", testDesktopWallpaperDetection),
    ("Desktop wallpaper spanning multiple displays", testDesktopWallpaperSpansMultipleDisplays),
    // Split direction toggle
    ("Toggle split vertical to horizontal", testToggleSplitVerticalToHorizontal),
    ("Toggle split round trip", testToggleSplitRoundTrip),
    ("Toggle split single window returns false", testToggleSplitSingleWindowReturnsFalse),
    ("Toggle split nested only affects focused split", testToggleSplitNestedOnlyAffectsFocusedSplit),
    ("Toggle split preserves gap inset", testToggleSplitPreservesGapInset),
    // Resize split
    ("Resize split single window returns false", testResizeSplitSingleWindowReturnsFalse),
    ("Resize split grows focused right child", testResizeSplitGrowsFocusedRightChild),
    ("Resize split shrinks focused right child", testResizeSplitShrinksFocusedRightChild),
    ("Resize split round trip restores equal split", testResizeSplitRoundTripRestoresEqualSplit),
    ("Resize split clamps to min/max", testResizeSplitClampsToMinMax),
    ("Resize split ratio survives toggle direction", testResizeSplitRatioSurvivesToggleDirection),
    // WindowOrdering (slot preservation)
    ("WindowOrdering preserves previous order", testWindowOrderingPreservesPreviousOrder),
    ("WindowOrdering sorts all when no previous order", testWindowOrderingSortsEverythingWhenNoPreviousOrder),
    ("WindowOrdering drops removed windows from previous order", testWindowOrderingDropsRemovedWindowsFromPreviousOrder),
    ("WindowOrdering matches each item once", testWindowOrderingMatchesEachItemOnce),
    // Slot preservation
    ("Rebuild with same set keeps identical slots", testRebuildWithSameSetKeepsIdenticalSlots),
    ("New window takes tail slot", testNewWindowTakesTailSlot),
    ("Sticky window keeps leftmost slot despite discovery order", testStickyWindowKeepsLeftmostSlotDespiteDiscoveryOrder),
    ("Reassign layout order keeps focus", testReassignLayoutOrderKeepsFocus),
    ("AppTilingRule decodes sticky", testAppTilingRuleDecodesSticky),
    ("AppTilingRule decodes from config dict", testAppTilingRuleDecodesFromConfigDict),
    // WindowFilter (role/subrole classification)
    ("WindowFilter standard window passes", testWindowFilterStandardWindowPasses),
    ("WindowFilter rejects non-window role", testWindowFilterRejectsNonWindowRole),
    ("WindowFilter rejects nil role", testWindowFilterRejectsNilRole),
    ("WindowFilter nil subrole accepted", testWindowFilterNilSubroleAccepted),
    ("WindowFilter rejects each default excluded subrole", testWindowFilterRejectsEachDefaultExcludedSubrole),
    ("WindowFilter config override replaces defaults", testWindowFilterConfigOverrideReplacesDefaults),
    ("WindowFilter empty override tiles everything standard", testWindowFilterEmptyOverrideTilesEverythingStandard),
    ("WindowFilter rejects zero size", testWindowFilterRejectsZeroSize),
    ("TesseraConfig default excludedSubroles", testTesseraConfigDefaultExcludedSubroles),
    // Layout presets
    ("LayoutMode cycle order + raw values", testLayoutModeCycleOrder),
    ("masterStack single window fills area", testMasterStackSingleWindowFillsArea),
    ("masterStack two windows master + stack column", testMasterStackTwoWindowsMasterBetterThanCrisscross),
    ("masterStack three windows stack as rows", testMasterStackThreeWindowsStackAsRows),
    ("masterStack slot preserved across retile", testMasterStackSlotPreservedAcrossRetile),
    ("masterStack master is first window", testMasterStackMasterIsFirstWindow),
    ("masterStack remove window succeeds", testMasterStackRemoveWindowSucceeds),
    ("columns get equal width/height", testColumnsGetEqualWidth),
    ("columns split adjusts with count", testColumnsSplitAdjustsWithCount),
    ("applyPreset empty clears tree", testApplyPresetEmptyClearsTree),
    // Per-display layout state
    ("LayoutState defaults to no overrides", testLayoutStateDefaultsToNoOverrides),
    ("LayoutState override resolution and clear", testLayoutStateOverrideResolutionAndClear),
    ("LayoutState prune drops unplugged displays", testLayoutStatePruneDropsUnpluggedDisplays),
    ("LayoutState store round-trip", testLayoutStateStoreRoundTrip),
    ("LayoutState store missing and corrupt files", testLayoutStateStoreMissingAndCorruptFiles),
    ("LayoutState survives daemon-style reload", testLayoutStateSurvivesDaemonStyleReload),
    ("LayoutState round-trips full state", testLayoutStateRoundTripsFullState),
    ("LayoutState old file still decodes", testLayoutStateOldFileStillDecodes),
    ("LayoutState setSplitStates empty removes entry", testLayoutStateSetSplitStatesEmptyRemovesEntry),
    // Split ratio persistence
    ("capture/apply ratios round-trip preserves geometry", testCaptureApplyRatiosRoundTripPreservesGeometry),
    ("applySplitState keeps surviving splits across adds", testApplySplitStateKeepsSurvivingSplitsAcrossAdds),
    ("applySplitState ignores unknown keys", testApplySplitStateIgnoresUnknownKeys),
    // Hotkey model
    ("Hotkey defaults carry documented combos", testHotkeyDefaultsCarryDocumentedCombos),
    ("Hotkey normalizedFlags aliases + order", testHotkeyNormalizedFlagsAliasesAndOrder),
    ("Hotkey merge keeps defaults without overrides", testHotkeyMergeKeepsDefaultsWithoutOverrides),
    ("Hotkey merge override adds combo and keeps aliases", testHotkeyMergeOverrideAddsComboAndKeepsAliases),
    ("Hotkey merge override frees only the claimed key", testHotkeyMergeOverrideFreesOnlyTheClaimedKey),
    ("Hotkey merge active combos list", testHotkeyMergeActiveCombos),
    ("Hotkey merge preserves unknown actions", testHotkeyMergePreservesUnknownAction),
    ("Hotkey key symbols", testHotkeyKeySymbols),
    ("Hotkey display uses canonical modifier order", testHotkeyDisplayUsesCanonicalModifierOrder),
    ("Hotkey canonical actions cover defaults", testHotkeyCanonicalActionsCoverDefaults),
    // Update model
    ("Version compare accepts alphanumeric components", testVersionCompareAcceptsAlphanumericComponents),
    ("Version compare handles shorter forms", testVersionCompareShorterForms),
    ("Appcast parse returns newer release", testAppcastParseReturnsNewer),
    ("Appcast parse nil when older or equal", testAppcastParseNilWhenOlderOrEqual),
    ("Appcast parse throws on malformed data", testAppcastParseThrowsOnMalformedData),
]

var passed = 0
var failed: [(String, Error)] = []

for (name, testFn) in tests {
    do {
        try testFn()
        passed += 1
        print("  ✅ \(name)")
    } catch {
        failed.append((name, error))
        print("  ❌ \(name)")
        print("     \(error)")
    }
}

print("\n═══════════════════════════════════════")
print("  \(passed)/\(tests.count) passed", terminator: "")
if !failed.isEmpty {
    print(", \(failed.count) failed", terminator: "")
}
print()
print("═══════════════════════════════════════")

if !failed.isEmpty {
    exit(1)
}
