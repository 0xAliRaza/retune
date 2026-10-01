import Foundation

public enum VideoQuality {
    /// Marketing label for a frame size. Width matters as much as height because
    /// scope films are e.g. 1920×800 yet still "1080p".
    public static func label(width: Int, height: Int) -> String? {
        guard width > 0, height > 0 else { return nil }
        switch (width, height) {
        case let (w, h) where w >= 3200 || h >= 2000: return "4K"
        case let (w, h) where w >= 2200 || h >= 1400: return "1440p"
        case let (w, h) where w >= 1700 || h >= 1000: return "1080p"
        case let (w, h) where w >= 1200 || h >= 700: return "720p"
        default: return "SD"
        }
    }

    /// "4.2 Mbps" / "640 kbps".
    public static func bitrate(_ bitsPerSecond: Double) -> String {
        bitsPerSecond >= 1_000_000
            ? String(format: "%.1f Mbps", bitsPerSecond / 1_000_000)
            : String(format: "%.0f kbps", bitsPerSecond / 1000)
    }
}
