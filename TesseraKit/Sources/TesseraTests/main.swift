import CoreGraphics
import Foundation
import TesseraKit

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
