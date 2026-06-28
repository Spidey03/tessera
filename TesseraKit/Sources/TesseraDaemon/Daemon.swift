import ApplicationServices
import CoreGraphics
import Foundation
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

final class Daemon {
    let tiler: Tiler
    let bindings: [KeyBinding]
    let observer: WindowObserver

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
            guard let self else { return }
            print("[auto-tile] window change detected — tiling")
            self.tileWithSuppression()
        }
        observer.start()
        print("AX observer started.")

        print()
        print("Tessera daemon running. Press ⌘⌥⏎ to tile, ⌘⌥⇧Q to quit.")
        print("Listening for keyDown events...")

        CFRunLoopRun()
    }

    /// Tile while suppressing AX notifications to avoid loops
    func tileWithSuppression() {
        observer.isSuppressed = true
        tiler.tileAllWindows()
        observer.isSuppressed = false
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
        case "quit":
            print("[quit] Quitting Tessera daemon.")
            exit(0)
        default:
            break
        }
    }

    return Unmanaged.passUnretained(event)
}
