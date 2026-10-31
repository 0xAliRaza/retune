import Foundation

/// Persistent subtitle appearance (size, position, background), mapped onto mpv options.
public struct SubtitleStyle: Codable, Equatable, Sendable {
    /// Multiplier on the base font size.
    public var scale: Double = 1
    /// Vertical position: 100 = bottom, smaller = higher.
    public var position: Double = 100
    public var background = false
    /// Respect styling embedded in the track. Off by default: many SRT rips carry inline tags such as
    /// `<font size="80">` that mpv honours even with `force`, producing screen-filling text, so the
    /// default `strip` drops every inline tag and applies this style instead.
    public var keepsOriginalStyle = false

    public init() {}

    public static let scaleRange = 0.5...2.5
    public static let positionRange = 50.0...100.0
    private static let defaultsKey = "player.subtitleStyle"

    public var mpvOptions: [(String, String)] {
        [("sub-scale", String(scale)),
         ("sub-pos", String(position)),
         ("sub-border-style", background ? "background-box" : "outline-and-shadow"),
         ("sub-ass-override", keepsOriginalStyle ? "scale" : "strip")]
    }

    public mutating func clamp() {
        scale = min(max((scale * 10).rounded() / 10, Self.scaleRange.lowerBound), Self.scaleRange.upperBound)
        position = min(max(position.rounded(), Self.positionRange.lowerBound), Self.positionRange.upperBound)
    }

    public static func load() -> SubtitleStyle {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let style = try? JSONDecoder().decode(SubtitleStyle.self, from: data) else { return SubtitleStyle() }
        return style
    }

    public func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(self), forKey: Self.defaultsKey)
    }
}
