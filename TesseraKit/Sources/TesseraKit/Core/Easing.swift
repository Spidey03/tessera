import Foundation

/// Interpolation curves for window motion.
///
/// Pure math with no OS dependencies, so it belongs in the Brain layer and is
/// unit-testable without a display server (see the "Brain vs Body" notes in
/// the README). The daemon only decides *when* to sample; the shape of the
/// motion lives here.
///
/// Every curve satisfies `value(at: 0) == 0` and `value(at: 1) == 1`, and every
/// curve is monotonic — a window never overshoots its tile, because
/// overshoot would push it into a neighbour's space for a few frames.
public enum AnimationCurve: String, CaseIterable, Sendable {
    /// Quadratic ease-out. Tessera's historical curve, kept as the default so
    /// existing configs keep their current feel.
    case easeOutQuad
    /// Cubic ease-out — the snappier of the two, and the closest match to how
    /// AppKit decelerates a window move.
    case easeOut
    /// Symmetric accelerate-then-decelerate, for layout changes that want to
    /// read as a deliberate reposition rather than a flick.
    case easeInEaseOut
    case linear
    /// Critically damped spring. No overshoot (that is the point of *critical*
    /// damping), but it carries momentum into the target — the settle is
    /// slower than `easeOut` at the same duration.
    case spring

    /// The historical default. Changing this would silently alter the motion
    /// for every existing install, so it stays put.
    public static let `default` = AnimationCurve.easeOutQuad

    /// Steady-state used for the critically damped spring. Higher = snappier
    /// approach with a longer tail. 6.0 lands roughly 98% of the way in 0.3 s.
    private static let springDamping = 6.0

    /// Tolerant parser: an unknown or misspelled value in `config.json` falls
    /// back to the default rather than silently disabling motion.
    public init(configValue: String) {
        let trimmed = configValue.trimmingCharacters(in: .whitespaces)
        if let exact = AnimationCurve(rawValue: trimmed) {
            self = exact
            return
        }
        // Case-insensitive fallback: config.json is hand-edited, so "easeout",
        // "EaseOut" and "easeOut" should all land on the same curve. Comparing
        // a lowercased input against camelCase rawValues would not match.
        let lowered = trimmed.lowercased()
        self = AnimationCurve.allCases.first { $0.rawValue.lowercased() == lowered } ?? .default
    }

    /// Label for the settings UI popup.
    public var displayName: String {
        switch self {
        case .easeOutQuad: return "Ease Out (Quadratic)"
        case .easeOut: return "Ease Out (Cubic)"
        case .easeInEaseOut: return "Ease In Ease Out"
        case .linear: return "Linear"
        case .spring: return "Spring"
        }
    }

    /// Interpolated progress for a linear time fraction. `t` is clamped, so
    /// callers cannot ask for out-of-range progress.
    public func value(at t: Double) -> Double {
        let x = min(max(t, 0), 1)
        switch self {
        case .linear:
            return x
        case .easeOutQuad:
            let inv = 1 - x
            return 1 - inv * inv
        case .easeOut:
            let inv = 1 - x
            return 1 - inv * inv * inv
        case .easeInEaseOut:
            if x < 0.5 {
                return 2 * x * x
            }
            let inv = -2 * x + 2
            return 1 - inv * inv / 2
        case .spring:
            return Self.springValue(at: x)
        }
    }

    /// Critically damped step response, normalised so it lands exactly on 1.
    ///
    /// The raw response `1 - (1 + a·t)·e^(-a·t)` is still ~98% complete at
    /// t = 1, so it is divided by its own value at 1. The derivative of
    /// `(1 + a·t)·e^(-a·t)` is `-a²·t·e^(-a·t) ≤ 0` for t ≥ 0, i.e. the raw
    /// response increases monotonically — normalisation preserves that, so
    /// the spring eases in without ever passing the target.
    private static func springValue(at t: Double) -> Double {
        let a = springDamping
        func response(_ x: Double) -> Double {
            return 1 - (1 + a * x) * exp(-a * x)
        }
        let settled = response(1)
        guard settled > 0 else { return t }
        return response(t) / settled
    }
}

/// Timing for a single tile's motion: how long one window takes, and how far
/// each window after the first is delayed.
public struct AnimationTiming: Equatable, Sendable {
    /// Seconds one window spends travelling from its start frame to its tile.
    public let duration: TimeInterval
    /// Seconds of delay added per window index, producing a stagger.
    public let stagger: TimeInterval
    /// Number of discrete samples the daemon takes per window.
    public let steps: Int

    public init(duration: TimeInterval, stagger: TimeInterval = 0, steps: Int = 8) {
        self.duration = max(0, duration)
        self.stagger = max(0, stagger)
        self.steps = max(1, steps)
    }

    /// Delay before window `index` starts moving.
    public func startOffset(index: Int) -> TimeInterval {
        return stagger * TimeInterval(max(0, index))
    }

    /// When the last window comes to rest. The daemon's re-tile cooldown is
    /// derived from this — forgetting the stagger term means a staggered tile
    /// is still in flight when the next one starts, which is exactly the
    /// backwards-jump this is meant to avoid.
    public func settleTime(windowCount: Int) -> TimeInterval {
        return duration + startOffset(index: max(0, windowCount - 1))
    }

    /// Slack added on top of `settleTime` to cover the AX debounce interval and
    /// the window in which notification delivery is still in flight.
    public static let cooldownAllowance: TimeInterval = 0.35

    /// How long to suppress observer-driven auto-tiles after placing windows.
    ///
    /// Must outlast the slowest window's arrival, not the fastest: the moves an
    /// animation makes reach the AX observer like any other window move, so
    /// clearing this early would start a second tile on top of the first.
    /// Floored at half a second so instant placements still coalesce bursts of
    /// noise into a single follow-up tile.
    public func cooldownTime(windowCount: Int) -> TimeInterval {
        return max(0.5, settleTime(windowCount: windowCount) + Self.cooldownAllowance)
    }
}
