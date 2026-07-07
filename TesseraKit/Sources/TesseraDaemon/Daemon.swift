import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import TesseraKit
import TesseraSystem

private func describeFlags(_ f: CGEventFlags) -> String {
    var parts: [String] = []
    if f.contains(.maskAlphaShift) { parts.append("caps") }
    if f.contains(.maskShift) { parts.append("shift") }
    if f.contains(.maskControl) { parts.append("ctrl") }
    if f.contains(.maskAlternate) { parts.append("opt") }
    if f.contains(.maskCommand) { parts.append("cmd") }
    if f.contains(.maskSecondaryFn) { parts.append("fn") }
    if f.contains(.maskNumericPad) { parts.append("numPad") }
    if f.contains(.maskNonCoalesced) { parts.append("nonCoal") }
    if f.contains(.maskHelp) { parts.append("help") }
    let known: CGEventFlags = [.maskAlphaShift, .maskShift, .maskControl, .maskAlternate, .maskCommand, .maskSecondaryFn, .maskNumericPad, .maskNonCoalesced, .maskHelp]
    let extra = f.subtracting(known)
    if extra.rawValue != 0 { parts.append("extra(\(extra.rawValue))") }
    return parts.joined(separator: "+")
}

final class Daemon: @unchecked Sendable {
    let tiler: Tiler
    let bindings: [KeyBinding]
    let observer: WindowObserver

    /// Persistent BSP workspace state across operations
    var currentWorkspace: Workspace?
    /// Persistent window mapping across operations
    var currentMapper: WindowMapper?
    /// Cooldown flag to suppress spurious re-tiles from transient windows created during resize
    private var recentlyTiled = false
    /// IDs of config-floaters already centered (never re-center on subsequent tiles)
    private var centeredFloaterIDs: Set<String> = []
    /// ID of the window currently in fullscreen mode, if any (nil = not in fullscreen)
    private var fullscreenWindowID: String? = nil
    /// Fingerprints of last known tileable windows (appPID + geometry) to skip no-op auto-tiles
    private var lastTileableFingerprints: Set<String> = []

    init(tiler: Tiler, bindings: [KeyBinding]) {
        self.tiler = tiler
        self.bindings = bindings
        self.observer = WindowObserver(debounce: 0.05)
    }

    func run() {
        let pid = ProcessInfo.processInfo.processIdentifier
        print("Daemon PID: \(pid)")
        print("AX trusted: \(AXIsProcessTrusted())")
        print()

        guard checkPermissions() else {
            print("Fix permissions and re-run.")
            exit(1)
        }

        guard let tap = createEventTap() else {
            print("Failed to create event tap. Check Input Monitoring permissions.")
            exit(1)
        }
        print("Event tap created successfully.")

        if CFMachPortIsValid(tap) {
            print("Event tap is valid.")
        } else {
            print("Event tap is NOT valid — will not receive events.")
            exit(1)
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .defaultMode)
        print("Run loop source added.")

        // Set up the auto-tile callback with suppression
        observer.onChange = { [weak self] in
            guard let self, !recentlyTiled else { return }
            let windows = tiler.filterWindows(WindowDiscovery.allWindows())
            let fingerprints = Set(windows.map { "\($0.appPID):\(Int($0.position.x)):\(Int($0.position.y)):\(Int($0.size.width)):\(Int($0.size.height))" })
            guard fingerprints != lastTileableFingerprints else {
                print("[auto-tile] tileable windows unchanged — skipping")
                return
            }
            lastTileableFingerprints = fingerprints
            print("[auto-tile] tileable change detected — tiling")
            self.tileWithSuppression()
        }
        observer.start()
        print("AX observer started.")

        // Auto-tile on startup
        let initialWindows = tiler.filterWindows(WindowDiscovery.allWindows())
        if !initialWindows.isEmpty {
            print("[startup] \(initialWindows.count) windows found — auto-tiling")
            tileWithSuppression()
        }

        print()
        print("Tessera daemon running.")
        print("  ⌘⌥⏎  — tile all windows")
        print("  ⌘⌥H/J — focus left/right")
        print("  ⌘⌥K/L — focus left/right")
        print("  ⌘⌥W  — remove focused window")
        print("  ⌘⌥⇧Q — quit")
        print("  ⌘⌥H/L — focus left/right")
        print("  ⌘⌥K/J — focus left/right (vim-style)")
        print("  ⌘⌥I/M — focus up/down")
        print("  ⌘⌥F   — toggle fullscreen")
        print("Listening for keyDown events...")

        CFRunLoopRun()
    }

