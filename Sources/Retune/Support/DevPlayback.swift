import Foundation
import RetuneCore
import OSLog

#if DEBUG
/// Developer hook: `Retune --play <URL> [--live]` opens the player on that stream and logs playback
/// health, so rendering changes can be verified without clicking through the UI:
///   log show --last 1m --predicate 'subsystem == "io.github.0xaliraza.retune" AND category == "dev"'
@MainActor
enum DevPlayback {
    private static let log = Logger(subsystem: "io.github.0xaliraza.retune", category: "dev")

    /// `Retune --bench`: switches library sections and logs how long the main thread stays busy after each.
    static func benchIfRequested(_ model: AppModel) {
        guard CommandLine.arguments.contains("--bench") else { return }
        Task {
            let launch = ContinuousClock.now
            while model.loaded == nil { try? await Task.sleep(for: .milliseconds(20)) }
            log.notice("catalog ready \((ContinuousClock.now - launch).formatted(.units(allowed: [.milliseconds])), privacy: .public) after window appeared")
            try? await Task.sleep(for: .seconds(2))
            let order: [LibrarySection] = CommandLine.arguments.contains("--bench-loop") ? Array(repeating: [LibrarySection.live, .movies], count: 8).flatMap { $0 } : [.movies, .series, .live, .movies, .series, .live]
            for section in order {
                let start = ContinuousClock.now
                model.section = section
                let busy = await mainThreadBusyTime()
                log.notice("switch to \(section.rawValue, privacy: .public): \((ContinuousClock.now - start).formatted(.units(allowed: [.milliseconds])), privacy: .public) (busy \(busy.formatted(.units(allowed: [.milliseconds])), privacy: .public))")
                try? await Task.sleep(for: .seconds(1))
            }
            log.notice("bench done")
        }
    }

    /// Waits until the main queue answers within 20 ms (i.e. SwiftUI finished updating and laying out).
    private static func mainThreadBusyTime() async -> Duration {
        let start = ContinuousClock.now
        while true {
            let ping = ContinuousClock.now
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
            if ContinuousClock.now - ping < .milliseconds(20), ContinuousClock.now - start > .milliseconds(50) { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return ContinuousClock.now - start
    }

    static func startIfRequested(_ model: AppModel) {
        benchIfRequested(model)
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--play"), arguments.indices.contains(flag + 1) else { return }
        guard let url = URL(string: arguments[flag + 1]) else { return }
        let kind: ContentKind = arguments.contains("--live") ? .live : .movie
        model.playDirect(PlaybackItem(id: "dev", kind: kind, title: url.lastPathComponent, url: url))
        Task {
            for second in stride(from: 2, through: 8, by: 2) {
                try? await Task.sleep(for: .seconds(2))
                let engine = model.session.engine
                let stats = engine.readStats()
                log.notice("t+\(second)s position=\(engine.position, format: .fixed(precision: 2)) frame=\(engine.hasVideoFrame) fps=\(stats.outputFPS ?? 0, format: .fixed(precision: 1)) dropped=\(stats.droppedFrames) decoderDropped=\(stats.decoderDroppedFrames) error=\(engine.errorMessage ?? "none", privacy: .public)")
            }
        }
    }
}
#endif
