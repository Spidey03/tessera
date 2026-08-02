import AppKit
import ApplicationServices
import Foundation

public final class WindowObserver {
    private var observers: [pid_t: AXObserver] = [:]
    private let debounceInterval: TimeInterval
    private let dragDebounceInterval: TimeInterval
    private var debounceWorkItem: DispatchWorkItem?

    /// Callback fired when a debounced window change notification arrives.
    public var onChange: (() -> Void)?

    /// Callback fired when the display configuration changes (hotplug, resolution, arrangement).
    public var onScreensChanged: (() -> Void)?

    /// When true, incoming notifications are suppressed (used during our own layout)
    public var isSuppressed = false

    private let notificationNames: [String] = [
        kAXWindowCreatedNotification as String,
    ]

    private let windowNotificationNames: [String] = [
        kAXMovedNotification as String,
        kAXResizedNotification as String,
        kAXUIElementDestroyedNotification as String,
    ]

    public init(debounce: TimeInterval = 0.05, dragDebounce: TimeInterval = 0.25) {
        self.debounceInterval = debounce
        self.dragDebounceInterval = dragDebounce
    }

    deinit {
        stop()
    }

    public func start() {
        registerAllApps()

        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(appLaunched(_:)),
                       name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        nc.addObserver(self, selector: #selector(appTerminated(_:)),
                       name: NSWorkspace.didTerminateApplicationNotification, object: nil)

        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged(_:)),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    public func stop() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)

        for (_, observer) in observers {
            let source = AXObserverGetRunLoopSource(observer)
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .defaultMode)
        }
        observers.removeAll()
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
    }

    // MARK: - App lifecycle

    @objc private func appLaunched(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.activationPolicy == .regular else { return }
        register(app: app)
    }

    @objc private func appTerminated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        let pid = app.processIdentifier
        if let observer = observers.removeValue(forKey: pid) {
            let source = AXObserverGetRunLoopSource(observer)
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .defaultMode)
        }
    }

    @objc private func screensChanged(_ note: Notification) {
        guard !isSuppressed else { return }
        print("[observer] screen parameters changed")
        onScreensChanged?()
    }

    // MARK: - Registration

    private func registerAllApps() {
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
        for app in apps {
            register(app: app)
        }
    }

    private func register(app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard observers[pid] == nil else { return }

        var observer: AXObserver?
        let createErr = AXObserverCreate(pid, { obs, element, notification, refcon in
            let selfPtr = Unmanaged<WindowObserver>.fromOpaque(refcon!).takeUnretainedValue()
            selfPtr.handleNotification(element: element, notification: notification)
        }, &observer)

        guard createErr == .success, let obs = observer else {
            print("[observer] AXObserverCreate failed for \(app.localizedName ?? "?"): \(createErr.rawValue)")
            return
        }

        let source = AXObserverGetRunLoopSource(obs)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .defaultMode)

        let appElement = AXUIElementCreateApplication(pid)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        for name in notificationNames {
            let addErr = AXObserverAddNotification(obs, appElement, name as CFString, selfPtr)
            if addErr != .success {
                print("[observer] \(app.localizedName ?? "?"): can't observe \(name): \(addErr.rawValue)")
            }
        }

        observers[pid] = obs
        print("[observer] registered \(app.localizedName ?? "?") (PID \(pid))")
    }

    // MARK: - Handling

    public func subscribeToDestroyed(element: AXUIElement, forPID pid: pid_t) {
        subscribe(element: element, forPID: pid, names: [kAXUIElementDestroyedNotification as String])
    }

    /// Subscribe a window element to move/resize/destroyed notifications so
    /// dragging or resizing it triggers a re-tile.
    public func subscribeToWindow(element: AXUIElement, forPID pid: pid_t) {
        subscribe(element: element, forPID: pid, names: windowNotificationNames)
    }

    private func subscribe(element: AXUIElement, forPID pid: pid_t, names: [String]) {
        guard let obs = observers[pid] else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in names {
            let err = AXObserverAddNotification(obs, element, name as CFString, refcon)
            if err != .success && err != .notificationAlreadyRegistered {
                print("[observer] subscribe error for \(name): \(err.rawValue)")
            }
        }
    }

    private func handleNotification(element: AXUIElement, notification: CFString) {
        guard !isSuppressed else { return }

        print("[observer] notification: \(notification)")

        // Drags fire move/resize events continuously — use a longer debounce so
        // the window settles before re-tiling. Create/destroy stay fast.
        let name = notification as String
        let interval: TimeInterval = (name == kAXMovedNotification || name == kAXResizedNotification)
            ? dragDebounceInterval : debounceInterval

        debounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            print("[observer] debounced trigger — calling onChange")
            self.onChange?()
        }
        debounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: workItem)
    }
}