    /// Tile while suppressing AX notifications to avoid loops.
    /// Saves workspace + mapper state for subsequent focus/remove operations.
    func tileWithSuppression() {
        observer.isSuppressed = true
        let result = tiler.tileAllWindows()
        if let (ws, mapper, newlyFloated, animationTargets) = result {
            let startPositions = mapper.allWindows
                .filter { animationTargets.keys.contains($0.id) }
                .reduce(into: [:]) { $0[$1.id] = $1.position }
            currentWorkspace = ws
            currentMapper = mapper
            centerNewFloaters(newlyFloated: newlyFloated)
            animateWindows(targets: animationTargets, startPositions: startPositions)
        }
        observer.isSuppressed = false
        subscribeAllToDestroyed()
        fullscreenWindowID = nil
        // Refresh fingerprint cache so subsequent auto-tiles can diff accurately
        let currentWindows = tiler.filterWindows(WindowDiscovery.allWindows())
        lastTileableFingerprints = Set(currentWindows.map { "\($0.appPID):\(Int($0.position.x)):\(Int($0.position.y)):\(Int($0.size.width)):\(Int($0.size.height))" })

        // Prevent spurious re-tiles from transient windows created during resize.
        // Must outlast animation (150ms) + AX debounce interval + notification delivery window.
        recentlyTiled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.recentlyTiled = false
        }
    }

    private func animateWindows(targets: [String: CGPoint], startPositions: [String: CGPoint], steps: Int = 8, duration: TimeInterval = 0.15) {
        guard !targets.isEmpty else { return }
        let interval = duration / Double(max(steps, 1))
        print("[animate] sliding \(targets.count) windows — \(steps) steps over \(Int(duration * 1000))ms")

        for i in 1...steps {
            let t = Double(i) / Double(steps)
            let eased = t < 1 ? 1 - pow(1 - t, 2) : 1.0
            DispatchQueue.main.asyncAfter(deadline: .now() + interval * Double(i)) { [weak self] in
                guard let self else { return }
                for (id, targetPos) in targets {
                    guard let macWin = self.currentMapper?.window(withID: id) else { continue }
                    let startPos = startPositions[id] ?? targetPos
                    let x = startPos.x + (targetPos.x - startPos.x) * eased
                    let y = startPos.y + (targetPos.y - startPos.y) * eased
                    var pt = CGPoint(x: x, y: y)
                    if let axValue = AXValueCreate(.cgPoint, &pt) {
                        AXUIElementSetAttributeValue(macWin.windowRef, kAXPositionAttribute as CFString, axValue)
                    }
                }
                // Last frame: snap exact and update cached positions
                if i == steps {
                    for (id, targetPos) in targets {
                        var pt = targetPos
                        if let axValue = AXValueCreate(.cgPoint, &pt),
                           let macWin = self.currentMapper?.window(withID: id) {
                            AXUIElementSetAttributeValue(macWin.windowRef, kAXPositionAttribute as CFString, axValue)
                        }
                    }
                    if var mapper = self.currentMapper {
                        mapper.updatePositions(targets)
                        self.currentMapper = mapper
                    }
                }
            }
        }
    }

    private func centerNewFloaters(newlyFloated: Set<String> = []) {
        guard let mapper = currentMapper else { return }
        let configFloaterBundleIDs = Set(tiler.config.floatingAppIDs)
        var newFloaters = mapper.allWindows
            .filter { configFloaterBundleIDs.contains($0.bundleID ?? "") && !centeredFloaterIDs.contains($0.id) }
        // Also center newly overflowed/undersized windows (but only once)
        let alreadyCentered = centeredFloaterIDs
        for win in mapper.allWindows where newlyFloated.contains(win.id) && !alreadyCentered.contains(win.id) {
            newFloaters.append(win)
        }
        newFloaters.sort { $0.id < $1.id }
        guard !newFloaters.isEmpty else { return }
        var updatedMapper = mapper
        var staggerIndex = 0
        for win in newFloaters {
            updatedMapper.centerOnScreen(id: win.id, staggerIndex: staggerIndex)
            centeredFloaterIDs.insert(win.id)
            staggerIndex += 1
        }
        currentMapper = updatedMapper
    }

    // MARK: - Destroyed notification subscription

    private func subscribeAllToDestroyed() {
        guard let mapper = currentMapper else { return }
        for win in mapper.allWindows {
            observer.subscribeToDestroyed(element: win.windowRef, forPID: win.appPID)
        }
    }

    // MARK: - Focus navigation

    /// Re-checks AX at this moment to find the truly focused window in the mapper.
    /// `mapper.focusedWindow` is stale because `isGloballyFocused` is captured at tile time.
    private func findFocusedMapperWindow(in mapper: WindowMapper) -> String? {
        guard let frontAppPID = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        let appElement = AXUIElementCreateApplication(frontAppPID)
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedRef) == .success,
              let focusedAX = focusedRef as! AXUIElement? else { return nil }
        return mapper.allWindows.first { win in
            win.appPID == frontAppPID && CFEqual(win.windowRef, focusedAX)
        }?.id
    }

    private func tilerScreenRect() -> Rect {
        guard let screen = NSScreen.main else {
            return Rect(x: 0, y: 0, width: 1920, height: 1080)
        }
        let frame = screen.frame
        let visible = screen.visibleFrame
        let topInset = frame.height - (visible.origin.y + visible.height)
        return Rect(
            x: Double(visible.origin.x),
            y: Double(topInset),
            width: Double(visible.size.width),
            height: Double(visible.size.height)
        )
    }

    func focusLeft() {
        guard let ws = currentWorkspace else { print("[focus] no workspace — tile first"); return }
        guard let mapper = currentMapper else { print("[focus] no mapper — tile first"); return }
        guard ws.focusLeft() else { print("[focus] already at leftmost"); return }
        guard let focusedID = ws.focusedWindowID else { print("[focus] no focused window"); return }
        if mapper.focusWindow(id: focusedID) {
            print("[focus] ← left")
        } else {
            print("[focus] failed to focus window")
        }
    }

    func focusRight() {
        guard let ws = currentWorkspace else { print("[focus] no workspace — tile first"); return }
        guard let mapper = currentMapper else { print("[focus] no mapper — tile first"); return }
        guard ws.focusRight() else { print("[focus] already at rightmost"); return }
        guard let focusedID = ws.focusedWindowID else { print("[focus] no focused window"); return }
        if mapper.focusWindow(id: focusedID) {
            print("[focus] → right")
        } else {
            print("[focus] failed to focus window")
        }
    }

    func focusUp() {
        guard let ws = currentWorkspace else { print("[focus] no workspace — tile first"); return }
        guard let mapper = currentMapper else { print("[focus] no mapper — tile first"); return }
        guard ws.focusUp() else { print("[focus] already at topmost"); return }
        guard let focusedID = ws.focusedWindowID else { print("[focus] no focused window"); return }
        if mapper.focusWindow(id: focusedID) {
            print("[focus] ↑ up")
        } else {
            print("[focus] failed to focus window")
        }
    }

    func focusDown() {
        guard let ws = currentWorkspace else { print("[focus] no workspace — tile first"); return }
        guard let mapper = currentMapper else { print("[focus] no mapper — tile first"); return }
        guard ws.focusDown() else { print("[focus] already at bottommost"); return }
        guard let focusedID = ws.focusedWindowID else { print("[focus] no focused window"); return }
        if mapper.focusWindow(id: focusedID) {
            print("[focus] ↓ down")
        } else {
            print("[focus] failed to focus window")
        }
    }

    func removeFocused() {
        guard let ws = currentWorkspace else { print("[remove] no workspace — tile first"); return }
        guard var mapper = currentMapper else { print("[remove] no mapper — tile first"); return }
        guard let focusedID = ws.focusedWindowID else { print("[remove] no focused window"); return }
        print("[remove] removing \(focusedID)")
        observer.isSuppressed = true
        ws.removeWindow(id: focusedID)
        let layout = ws.getLayout()
        if layout.isEmpty {
            print("[remove] no windows left")
            currentWorkspace = nil
            currentMapper = nil
        } else {
            let screenRect = tilerScreenRect()
            mapper.applyLayout(layout, screenRect: screenRect)
            currentMapper = mapper
        }
        observer.isSuppressed = false
    }

    func toggleFullscreen() {
        guard let ws = currentWorkspace else { print("[fullscreen] no workspace — tile first"); return }
        guard var mapper = currentMapper else { print("[fullscreen] no mapper — tile first"); return }

        // Exit fullscreen
        if let fsID = fullscreenWindowID {
            fullscreenWindowID = nil
            let stillExists = ws.getLayout().contains { $0.0.id == fsID }
            if stillExists {
                print("[fullscreen] exiting — restoring tile position")
                observer.isSuppressed = true
                let screenRect = tilerScreenRect()
                mapper.applyLayout(ws.getLayout(), screenRect: screenRect)
                currentMapper = mapper
                observer.isSuppressed = false
                return
            }
            print("[fullscreen] stale fullscreen window gone — entering fresh")
        }

        // Enter fullscreen
        guard let focusedID = findFocusedMapperWindow(in: mapper) else { print("[fullscreen] no focused window"); return }
        guard mapper.window(withID: focusedID) != nil else { print("[fullscreen] focused window not in mapper"); return }

        let sr = tilerScreenRect()
        mapper.setWindowFrame(id: focusedID, position: CGPoint(x: sr.x, y: sr.y), size: CGSize(width: sr.width, height: sr.height))
        currentMapper = mapper
        fullscreenWindowID = focusedID
        print("[fullscreen] ✓ \(focusedID)")
    }

    // MARK: - Permissions

    private func checkPermissions() -> Bool {
        var ok = true

        print("Event flag values: cmd=\(CGEventFlags.maskCommand.rawValue) alt=\(CGEventFlags.maskAlternate.rawValue) shift=\(CGEventFlags.maskShift.rawValue) ctrl=\(CGEventFlags.maskControl.rawValue) nonCoalesced=\(CGEventFlags.maskNonCoalesced.rawValue) numericPad=\(CGEventFlags.maskNumericPad.rawValue)")

        if !AXIsProcessTrusted() {
            print("⚠️  Accessibility permissions required.")
            print("   Grant access: System Settings → Privacy & Security → Accessibility")
            print()
            ok = false
        }

        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        let dummyTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: CGEventTapOptions(rawValue: 0)!,
            eventsOfInterest: eventMask,
            callback: { _, type, _, _ in
                print("[dummyTap] event type: \(type.rawValue)")
                return nil
            },
            userInfo: nil
        )
        if let tap = dummyTap {
            print("Input Monitoring: granted (dummy tap created)")
            print("Tap is valid: \(CFMachPortIsValid(tap))")
            CFMachPortInvalidate(tap)
        } else {
            print("⚠️  Input Monitoring permissions required.")
            print("   Grant access: System Settings → Privacy & Security → Input Monitoring")
            print("   Add 'Terminal' (or your IDE) and make sure the checkbox is checked.")
            print()
            ok = false
        }

        return ok
    }

    // MARK: - Event tap

    private func createEventTap() -> CFMachPort? {
        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        print("Creating event tap with mask: \(eventMask)")
        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: CGEventTapOptions(rawValue: 0)!,
            eventsOfInterest: eventMask,
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        return tap
    }
}

