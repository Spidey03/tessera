import Foundation

/// Decides when a tiled window that extends past the screen is auto-floated.
public enum AutoFloat {
    /// Overflow allowed before a window floats when the config omits the key.
    public static let defaultOverflowThreshold: Double = 50
    /// Accepted range for `autoFloatOverflowThreshold` (pixels).
    public static let overflowThresholdRange: ClosedRange<Double> = 0...500

    /// True when a window overflows the screen by more than `threshold` pixels.
    /// Exactly `threshold` is tolerated.
    public static func shouldAutoFloat(overflow: Double, threshold: Double) -> Bool {
        overflow > threshold
    }

    /// Resolves a raw config value. A missing, non-finite or out-of-range value
    /// falls back to `defaultOverflowThreshold`.
    public static func overflowThreshold(from raw: Double?) -> Double {
        guard let raw, raw.isFinite, overflowThresholdRange.contains(raw) else {
            return defaultOverflowThreshold
        }
        return raw
    }
}
