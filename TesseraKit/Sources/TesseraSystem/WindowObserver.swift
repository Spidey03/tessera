import AppKit
import ApplicationServices
import Foundation

public final class WindowObserver {
    private var observers: [pid_t: AXObserver] = [:]
    private let debounceInterval: TimeInterval
    private var debounceWorkItem: DispatchWorkItem?

    /// Callback fired when a debounced window change notification arrives.
    public var onChange: (() -> Void)?

    /// When true, incoming notifications are suppressed (used during our own layout)
    public var isSuppressed = false

    private let notificationNames: [String] = [
        kAXWindowCreatedNotification as String,
    ]

    public init(debounce: TimeInterval = 0.05) {
        self.debounceInterval = debounce
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
    }

    public func stop() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)

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
        guard let obs = observers[pid] else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let err = AXObserverAddNotification(obs, element, kAXUIElementDestroyedNotification as CFString, refcon)
        if err != .success && err != .notificationAlreadyRegistered {
            print("[observer] subscribeToDestroyed error: \(err.rawValue)")
        }
    }

    private func handleNotification(element: AXUIElement, notification: CFString) {
        guard !isSuppressed else { return }

        print("[observer] notification: \(notification)")

        debounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            print("[observer] debounced trigger — calling onChange")
            self.onChange?()
        }
        debounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }
}
