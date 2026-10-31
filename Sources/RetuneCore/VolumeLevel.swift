import Foundation

/// The player's volume scale: whole percentages up to the source's own loudness, never amplified.
public enum VolumeLevel {
    public static let maximum = 100.0
    public static let keyStep = 5.0

    public static func clamped(_ volume: Double) -> Double {
        min(max(volume.rounded(), 0), maximum)
    }

    /// Moves to the next multiple of `keyStep`, so a level left between steps by the slider lines up again.
    public static func stepped(_ volume: Double, up: Bool) -> Double {
        let steps = volume / keyStep
        return clamped((up ? steps.rounded(.down) + 1 : steps.rounded(.up) - 1) * keyStep)
    }

    public static func percent(_ volume: Double) -> String {
        "\(Int(volume.rounded()))%"
    }
}
