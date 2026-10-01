import Foundation
import LumenCore
import Observation

/// Owns the player engine, the play queue (channel list or episode run) and progress reporting.
@MainActor
@Observable
final class PlaybackSession {
    let engine = MPVPlayer()
    @ObservationIgnored private(set) lazy var videoView = MPVVideoView(player: engine)

    private(set) var queue: [PlaybackItem] = []
    private(set) var index = 0
    private(set) var epg: [EPGEntry] = []
    /// Seconds left before the next episode starts automatically; nil when no countdown is running.
    private(set) var autoplayCountdown: Int?

    /// Heading for the list panel, e.g. the category or series the queue came from.
    var queueTitle: String?

    @ObservationIgnored var onProgress: ((PlaybackItem, Double, Double) -> Void)?
    /// Saved resume point for an item, used when switching within the queue.
    @ObservationIgnored var resumePosition: ((PlaybackItem) -> Double?)?
    @ObservationIgnored var epgProvider: ((PlaybackItem) async -> [EPGEntry])?
    @ObservationIgnored private var progressTask: Task<Void, Never>?
    @ObservationIgnored private var epgTask: Task<Void, Never>?
    @ObservationIgnored private var countdownTask: Task<Void, Never>?
    @ObservationIgnored private var tuneTask: Task<Void, Never>?
    /// The channel watched before the current one, for ⌫ "last channel".
    @ObservationIgnored private var previousIndex: Int?

    /// Rapid channel changes only connect once the user pauses, so zapping stays instant and
    /// single-connection accounts aren't hammered.
    private let zapDelay: Duration = .milliseconds(350)

    init() {
        engine.onEndOfFile = { [weak self] in self?.handleEndOfFile() }
    }

    var current: PlaybackItem? { queue.indices.contains(index) ? queue[index] : nil }
    var isActive: Bool { current != nil }
    var hasNext: Bool { index + 1 < queue.count }
    var hasPrevious: Bool { index > 0 }
    var nextItem: PlaybackItem? { hasNext ? queue[index + 1] : nil }

    var nowPlaying: EPGEntry? { epg.first { $0.isLive() } }
    var upNext: EPGEntry? {
        guard let now = nowPlaying else { return epg.first { $0.start > .now } }
        return epg.first { $0.start >= now.end }
    }

    func play(_ items: [PlaybackItem], at position: Int, startAt: Double? = nil) {
        guard items.indices.contains(position) else { return }
        saveProgress()
        queue = items
        start(at: position, startAt: startAt)
        previousIndex = nil
    }

    func playNext() { step(1) }
    func playPrevious() { step(-1) }

    /// Jumps back to the previously watched channel (TV-remote "last" button).
    func playLastChannel() {
        guard current?.isLive == true, let previousIndex, queue.indices.contains(previousIndex) else { return }
        start(at: previousIndex, startAt: nil)
    }

    func jump(to item: PlaybackItem) {
        guard let target = queue.firstIndex(of: item), target != index else { return }
        saveProgress()
        start(at: target, startAt: resumePosition?(item))
    }

    func retry() {
        guard let current else { return }
        engine.load(current.url, startAt: engine.position > 0 ? engine.position : nil)
    }

    func stop() {
        saveProgress()
        cancelAutoplay()
        progressTask?.cancel()
        epgTask?.cancel()
        tuneTask?.cancel()
        engine.stop()
        queue = []
        queueTitle = nil
        epg = []
        index = 0
    }

    func cancelAutoplay() {
        countdownTask?.cancel()
        autoplayCountdown = nil
    }

    /// Live TV wraps around the channel list; on-demand queues stop at the ends.
    private func step(_ delta: Int) {
        guard !queue.isEmpty, let current else { return }
        var target = index + delta
        if current.isLive {
            target = (target + queue.count) % queue.count
        } else if !queue.indices.contains(target) {
            return
        }
        saveProgress()
        start(at: target, startAt: resumePosition?(queue[target]), debounce: true)
    }

    private func start(at position: Int, startAt: Double?, debounce: Bool = false) {
        cancelAutoplay()
        if position != index, current != nil { previousIndex = index }
        index = position
        let item = queue[position]
        tuneTask?.cancel()
        guard debounce else {
            begin(item, startAt: startAt)
            return
        }
        engine.prepareForTuning()
        epg = []
        tuneTask = Task { [weak self, zapDelay] in
            try? await Task.sleep(for: zapDelay)
            guard !Task.isCancelled else { return }
            self?.begin(item, startAt: startAt)
        }
    }

    private func begin(_ item: PlaybackItem, startAt: Double?) {
        engine.load(item.url, startAt: startAt)
        if item.isLive { onProgress?(item, 0, 0) }
        startProgressTimer()
        loadEPG(for: item)
    }

    private func handleEndOfFile() {
        guard let current, !current.isLive else { return }
        saveProgress()
        // Only a series flows on by itself; a movie ending shouldn't roll into the next title in its category.
        guard current.kind == .episode, nextItem?.kind == .episode, hasNext, PlayerPreferences.autoplayNextEpisode else { return }
        autoplayCountdown = 8
        countdownTask = Task { [weak self] in
            while let self, let remaining = self.autoplayCountdown, remaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self.autoplayCountdown = remaining - 1
            }
            guard !Task.isCancelled else { return }
            self?.playNext()
        }
    }

    private func startProgressTimer() {
        progressTask?.cancel()
        progressTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                self?.saveProgress()
            }
        }
    }

    private func saveProgress() {
        guard let current, !current.isLive, engine.duration > 0 else { return }
        onProgress?(current, engine.position, engine.duration)
    }

    private func loadEPG(for item: PlaybackItem) {
        epg = []
        epgTask?.cancel()
        guard item.isLive, let epgProvider else { return }
        epgTask = Task { [weak self] in
            let entries = await epgProvider(item)
            guard !Task.isCancelled, self?.current?.id == item.id else { return }
            self?.epg = entries
        }
    }
}
