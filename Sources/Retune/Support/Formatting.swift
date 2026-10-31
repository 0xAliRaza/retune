import Foundation
import RetuneCore
import SwiftUI

enum Format {
    /// 1:02:03 or 4:05.
    static func clock(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = wholeSeconds(seconds)
        let hours = total / 3600, minutes = (total % 3600) / 60, secs = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs) : String(format: "%d:%02d", minutes, secs)
    }

    /// "1h 42m" / "45m".
    static func runtime(_ seconds: Int) -> String {
        let hours = seconds / 3600, minutes = (seconds % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(max(minutes, 1))m"
    }

    static func remaining(_ seconds: Double) -> String {
        "\(runtime(wholeSeconds(seconds))) left"
    }

    /// `Int(Double)` traps past Int.max, and media files can report any duration they like.
    private static func wholeSeconds(_ seconds: Double) -> Int {
        guard seconds.isFinite else { return 0 }
        return Int(min(max(seconds, 0), LibraryState.maxPlausibleDuration).rounded(.down))
    }

    static func rating(_ value: Double) -> String { String(format: "%.1f", value) }

    static func time(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }

    static func timeRange(_ start: Date, _ end: Date) -> String { "\(time(start)) – \(time(end))" }
}

/// Consistent placeholder for missing artwork: a soft gradient with the title's initials.
struct ArtworkPlaceholder: View {
    let title: String
    var symbol: String?

    var body: some View {
        ZStack {
            LinearGradient(colors: Self.palette(for: title), startPoint: .topLeading, endPoint: .bottomTrailing)
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
            } else {
                Text(initials)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
    }

    private var initials: String {
        let words = title.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).prefix(2)
        return words.compactMap(\.first).map(String.init).joined().uppercased()
    }

    private static func palette(for title: String) -> [Color] {
        // Stable across launches (String.hashValue is seeded per process).
        let seed = title.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        let hue = Double(seed % 360) / 360
        return [Color(hue: hue, saturation: 0.45, brightness: 0.45), Color(hue: (hue + 0.08).truncatingRemainder(dividingBy: 1), saturation: 0.55, brightness: 0.28)]
    }
}

extension View {
    /// Liquid Glass on macOS 26, regular material elsewhere.
    @ViewBuilder
    func glassPanel(cornerRadius: CGFloat = 14) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            background(.regularMaterial, in: .rect(cornerRadius: cornerRadius))
        }
    }
}
