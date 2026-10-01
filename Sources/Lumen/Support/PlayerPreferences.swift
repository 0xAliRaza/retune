import Foundation

/// User-facing playback preferences, stored in UserDefaults and edited in Settings.
enum PlayerPreferences {
    enum LiveFormat: String, CaseIterable, Identifiable {
        case automatic, ts, hls

        var id: String { rawValue }

        var title: String {
            switch self {
            case .automatic: "Automatic"
            case .ts: "MPEG-TS (lower latency)"
            case .hls: "HLS (more resilient)"
            }
        }

        /// The stream extension to request, honouring what the account allows.
        func resolve(allowed: [String]) -> String {
            switch self {
            case .ts: "ts"
            case .hls: "m3u8"
            case .automatic: allowed.isEmpty || allowed.contains("ts") ? "ts" : "m3u8"
            }
        }
    }

    static let liveFormatKey = "player.liveFormat"
    static let autoplayKey = "player.autoplayNext"

    static var liveFormat: LiveFormat {
        LiveFormat(rawValue: UserDefaults.standard.string(forKey: liveFormatKey) ?? "") ?? .automatic
    }

    static var autoplayNextEpisode: Bool {
        UserDefaults.standard.object(forKey: autoplayKey) as? Bool ?? true
    }
}
