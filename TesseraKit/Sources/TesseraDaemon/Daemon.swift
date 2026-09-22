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
    var tiler: Tiler
    var bindings: [KeyBinding]
    let observer: WindowObserver

    /// Retained observer token for the DistributedNotificationCenter command channel.
    private var ipcObserver: NSObjectProtocol?
    /// Retained signal source for graceful SIGTERM handling (launchctl stop).
    private var termSignalSource: DispatchSourceSignal?

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

        _ = checkPermissions()

        if let tap = createEventTap(), CFMachPortIsValid(tap) {
            print("Event tap created successfully.")
            let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .defaultMode)
            print("Run loop source added.")
        } else {
            print("⚠️  Event tap unavailable — running WITHOUT hotkeys (IPC only).")
            print("    Grant Input Monitoring to enable hotkeys; grant Accessibility to tile windows.")
            print("    Grant in System Settings → Privacy & Security if the launchd-spawned daemon lacks them.")
        }

        installSignalHandler()
        startIPCLifecycle()

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
        print("  ⌘⌥.   — cycle layout (bsp → master-stack → columns)")
        print("Listening for keyDown events...")

        CFRunLoopRun()
    }

    // MARK: - IPC (DistributedNotificationCenter)

    /// Register a command listener, write the PID file, and announce the daemon
    /// so the TesseraMenu status item can detect it.
    private func startIPCLifecycle() {
        let nc = DistributedNotificationCenter.default()
        ipcObserver = nc.addObserver(forName: .tesseraCommand, object: nil, queue: .main) { [weak self] note in
            guard let self else { return }
            guard let action = note.userInfo?["action"] as? String else { return }
            print("[ipc] command: \(action)")
            self.handleAction(action)
        }

        let pid = ProcessInfo.processInfo.processIdentifier
        let appSupport = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Tessera")
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        try? "\(pid)".write(to: appSupport.appendingPathComponent("daemon.pid"), atomically: true, encoding: .utf8)
        nc.post(name: .tesseraDaemonDidStart, object: nil, userInfo: ["pid": pid])
        print("IPC: listening on 'TesseraDaemonCommand' (pid \(pid))")
    }

    /// Announce shutdown and remove the PID file. Called on quit or SIGTERM.
    private func stopIPCLifecycle() {
        DistributedNotificationCenter.default().post(
            name: .tesseraDaemonDidQuit,
            object: nil,
            userInfo: ["pid": ProcessInfo.processInfo.processIdentifier]
        )
        let pidFile = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Tessera/daemon.pid")
        try? FileManager.default.removeItem(at: pidFile)
    }

    /// Graceful shutdown on `launchctl stop` / SIGTERM.
    private func installSignalHandler() {
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { [weak self] in
            print("[signal] SIGTERM received — quitting")
            self?.handleAction("quit")
        }
        source.resume()
        termSignalSource = source
    }

    /// Central action dispatch. Called from the event tap (hotkeys) and from
    /// the IPC command channel. Main-thread only — tiling state lives there.
    func handleAction(_ action: String) {
        switch action {
        case "tile":
            print("[tile] starting...")
            tileWithSuppression()
            print("[tile] done")
        case "focusLeft", "focus-left":
            focusLeft()
        case "focusRight", "focus-right":
            focusRight()
        case "focusUp":
            focusUp()
        case "focusDown":
            focusDown()
        case "remove":
            removeFocused()
        case "fullscreen":
            toggleFullscreen()
        case "toggleSplit", "toggle-split", "toggleSplitDirection":
            toggleSplitDirection()
        case "cycleLayout", "cycle-layout":
            cycleLayout()
        case let action where action.hasPrefix("setLayout:"):
            setLayout(String(action.dropFirst("setLayout:".count)))
        case "reload", "reloadConfig":
            reloadConfig()
        case "quit":
            print("[quit] Quitting Tessera daemon.")
            stopIPCLifecycle()
            exit(0)
        default:
            print("[dispatch] unknown action: \(action)")
        }
    }

    /// Re-read config.json, swap the tiler + hotkey bindings, reset per-display
    /// state, and re-tile everything. Used by the menu bar app's "Reload config".
    func reloadConfig() {
        print("[reload] reloading config from disk")
        let loaded = ConfigLoader.load()
        tiler = Tiler(config: loaded.tesseraConfig)
        bindings = loaded.bindings
        currentWorkspaces = [:]
        currentMappers = [:]
        centeredFloaterIDs = []
        fullscreenWindowID = nil
        lastTileableFingerprints = [:]
        print("[reload] config reloaded — re-tiling")
        tileWithSuppression()
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
        let results = tiler.tileAllWindows(previousOrderKeys: previousLayoutOrderKeys())

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

    /// Fingerprint of each display's current layout order: for every tiled
    /// window in layout order, its `appName|title` key resolved through the
    /// last mapper. Used to preserve tile slots across re-tiles.
    private func previousLayoutOrderKeys() -> [CGDirectDisplayID: [String]] {
        var keys: [CGDirectDisplayID: [String]] = [:]
        for (displayID, workspace) in currentWorkspaces {
            guard let mapper = currentMappers[displayID] else { continue }
            keys[displayID] = workspace.getLayout().compactMap { window, _ in
                mapper.window(withID: window.id).map { "\($0.appName)|\($0.title)" }
            }
        }
        return keys
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

    // MARK: - Layout presets

    /// Cycle the layout mode (bsp → masterStack → columns → bsp) and re-tile
    /// every display with the new geometry.
    func cycleLayout() {
        tiler.layoutMode = tiler.layoutMode.next()
        print("[layout] switching to '\(tiler.layoutMode.rawValue)'")
        tileWithSuppression()
    }

    /// Switch to a specific layout mode by name ("bsp", "masterStack", "columns")
    /// and re-tile. Unknown names are rejected.
    func setLayout(_ raw: String) {
        guard let mode = LayoutMode(rawValue: raw) else {
            print("[layout] unknown layout '\(raw)' — expected bsp, masterStack or columns")
            return
        }
        tiler.layoutMode = mode
        print("[layout] switching to '\(mode.rawValue)'")
        tileWithSuppression()
    }

    func toggleSplitDirection() {
        guard tiler.layoutMode == .bsp else {
            print("[split] toggle is only supported in bsp mode (current: \(tiler.layoutMode.rawValue))")
            return
        }
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
            print("   Add 'TesseraDaemon', or your Terminal, and enable the checkbox.")
            print()
            // Pop the system prompt so the user can grant with a click.
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
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
            print("   Add 'TesseraDaemon', or your Terminal, and enable the checkbox.")
            print()
            // Ask macOS to add us to the Input Monitoring allow list (one-click prompt).
            CGRequestListenEventAccess()
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
        let action = binding.action
        CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue) {
            daemon.handleAction(action)
        }
        CFRunLoopWakeUp(CFRunLoopGetMain())
        print("[event] swallowed (\(action))")
        return nil
    }

    return Unmanaged.passUnretained(event)
}

// MARK: - IPC notification names

extension Notification.Name {
    /// Posted by TesseraMenu (or any controller) with userInfo ["action": String].
    static let tesseraCommand = Notification.Name("TesseraDaemonCommand")
    /// Posted by the daemon on successful startup. userInfo: ["pid": Int].
    static let tesseraDaemonDidStart = Notification.Name("TesseraDaemonDidStart")
    /// Posted by the daemon right before it exits (quit hotkey, quit command, SIGTERM).
    static let tesseraDaemonDidQuit = Notification.Name("TesseraDaemonDidQuit")
}
