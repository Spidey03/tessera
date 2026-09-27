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
    /// Where per-display layout overrides are persisted (state.json).
    private let layoutStateURL: URL

    init(tiler: Tiler, bindings: [KeyBinding], layoutStateURL: URL = ConfigLoader.statePath) {
        self.tiler = tiler
        self.bindings = bindings
        self.observer = WindowObserver(debounce: 0.05, dragDebounce: 0.25)
        self.layoutStateURL = layoutStateURL
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
        print("  ⌘⌥[ / ⌘⌥] — shrink / grow focused split")
        print("  ⌘⌥.   — cycle layout on the focused display (bsp → master-stack → columns)")
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
        case "resizeGrow", "resize-grow", "resizeSplit":
            resizeSplit(delta: tiler.config.splitResizeStep)
        case "resizeShrink", "resize-shrink":
            resizeSplit(delta: -tiler.config.splitResizeStep)
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
        let layoutState = LayoutStateStore.load(from: layoutStateURL)
        tiler = Tiler(config: loaded.tesseraConfig, layoutState: layoutState)
        bindings = loaded.bindings
        currentWorkspaces = [:]
        currentMappers = [:]
        centeredFloaterIDs = []
        fullscreenWindowID = nil
        lastTileableFingerprints = [:]
        print("[reload] config reloaded — re-tiling (persisted layout overrides kept)")
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

        // Snapshot the window set *before* the tile so the trigger can be
        // inferred by diffing (see TileTriggerAnalyzer): a window appearing or
        // disappearing is what distinguishes an insert/remove from a relayout.
        //
        // Keyed on stableID, never MacWindow.id: id is the AXUIElement pointer
        // and is rebuilt on every discovery pass, so the same window would
        // change id between tiles and every relayout would look like a
        // full remove+insert.
        let previousWindowIDs = Set(currentMappers.values.flatMap { $0.allWindows.map(\.stableID) })

        let results = tiler.tileAllWindows(previousOrderKeys: previousLayoutOrderKeys(),
                                           previousSplitStates: previousSplitStatesByDisplay())

        let analysis = TileTriggerAnalyzer.analyze(
            previous: previousWindowIDs,
            current: Set(results.values.flatMap { $0.mapper.allWindows.map(\.stableID) })
        )
        if animationDebugEnabled {
            print("[animate] trigger=\(analysis.trigger.rawValue) inserted=\(analysis.inserted.count) removed=\(analysis.removed.count) animated=\(analysis.animated.count)")
        }

        // Update per-display state and prune displays that disappeared
        let liveIDs = Set(ScreenManager.displays.map(\.id))
        for (displayID, result) in results {
            currentWorkspaces[displayID] = result.workspace
            currentMappers[displayID] = result.mapper
        }
        currentWorkspaces = currentWorkspaces.filter { liveIDs.contains($0.key) }
        currentMappers = currentMappers.filter { liveIDs.contains($0.key) }

        // Persist the effective state before applying: split ratios per display
        // and absolute float frames survive re-tiles and restarts.
        persistEffectiveState(from: results, liveIDs: liveIDs)

        var animatedTargetCount = 0
        for (displayID, result) in results {
            guard let mapper = currentMappers[displayID] else { continue }
            centerNewFloaters(displayID: displayID, newlyFloated: result.newlyFloated)

            guard !result.animationTargets.isEmpty else { continue }

            // Only the windows the trigger nominates glide; everything else
            // lands this frame.
            //
            // `analysis.animated` is keyed on stableID while `animationTargets`
            // is keyed on MacWindow.id, so bridge the two identity spaces via
            // this display's windows rather than intersecting the sets
            // directly.
            let nominatedIDs = Set(result.mapper.allWindows
                .filter { analysis.animated.contains($0.stableID) }
                .map(\.id))
            animatedTargetCount += placeWindows(
                displayID: displayID,
                mapper: mapper,
                targets: result.animationTargets,
                animatedIDs: nominatedIDs
            )
        }
        if motionAllowed, animatedTargetCount == 0, analysis.trigger != .relayout, analysis.trigger != .initial {
            print("[tile] instant placement: motion disabled or nothing to glide on display")
        }
        observer.isSuppressed = false
        subscribeAllWindows()
        fullscreenWindowID = nil
        // Refresh fingerprint cache so subsequent auto-tiles can diff accurately
        lastTileableFingerprints = currentFingerprintsByDisplay()

        // Prevent spurious re-tiles from transient windows created during resize.
        // Must outlast animation + AX debounce interval + notification delivery window.
        // Must outlast the slowest window, which under a stagger is the *last*
        // one to start — using animationDuration alone would clear the cooldown
        // while the tail of the animation is still in flight.
        holdCooldown(animatedWindowCount: animatedTargetCount)
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

    /// Each display's current split ratios, so re-tiles keep surviving splits'
    /// weights (see `Workspace.captureSplitState`).
    private func previousSplitStatesByDisplay() -> [CGDirectDisplayID: [String: SplitState]] {
        currentWorkspaces.reduce(into: [:]) { result, entry in
            result[entry.key] = entry.value.captureSplitState()
        }
    }

    /// Persist per-display split ratios and absolute float frames (resolved
    /// through the fresh mappers) to state.json — but only when something
    /// actually changed, so idle re-tiles don't churn the file.
    private func persistEffectiveState(from results: [CGDirectDisplayID: DisplayTileResult], liveIDs: Set<CGDirectDisplayID>) {
        var splitStates: [String: [String: SplitState]] = [:]
        var floatRects: [String: FloatRect] = [:]
        for (displayID, result) in results {
            splitStates[String(displayID)] = result.workspace.captureSplitState()
            let mapper = currentMappers[displayID]
            for win in mapper?.allWindows ?? [] where result.floatedIDs.contains(win.id) {
                let key = floaterKey(for: win)
                let displayNumber = ScreenManager.display(containing: win.frame)?.id ?? displayID
                floatRects[key] = FloatRect(x: win.position.x, y: win.position.y,
                                            width: win.size.width, height: win.size.height,
                                            displayID: displayNumber)
            }
        }
        var state = tiler.layoutState
        state.prune(liveDisplayIDs: liveIDs)
        for (key, value) in splitStates { state.setSplitStates(value, for: UInt32(key) ?? 0) }
        state.setFloatRects(floatRects)
        guard state != tiler.layoutState else { return }
        tiler.layoutState = state
        persistLayoutState()
    }

    /// Stable identity for a floating window's saved frame.
    private func floaterKey(for win: MacWindow) -> String {
        win.stableID
    }

    /// Logged once so Reduce Motion does not print on every keystroke tile.
    private var didLogReduceMotion = false

    /// Whether windows are permitted to glide at all this tile.
    ///
    /// Reduce Motion wins over `animationEnabled`: a window manager that
    /// slides windows around regardless has not respected a user who asked for
    /// less motion. Read per tile, not cached, so toggling the setting in
    /// System Settings takes effect immediately.
    private var motionAllowed: Bool {
        guard tiler.config.animationEnabled else { return false }
        if AccessibilityPreferences.reduceMotion {
            if !didLogReduceMotion {
                didLogReduceMotion = true
                print("[animate] Reduce Motion is on - placing windows instantly")
            }
            return false
        }
        return true
    }

    private func animationTiming() -> AnimationTiming {
        return AnimationTiming(duration: tiler.config.animationDuration,
                               stagger: tiler.config.animationStagger,
                               steps: tiler.config.animationSteps)
    }

    /// Opt-in frame timing, for verifying vsync alignment without screen
    /// recording: TESSERA_ANIMATION_DEBUG=1.
    private var animationDebugEnabled: Bool {
        return ProcessInfo.processInfo.environment["TESSERA_ANIMATION_DEBUG"] == "1"
    }

    /// Places `targets` on a display: the windows in `animatedIDs` glide, the
    /// rest land this frame. Reduce Motion collapses the animated set to empty,
    /// so the whole tile becomes instant.
    ///
    /// Every animated placement goes through here — the tile funnel, and
    /// `removeFocused` — so there is a single place to change when placement
    /// starts interpolating full rects rather than origins.
    ///
    /// - Parameter animatedIDs: keyed on `MacWindow.id`, the same space as
    ///   `targets`. Callers holding stable identities must bridge first.
    /// - Returns: how many windows actually glided, for the cooldown maths.
    @discardableResult
    private func placeWindows(
        displayID: CGDirectDisplayID,
        mapper: WindowMapper,
        targets: [String: CGPoint],
        animatedIDs: Set<String>
    ) -> Int {
        guard !targets.isEmpty else { return 0 }

        let animatedTargets = motionAllowed && !animatedIDs.isEmpty
            ? targets.filter { animatedIDs.contains($0.key) }
            : [:]
        let instantTargets = targets.filter { !animatedTargets.keys.contains($0.key) }

        if !instantTargets.isEmpty {
            placeInstantly(displayID: displayID, targets: instantTargets)
        }
        guard !animatedTargets.isEmpty else { return 0 }

        let startPositions = mapper.allWindows
            .filter { animatedTargets.keys.contains($0.id) }
            .reduce(into: [String: CGPoint]()) { $0[$1.id] = $1.position }
        animateWindows(displayID: displayID, targets: animatedTargets, startPositions: startPositions,
                       curve: tiler.config.animationCurve,
                       timing: animationTiming())
        return animatedTargets.count
    }

    /// Put windows at their target origins within one frame and sync the cached
    /// positions. Used for every window the trigger did not nominate to glide,
    /// and for all of them when motion is off.
    private func placeInstantly(displayID: CGDirectDisplayID, targets: [String: CGPoint]) {
        guard !targets.isEmpty, var mapper = currentMappers[displayID] else { return }
        for (id, pos) in targets {
            guard let macWin = mapper.window(withID: id) else { continue }
            var pt = pos
            if let axValue = AXValueCreate(.cgPoint, &pt) {
                AXUIElementSetAttributeValue(macWin.windowRef, kAXPositionAttribute as CFString, axValue)
            }
        }
        mapper.updatePositions(targets)
        currentMappers[displayID] = mapper
    }

    /// Glide the nominated windows to their targets.
    ///
    /// Each window gets its own step schedule offset by `timing.stagger`, so a
    /// stagger is a delay cascade rather than a slower shared clock. The curve
    /// is sampled uniformly in time and evaluated per step.
    private func animateWindows(displayID: CGDirectDisplayID,
                                targets: [String: CGPoint],
                                startPositions: [String: CGPoint],
                                curve: AnimationCurve,
                                timing: AnimationTiming) {
        guard !targets.isEmpty else { return }
        let interval = timing.duration / Double(timing.steps)
        // Deterministic order, so the stagger does not reshuffle between runs
        // the way Dictionary key order would.
        let orderedIDs = targets.keys.sorted()
        print("[animate] sliding \(targets.count) window(s) on display \(displayID) - \(curve.rawValue), \(timing.steps) steps over \(Int(timing.duration * 1000))ms, stagger \(Int(timing.stagger * 1000))ms")

        var lastScheduled: TimeInterval = 0
        for (index, id) in orderedIDs.enumerated() {
            guard let targetPos = targets[id] else { continue }
            let startPos = startPositions[id] ?? targetPos
            let startOffset = timing.startOffset(index: index)

            for i in 1...timing.steps {
                let eased = curve.value(at: Double(i) / Double(timing.steps))
                let delay = startOffset + interval * Double(i)
                lastScheduled = max(lastScheduled, delay)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self, let macWin = self.currentMappers[displayID]?.window(withID: id) else { return }
                    var pt = CGPoint(x: startPos.x + (targetPos.x - startPos.x) * eased,
                                     y: startPos.y + (targetPos.y - startPos.y) * eased)
                    if let axValue = AXValueCreate(.cgPoint, &pt) {
                        AXUIElementSetAttributeValue(macWin.windowRef, kAXPositionAttribute as CFString, axValue)
                    }
                }
            }
        }

        // One finalisation for the whole animation, at the moment the *last*
        // window lands (which under a stagger is not the longest window but
        // the latest-starting one): snap exact targets, sync the mapper cache,
        // and refresh fingerprints so a settled tile does not immediately
        // re-tile itself.
        let settle = max(lastScheduled, timing.settleTime(windowCount: orderedIDs.count))
        DispatchQueue.main.asyncAfter(deadline: .now() + settle) { [weak self] in
            guard let self else { return }
            self.placeInstantly(displayID: displayID, targets: targets)
            self.lastTileableFingerprints = self.currentFingerprintsByDisplay()
        }
        if animationDebugEnabled {
            print("[animate] settle at \(Int(settle * 1000))ms for \(targets.count) window(s), interval \(Int(interval * 1000))ms")
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
            if let savedRect = restorableFloatRect(for: win) {
                updatedMapper.place(id: win.id, rect: savedRect)
            } else {
                updatedMapper.centerOnScreen(id: win.id, screenRect: screenRect, staggerIndex: staggerIndex)
                staggerIndex += 1
            }
            centeredFloaterIDs.insert(win.id)
        }
        currentMappers[displayID] = updatedMapper
    }

    /// The saved float frame for `win`, if it still lands on a live display.
    /// Restoring a stored position is what lets floaters reappear where the
    /// user left them after a restart; anything off-screen (monitor changed)
    /// falls through to the default center-on-screen behavior.
    private func restorableFloatRect(for win: MacWindow) -> Rect? {
        guard let saved = tiler.layoutState.floatRect(for: floaterKey(for: win)) else { return nil }
        let slack: Double = 2
        let insideAny = ScreenManager.displays.contains { display in
            let r = display.rect
            return saved.x >= r.x - slack && saved.y >= r.y - slack
                && saved.x + saved.width <= r.x + r.width + slack
                && saved.y + saved.height <= r.y + r.height + slack
        }
        return insideAny ? saved.rect : nil
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

    /// Drop the focused window out of the tiling layout and glide the survivors
    /// into the space it left behind.
    ///
    /// This is a removal, so under the hybrid policy every survivor animates —
    /// unlike the tile funnel, which only glides windows that just appeared.
    /// The excluded window is deliberately left exactly where it was; it simply
    /// stops being managed, and survivors move around it.
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
            // computeLayout, not applyLayout: survivors get *larger* tiles here,
            // so their sizes must be recomputed. It returns target origins
            // without moving anything, which is what lets them glide.
            let (targets, floatedIDs) = mapper.computeLayout(layout, screenRect: screenRect)
            currentMappers[displayID] = mapper
            centerNewFloaters(displayID: displayID, newlyFloated: floatedIDs)

            let glided = placeWindows(
                displayID: displayID,
                mapper: mapper,
                targets: targets,
                animatedIDs: Set(targets.keys)
            )
            // The glide itself moves windows, and those moves reach the AX
            // observer. Hold the same cooldown the funnel uses so the observer
            // cannot start a second tile on top of this one mid-flight.
            holdCooldown(animatedWindowCount: glided)
        }
        observer.isSuppressed = false
    }

    /// Suppress observer-driven auto-tiles for the length of an animation plus
    /// the AX debounce window, then re-check once for changes that landed inside
    /// it.
    private func holdCooldown(animatedWindowCount: Int) {
        let cooldown = animationTiming().cooldownTime(windowCount: animatedWindowCount)
        recentlyTiled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + cooldown) { [weak self] in
            guard let self else { return }
            self.recentlyTiled = false
            let fingerprints = self.currentFingerprintsByDisplay()
            let allKeys = Set(fingerprints.keys).union(self.lastTileableFingerprints.keys)
            let changed = allKeys.contains { fingerprints[$0] != self.lastTileableFingerprints[$0] }
            if changed {
                print("[auto-tile] change caught after cooldown — tiling")
                self.tileWithSuppression()
            }
        }
    }

    // MARK: - Layout presets

    /// Cycle the layout mode of the ACTIVE display (bsp → masterStack →
    /// columns → bsp), persist the override, and re-tile every display with
    /// the new geometry. Other displays keep their own mode.
    func cycleLayout() {
        guard let displayID = activeDisplayID() else { print("[layout] no displays — tile first"); return }
        let next = tiler.layoutMode(for: displayID).next()
        tiler.layoutState.setMode(next, for: displayID)
        persistLayoutState()
        print("[layout] display \(displayID): switching to '\(next.rawValue)'")
        tileWithSuppression()
    }

    /// Switch the ACTIVE display to a specific layout mode by name
    /// ("bsp", "masterStack", "columns") and re-tile. Unknown names are
    /// rejected; the override persists for the next run.
    func setLayout(_ raw: String) {
        guard let mode = LayoutMode(rawValue: raw) else {
            print("[layout] unknown layout '\(raw)' — expected bsp, masterStack or columns")
            return
        }
        guard let displayID = activeDisplayID() else { print("[layout] no displays — tile first"); return }
        tiler.layoutState.setMode(mode, for: displayID)
        persistLayoutState()
        print("[layout] display \(displayID): switching to '\(mode.rawValue)'")
        tileWithSuppression()
    }

    /// Write the current per-display overrides to state.json (pruned of
    /// displays that are no longer connected), so layouts survive restarts.
    private func persistLayoutState() {
        var state = tiler.layoutState
        state.prune(liveDisplayIDs: Set(ScreenManager.displays.map(\.id)))
        do {
            try LayoutStateStore.save(state, to: layoutStateURL)
            print("[layout] state persisted to \(layoutStateURL.path)")
        } catch {
            print("[layout] WARNING: failed to save layout state: \(error)")
        }
    }

    func toggleSplitDirection() {
        guard let displayID = activeDisplayID() else { print("[split] no displays — tile first"); return }
        guard tiler.layoutMode(for: displayID) == .bsp else {
            print("[split] toggle is only supported in bsp mode (current: \(tiler.layoutMode(for: displayID).rawValue))")
            return
        }
        guard let ws = currentWorkspaces[displayID] else { print("[split] no workspace — tile first"); return }
        guard var mapper = currentMappers[displayID] else { print("[split] no mapper — tile first"); return }

        observer.isSuppressed = true
        guard ws.toggleSplitDirection() else {
            observer.isSuppressed = false
            print("[split] focused window has no parent split — nothing to toggle")
            return
        }
        applyTreeChange(displayID: displayID)
        print("[split] toggled on display \(displayID)")
    }

    /// Nudge the focused split ratio. Positive `delta` grows the focused
    /// window's share (see `Workspace.resizeSplit`). Mirrors the toggle path.
    func resizeSplit(delta: Double) {
        guard let displayID = activeDisplayID() else { print("[split] no displays — tile first"); return }
        guard tiler.layoutMode(for: displayID) == .bsp else {
            print("[split] resize is only supported in bsp mode (current: \(tiler.layoutMode(for: displayID).rawValue))")
            return
        }
        guard let ws = currentWorkspaces[displayID] else { print("[split] no workspace — tile first"); return }
        guard currentMappers[displayID] != nil else { print("[split] no mapper — tile first"); return }

        observer.isSuppressed = true
        guard ws.resizeSplit(delta: delta) else {
            observer.isSuppressed = false
            print("[split] focused window has no parent split — nothing to resize")
            return
        }
        applyTreeChange(displayID: displayID)
        print("[split] resized split by \(delta) on display \(displayID)")
    }

    /// After a workspace tree mutation, recompute the layout and animate (or
    /// instantly apply) the windows. Expects `observer.isSuppressed` to be
    /// true already; resets it afterward.
    private func applyTreeChange(displayID: CGDirectDisplayID) {
        guard let ws = currentWorkspaces[displayID] else {
            observer.isSuppressed = false
            return
        }
        guard var mapper = currentMappers[displayID] else {
            observer.isSuppressed = false
            return
        }

        let layout = ws.getLayout()
        let screenRect = screenRect(for: displayID)
        let (targets, _) = mapper.computeLayout(layout, screenRect: screenRect)
        currentMappers[displayID] = mapper

        // A tree mutation (split toggle, split resize) is a relayout: the same
        // windows land on different tiles, so the hybrid policy places them
        // instantly instead of gliding. That is also where an AX-driven
        // animation reads worst, because every pane resizes at once.
        placeInstantly(displayID: displayID, targets: targets)
        lastTileableFingerprints = currentFingerprintsByDisplay()
        observer.isSuppressed = false
        fullscreenWindowID = nil
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
