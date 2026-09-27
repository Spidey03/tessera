import AppKit
import Foundation

/// Live accessibility settings that window motion has to respect.
///
/// Read on every tile rather than cached at launch, so toggling a setting in
/// System Settings takes effect immediately without restarting the daemon.
public enum AccessibilityPreferences {
    /// True when the user has asked for reduced motion.
    ///
    /// For a window manager this is not a cosmetic nicety: motion that the
    /// user has explicitly asked to see less of should be skipped entirely,
    /// which is also what AppKit itself does. The daemon is not a bundled GUI
    /// app, but it does run inside a window-server session (it is spawned as a
    /// descendant of a granted terminal), so the preference is readable; if
    /// the session is unavailable we treat motion as allowed and let the
    /// animation run.
    public static var reduceMotion: Bool {
        return NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// True when the user has asked for reduced transparency. Honoured by the
    /// menu bar app's settings window, which is otherwise a vibrancy surface.
    public static var reduceTransparency: Bool {
        return NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }
}
