import AppKit
import Foundation
import RetuneCore
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
    /// Automatic reconnects used for the current item (0 = first try); shown on the tuning card.
    private(set) var reconnectAttempt = 0
    /// Where the current file last stopped short of its length, so a retry has to get further.
    @ObservationIgnored private var earlyEndPosition: Double?

    /// Seconds left before the next episode starts automatically; nil when no countdown is running.
    private(set) var autoplayCountdown: Int?

    /// Heading for the list panel, e.g. the category or series the queue came from.
    var queueTitle: String?

    /// (item, position, duration, isFinal): final saves happen on stop, switch and end of file.
    @ObservationIgnored var onProgress: ((PlaybackItem, Double, Double, Bool) -> Void)?
    /// Saved resume point for an item, used when switching within the queue.
    @ObservationIgnored var resumePosition: ((PlaybackItem) -> Double?)?
    @ObservationIgnored var epgProvider: ((PlaybackItem) async -> [EPGEntry])?
    @ObservationIgnored private var progressTask: Task<Void, Never>?
    @ObservationIgnored private var epgTask: Task<Void, Never>?
    @ObservationIgnored private var countdownTask: Task<Void, Never>?
    @ObservationIgnored private var tuneTask: Task<Void, Never>?
    /// The channel watched before the current one, for ⌫ "last channel".
    @ObservationIgnored private var previousIndex: Int?
    /// Where the current load was asked to start; the engine's position means nothing until a frame shows.
    @ObservationIgnored private var requestedStart: Double?

    /// Rapid channel changes only connect once the user pauses, so zapping stays instant and
    /// single-connection accounts aren't hammered.
    private let zapDelay: Duration = .milliseconds(350)

    init() {
        engine.onEndOfFile = { [weak self] in self?.handleEndOfFile() }
        // Replaying or seeking back from the end must not let the countdown fire anyway.
        engine.onLeftEnd = { [weak self] in self?.cancelAutoplay() }
        engine.onError = { [weak self] message in self?.handleFailure(message) }
        engine.onPlaybackStarted = { [weak self] in self?.reconnectAttempt = 0 }
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

    /// Saves the frame on screen to the Desktop, and reports whether a file was written.
    func saveScreenshot(completion: @escaping @MainActor (Bool) -> Void) {
        guard engine.hasVideoFrame else { return completion(false) }
        let url = ScreenshotFile.url(in: FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0])
        let layer = videoView.videoLayer
        layer.captureFrame { image in
            DispatchQueue.global(qos: .userInitiated).async {
                let saved = image.flatMap { Self.writePNG($0, to: url) } ?? false
                Task { @MainActor in completion(saved) }
            }
        }
        // A window that can't draw never delivers a frame, so don't wait for one forever.
        Task {
            try? await Task.sleep(for: .seconds(2))
            if layer.cancelCapture() { completion(false) }
        }
    }

    private nonisolated static func writePNG(_ image: CGImage, to url: URL) -> Bool {
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return false }
        return (try? data.write(to: url, options: .withoutOverwriting)) != nil
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
        reconnectAttempt = 0
        load(current, startAt: resumePoint)
    }

    /// Where a reload of the current item should start. Live streams have none: their position is a
    /// broadcast timestamp, not something to seek back to.
    private var resumePoint: Double? {
        guard current?.isLive == false else { return nil }
        return engine.hasVideoFrame && engine.position > 0 ? engine.position : requestedStart
    }

    private func load(_ item: PlaybackItem, startAt: Double?) {
        requestedStart = startAt
        engine.load(item.url, profile: StreamProfile(isLive: item.isLive), startAt: startAt)
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

    private func step(_ delta: Int) {
        guard let current,
              let target = QueueNavigation.target(from: index, delta: delta, count: queue.count, wraps: current.isLive) else { return }
        saveProgress()
        start(at: target, startAt: resumePosition?(queue[target]), debounce: true)
    }

    private func start(at position: Int, startAt: Double?, debounce: Bool = false) {
        cancelAutoplay()
        reconnectAttempt = 0
        earlyEndPosition = nil
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
        load(item, startAt: startAt)
        if item.isLive { onProgress?(item, 0, 0, true) }
        startProgressTimer()
        loadEPG(for: item)
    }

    /// Retries with backoff before surfacing an error. On-demand items resume where they stopped.
    private func handleFailure(_ message: String) {
        guard let current else { return }
        guard let delay = ReconnectPolicy.delay(afterFailedAttempts: reconnectAttempt) else {
            engine.showError(message)
            return
        }
        reconnectAttempt += 1
        let resumeAt = resumePoint
        engine.prepareForTuning()
        tuneTask?.cancel()
        tuneTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, self.current == current else { return }
            self.load(current, startAt: resumeAt)
        }
    }

    private func handleEndOfFile() {
        guard let current else { return }
        // A live stream "ending" means the feed dropped; reconnect instead of sitting on the last frame.
        if current.isLive {
            handleFailure("The live stream stopped.")
            return
        }
        // FFmpeg reports a connection it gave up on as a normal ending, which would otherwise count as
        // finishing the file and start the next episode.
        if ReconnectPolicy.endedEarly(position: engine.position, duration: engine.duration,
                                      previousEarlyEnd: earlyEndPosition) {
            earlyEndPosition = engine.position
            handleFailure("The connection dropped.")
            return
        }
        saveProgress()
        guard QueueNavigation.shouldAutoplay(after: current, next: nextItem, enabled: PlayerPreferences.autoplayNextEpisode) else { return }
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
                self?.saveProgress(isFinal: false)
            }
        }
    }

    private func saveProgress(isFinal: Bool = true) {
        // Before the first frame the position is 0, which would overwrite the saved resume point.
        guard let current, !current.isLive, engine.duration > 0, engine.hasVideoFrame else { return }
        onProgress?(current, engine.position, engine.duration, isFinal)
    }

    /// Fetches the guide for a live channel and refetches when the current programme ends,
    /// so Now/Next stays correct during long viewing.
    private func loadEPG(for item: PlaybackItem) {
        epg = []
        epgTask?.cancel()
        guard item.isLive, let epgProvider else { return }
        epgTask = Task { [weak self] in
            while !Task.isCancelled {
                let entries = await epgProvider(item)
                guard !Task.isCancelled, let self, self.current?.id == item.id else { return }
                self.epg = entries
                guard let end = self.nowPlaying?.end ?? entries.first(where: { $0.start > .now })?.start else { return }
                // Bounded both ways: EPG times come from the provider, and `Duration` traps on huge values.
                try? await Task.sleep(for: .seconds(min(max(end.timeIntervalSinceNow, 60), 6 * 60 * 60)))
            }
        }
    }
}
