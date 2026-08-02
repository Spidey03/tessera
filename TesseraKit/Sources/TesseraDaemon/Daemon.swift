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

    /// Persistent BSP workspace state per display
    var currentWorkspaces: [CGDirectDisplayID: Workspace] = [:]
    /// Persistent window mapping per display
    var currentMappers: [CGDirectDisplayID: WindowMapper] = [:]
    /// Cooldown flag to suppress spurious re-tiles from transient windows created during resize
    private var recentlyTiled = false
    /// IDs of config-floaters already centered (never re-center on subsequent tiles)
    private var centeredFloaterIDs: Set<String> = []
    /// ID of the window currently in fullscreen mode, if any (nil = not in fullscreen)
    private var fullscreenWindowID: String? = nil
    /// Fingerprints of last known tileable windows per display (appPID + geometry) to skip no-op auto-tiles
    private var lastTileableFingerprints: [CGDirectDisplayID: Set<String>] = [:]

    init(tiler: Tiler, bindings: [KeyBinding]) {
        self.tiler = tiler
        self.bindings = bindings
        self.observer = WindowObserver(debounce: 0.05, dragDebounce: 0.25)
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
            let fingerprints = self.currentFingerprintsByDisplay()
            let changedDisplays = fingerprints.keys.filter { fingerprints[$0] != lastTileableFingerprints[$0] }
            guard !changedDisplays.isEmpty else {
                print("[auto-tile] tileable windows unchanged — skipping")
                return
            }
            lastTileableFingerprints = fingerprints
            print("[auto-tile] change on \(changedDisplays.count) display(s) — tiling")
            self.tileWithSuppression()
        }
        // Re-tile when display configuration changes (hotplug, resolution, arrangement)
        observer.onScreensChanged = { [weak self] in
            guard let self, !recentlyTiled else { return }
            print("[screens] display configuration changed — re-tiling")
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
        print("  ⌘⌥Space — toggle split direction")
        print("Listening for keyDown events...")

        CFRunLoopRun()
    }

    // MARK: - Fingerprints

    private func currentFingerprintsByDisplay() -> [CGDirectDisplayID: Set<String>] {
        var result: [CGDirectDisplayID: Set<String>] = [:]
        for w in tiler.filterWindows(WindowDiscovery.allWindows()) {
            guard let display = ScreenManager.display(containing: w.frame) else { continue }
            result[display.id, default: []].insert("\(w.appPID):\(Int(w.position.x)):\(Int(w.position.y)):\(Int(w.size.width)):\(Int(w.size.height))")
        }
        return result
    }

    // MARK: - Tiling

    /// Tile while suppressing AX notifications to avoid loops.
    /// Saves per-display workspace + mapper state for subsequent focus/remove operations.
    func tileWithSuppression() {
        observer.isSuppressed = true
        let results = tiler.tileAllWindows()

        // Update per-display state and prune displays that disappeared
        let liveIDs = Set(ScreenManager.displays.map(\.id))
        for (displayID, result) in results {
            currentWorkspaces[displayID] = result.workspace
            currentMappers[displayID] = result.mapper
        }
        currentWorkspaces = currentWorkspaces.filter { liveIDs.contains($0.key) }
        currentMappers = currentMappers.filter { liveIDs.contains($0.key) }

        for (displayID, result) in results {
            guard let mapper = currentMappers[displayID] else { continue }
            let startPositions = mapper.allWindows
                .filter { result.animationTargets.keys.contains($0.id) }
                .reduce(into: [:]) { $0[$1.id] = $1.position }
            centerNewFloaters(displayID: displayID, newlyFloated: result.newlyFloated)
            if tiler.config.animationEnabled && !result.animationTargets.isEmpty {
                animateWindows(displayID: displayID, targets: result.animationTargets, startPositions: startPositions,
                               steps: tiler.config.animationSteps,
                               duration: tiler.config.animationDuration)
            } else if !result.animationTargets.isEmpty {
                guard var instantMapper = currentMappers[displayID] else { continue }
                for (id, pos) in result.animationTargets {
                    guard let macWin = instantMapper.window(withID: id) else { continue }
                    var pt = pos
                    if let axValue = AXValueCreate(.cgPoint, &pt) {
                        AXUIElementSetAttributeValue(macWin.windowRef, kAXPositionAttribute as CFString, axValue)
                    }
                }
                instantMapper.updatePositions(result.animationTargets)
                currentMappers[displayID] = instantMapper
                print("[tile] instant placement: \(result.animationTargets.count) window(s) on display \(displayID)")
            }
        }
        observer.isSuppressed = false
        subscribeAllWindows()
        fullscreenWindowID = nil
        // Refresh fingerprint cache so subsequent auto-tiles can diff accurately
        lastTileableFingerprints = currentFingerprintsByDisplay()

        // Prevent spurious re-tiles from transient windows created during resize.
        // Must outlast animation + AX debounce interval + notification delivery window.
        let cooldown = max(0.5, tiler.config.animationDuration + 0.35)
        recentlyTiled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + cooldown) { [weak self] in
            guard let self else { return }
            self.recentlyTiled = false
            // Catch changes that happened entirely inside the cooldown (e.g. a drag
            // completed right after a tile) so they still get re-tiled.
            let fingerprints = self.currentFingerprintsByDisplay()
            let allKeys = Set(fingerprints.keys).union(self.lastTileableFingerprints.keys)
            let changed = allKeys.contains { fingerprints[$0] != self.lastTileableFingerprints[$0] }
            if changed {
                print("[auto-tile] change caught after cooldown — tiling")
                self.tileWithSuppression()
            }
        }
    }

    private func animateWindows(displayID: CGDirectDisplayID, targets: [String: CGPoint], startPositions: [String: CGPoint], steps: Int, duration: TimeInterval) {
        guard !targets.isEmpty else { return }
        let interval = duration / Double(max(steps, 1))
        print("[animate] sliding \(targets.count) windows on display \(displayID) — \(steps) steps over \(Int(duration * 1000))ms")

        for i in 1...steps {
            let t = Double(i) / Double(steps)
            let eased = t < 1 ? 1 - pow(1 - t, 2) : 1.0
            DispatchQueue.main.asyncAfter(deadline: .now() + interval * Double(i)) { [weak self] in
                guard let self else { return }
                for (id, targetPos) in targets {
                    guard let macWin = self.currentMappers[displayID]?.window(withID: id) else { continue }
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
                           let macWin = self.currentMappers[displayID]?.window(withID: id) {
                            AXUIElementSetAttributeValue(macWin.windowRef, kAXPositionAttribute as CFString, axValue)
                        }
                    }
                    if var mapper = self.currentMappers[displayID] {
                        mapper.updatePositions(targets)
                        self.currentMappers[displayID] = mapper
                    }
                    // Fingerprints were captured pre-animation; refresh now so the
                    // settled state matches and no redundant re-tile fires later.
                    self.lastTileableFingerprints = self.currentFingerprintsByDisplay()
                }
            }
        }
    }

    private func centerNewFloaters(displayID: CGDirectDisplayID, newlyFloated: Set<String> = []) {
        guard let mapper = currentMappers[displayID],
              let screenRect = ScreenManager.display(byID: displayID)?.rect else { return }
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
            updatedMapper.centerOnScreen(id: win.id, screenRect: screenRect, staggerIndex: staggerIndex)
            centeredFloaterIDs.insert(win.id)
            staggerIndex += 1
        }
        currentMappers[displayID] = updatedMapper
    }

    // MARK: - Window notification subscription

    /// Subscribe all windows to destroyed notifications; subscribe tiled windows
    /// to moved/resized so drags trigger a re-tile. Floaters only get destroyed.
    private func subscribeAllWindows() {
        for (displayID, mapper) in currentMappers {
            let tiledIDs = Set(currentWorkspaces[displayID]?.getLayout().map { $0.0.id } ?? [])
            for win in mapper.allWindows {
                observer.subscribeToDestroyed(element: win.windowRef, forPID: win.appPID)
                if tiledIDs.contains(win.id) {
                    observer.subscribeToWindow(element: win.windowRef, forPID: win.appPID)
                }
            }
        }
    }

    // MARK: - Active display resolution

    /// The display whose BSP tree contains the currently focused window.
    /// Falls back to the main display when nothing is focused.
    private func activeDisplayID() -> CGDirectDisplayID? {
        for (id, mapper) in currentMappers where findFocusedMapperWindow(in: mapper) != nil {
            return id
        }
        return ScreenManager.mainDisplayID
    }

    private func screenRect(for displayID: CGDirectDisplayID) -> Rect {
        ScreenManager.display(byID: displayID)?.rect
            ?? Rect(x: 0, y: 0, width: 1920, height: 1080)
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

    func focusLeft() {
        guard let displayID = activeDisplayID() else { print("[focus] no displays — tile first"); return }
        guard let ws = currentWorkspaces[displayID] else { print("[focus] no workspace — tile first"); return }
        guard let mapper = currentMappers[displayID] else { print("[focus] no mapper — tile first"); return }
        guard ws.focusLeft() else { print("[focus] already at leftmost"); return }
        guard let focusedID = ws.focusedWindowID else { print("[focus] no focused window"); return }
        if mapper.focusWindow(id: focusedID) {
            print("[focus] ← left")
        } else {
            print("[focus] failed to focus window")
        }
    }

    func focusRight() {
        guard let displayID = activeDisplayID() else { print("[focus] no displays — tile first"); return }
        guard let ws = currentWorkspaces[displayID] else { print("[focus] no workspace — tile first"); return }
        guard let mapper = currentMappers[displayID] else { print("[focus] no mapper — tile first"); return }
        guard ws.focusRight() else { print("[focus] already at rightmost"); return }
        guard let focusedID = ws.focusedWindowID else { print("[focus] no focused window"); return }
        if mapper.focusWindow(id: focusedID) {
            print("[focus] → right")
        } else {
            print("[focus] failed to focus window")
        }
    }

    func focusUp() {
        guard let displayID = activeDisplayID() else { print("[focus] no displays — tile first"); return }
        guard let ws = currentWorkspaces[displayID] else { print("[focus] no workspace — tile first"); return }
        guard let mapper = currentMappers[displayID] else { print("[focus] no mapper — tile first"); return }
        guard ws.focusUp() else { print("[focus] already at topmost"); return }
        guard let focusedID = ws.focusedWindowID else { print("[focus] no focused window"); return }
        if mapper.focusWindow(id: focusedID) {
            print("[focus] ↑ up")
        } else {
            print("[focus] failed to focus window")
        }
    }

    func focusDown() {
        guard let displayID = activeDisplayID() else { print("[focus] no displays — tile first"); return }
        guard let ws = currentWorkspaces[displayID] else { print("[focus] no workspace — tile first"); return }
        guard let mapper = currentMappers[displayID] else { print("[focus] no mapper — tile first"); return }
        guard ws.focusDown() else { print("[focus] already at bottommost"); return }
        guard let focusedID = ws.focusedWindowID else { print("[focus] no focused window"); return }
        if mapper.focusWindow(id: focusedID) {
            print("[focus] ↓ down")
        } else {
            print("[focus] failed to focus window")
        }
    }

    func removeFocused() {
        guard let displayID = activeDisplayID() else { print("[remove] no displays — tile first"); return }
        guard let ws = currentWorkspaces[displayID] else { print("[remove] no workspace — tile first"); return }
        guard var mapper = currentMappers[displayID] else { print("[remove] no mapper — tile first"); return }
        guard let focusedID = ws.focusedWindowID else { print("[remove] no focused window"); return }
        print("[remove] removing \(focusedID)")
        observer.isSuppressed = true
        ws.removeWindow(id: focusedID)
        let layout = ws.getLayout()
        if layout.isEmpty {
            print("[remove] no windows left")
            currentWorkspaces[displayID] = nil
            currentMappers[displayID] = nil
        } else {
            let screenRect = screenRect(for: displayID)
            mapper.applyLayout(layout, screenRect: screenRect)
            currentMappers[displayID] = mapper
        }
        observer.isSuppressed = false
    }

    func toggleSplitDirection() {
        guard let displayID = activeDisplayID() else { print("[split] no displays — tile first"); return }
        guard let ws = currentWorkspaces[displayID] else { print("[split] no workspace — tile first"); return }
        guard var mapper = currentMappers[displayID] else { print("[split] no mapper — tile first"); return }

        observer.isSuppressed = true
        guard ws.toggleSplitDirection() else {
            observer.isSuppressed = false
            print("[split] focused window has no parent split — nothing to toggle")
            return
        }
        let layout = ws.getLayout()
        let screenRect = screenRect(for: displayID)
        let startPositions = mapper.allWindows.reduce(into: [:]) { $0[$1.id] = $1.position }
        let (targets, _) = mapper.computeLayout(layout, screenRect: screenRect)
        currentMappers[displayID] = mapper

        if tiler.config.animationEnabled && !targets.isEmpty {
            animateWindows(displayID: displayID, targets: targets, startPositions: startPositions,
                           steps: tiler.config.animationSteps,
                           duration: tiler.config.animationDuration)
        } else {
            guard var instantMapper = currentMappers[displayID] else { return }
            for (id, pos) in targets {
                guard let macWin = instantMapper.window(withID: id) else { continue }
                var pt = pos
                if let axValue = AXValueCreate(.cgPoint, &pt) {
                    AXUIElementSetAttributeValue(macWin.windowRef, kAXPositionAttribute as CFString, axValue)
                }
            }
            instantMapper.updatePositions(targets)
            currentMappers[displayID] = instantMapper
            lastTileableFingerprints = currentFingerprintsByDisplay()
        }
        observer.isSuppressed = false
        fullscreenWindowID = nil
        print("[split] toggled on display \(displayID) — \(targets.count) window(s)")
    }

    func toggleFullscreen() {
        guard let displayID = activeDisplayID() else { print("[fullscreen] no displays — tile first"); return }
        guard let ws = currentWorkspaces[displayID] else { print("[fullscreen] no workspace — tile first"); return }
        guard var mapper = currentMappers[displayID] else { print("[fullscreen] no mapper — tile first"); return }

        // Exit fullscreen
        if let fsID = fullscreenWindowID {
            fullscreenWindowID = nil
            let stillExists = ws.getLayout().contains { $0.0.id == fsID }
            if stillExists {
                print("[fullscreen] exiting — restoring tile position")
                observer.isSuppressed = true
                let screenRect = screenRect(for: displayID)
                mapper.applyLayout(ws.getLayout(), screenRect: screenRect)
                currentMappers[displayID] = mapper
                observer.isSuppressed = false
                return
            }
            print("[fullscreen] stale fullscreen window gone — entering fresh")
        }

        // Enter fullscreen
        guard let focusedID = findFocusedMapperWindow(in: mapper) else { print("[fullscreen] no focused window"); return }
        guard mapper.window(withID: focusedID) != nil else { print("[fullscreen] focused window not in mapper"); return }

        let sr = screenRect(for: displayID)
        mapper.setWindowFrame(id: focusedID, position: CGPoint(x: sr.x, y: sr.y), size: CGSize(width: sr.width, height: sr.height))
        currentMappers[displayID] = mapper
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
        case "toggleSplit", "toggle-split", "toggleSplitDirection":
            CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue) {
                daemon.toggleSplitDirection()
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