private let eventTapCallback: CGEventTapCallBack = { proxy, type, event, userInfo in
    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    let flags = event.flags.rawValue
    let flagDesc = describeFlags(event.flags)
    print("[event] type=\(type.rawValue) keyCode=\(keyCode) rawFlags=\(flags) flags=[\(flagDesc)]")

    guard type == .keyDown else {
        return Unmanaged.passUnretained(event)
    }

    let daemon = Unmanaged<Daemon>.fromOpaque(userInfo!).takeUnretainedValue()

    for binding in daemon.bindings {
        guard binding.matches(event: event) else { continue }
        print("[event] matched action: \(binding.action)")
        switch binding.action {
        case "tile":
            CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue) {
                print("[tile] starting...")
                daemon.tileWithSuppression()
                print("[tile] done")
            }
            CFRunLoopWakeUp(CFRunLoopGetMain())
            print("[event] swallowed (tile)")
            return nil
        case "focusLeft", "focus-left":
            CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue) {
                daemon.focusLeft()
            }
            CFRunLoopWakeUp(CFRunLoopGetMain())
            return nil
        case "focusRight", "focus-right":
            CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue) {
                daemon.focusRight()
            }
            CFRunLoopWakeUp(CFRunLoopGetMain())
            return nil
        case "focusUp":
            CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue) {
                daemon.focusUp()
            }
            CFRunLoopWakeUp(CFRunLoopGetMain())
            return nil
        case "focusDown":
            CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue) {
                daemon.focusDown()
            }
            CFRunLoopWakeUp(CFRunLoopGetMain())
            return nil
        case "remove":
            CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue) {
                daemon.removeFocused()
            }
            CFRunLoopWakeUp(CFRunLoopGetMain())
            return nil
        case "fullscreen":
            CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue) {
                daemon.toggleFullscreen()
            }
            CFRunLoopWakeUp(CFRunLoopGetMain())
            return nil
        case "quit":
            print("[quit] Quitting Tessera daemon.")
            exit(0)
        default:
            break
        }
    }

    return Unmanaged.passUnretained(event)
}
