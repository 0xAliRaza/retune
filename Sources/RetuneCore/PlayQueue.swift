import Foundation

/// Limits a play queue to a window around the chosen item, so starting playback from a
/// 65k-title "All" view doesn't build tens of thousands of stream URLs.
public enum QueueWindow {
    public static let defaultSize = 500

    /// The range of `count` items to queue, centred on `index` and shifted to stay in bounds.
    public static func range(count: Int, around index: Int, size: Int = defaultSize) -> Range<Int> {
        guard count > size else { return 0..<count }
        let start = min(max(index - size / 2, 0), count - size)
        return start..<(start + size)
    }
}

/// Pure rules for moving through a play queue; `PlaybackSession` applies them.
public enum QueueNavigation {
    /// Index after moving `delta` steps. Live TV wraps like a remote; on-demand queues stop at the ends.
    public static func target(from index: Int, delta: Int, count: Int, wraps: Bool) -> Int? {
        guard count > 0 else { return nil }
        let target = index + delta
        if wraps { return ((target % count) + count) % count }
        return (0..<count).contains(target) ? target : nil
    }

    /// Only the next episode of the same series plays by itself. A movie ending, or a Continue
    /// Watching queue that mixes shows, must not roll into an unrelated title.
    public static func shouldAutoplay(after current: PlaybackItem, next: PlaybackItem?, enabled: Bool) -> Bool {
        guard enabled, let next, current.kind == .episode, next.kind == .episode else { return false }
        return current.parentID != nil && current.parentID == next.parentID
    }

    /// Builds playback items from `source`, keeping `selected` pointing at the same element even when
    /// some elements can't be played (no stream URL). Returns nil if the selected element itself can't.
    public static func build<Element>(_ source: [Element], selected: Int,
                                      make: (Element) -> PlaybackItem?) -> (items: [PlaybackItem], index: Int)? {
        var items: [PlaybackItem] = []
        var selectedIndex: Int?
        for (offset, element) in source.enumerated() {
            guard let item = make(element) else { continue }
            if offset == selected { selectedIndex = items.count }
            items.append(item)
        }
        return selectedIndex.map { (items, $0) }
    }
}

/// Chooses what a series page's main button should play.
public enum EpisodePicker {
    public enum Pick: Equatable, Sendable {
        /// An episode is part-way through.
        case resume(Int)
        /// The last finished episode has a successor.
        case next(Int)
        /// Nothing started yet, or the whole series is finished.
        case start(Int)
    }

    /// `progress(i)` is the saved progress of episode `i` (in play order). The most recent activity wins:
    /// a newer in-progress episode beats an older finished one and vice versa.
    public static func pick(count: Int, progress: (Int) -> WatchProgress?) -> Pick? {
        guard count > 0 else { return nil }
        let latest = (0..<count)
            .compactMap { index in progress(index).map { (index, $0) } }
            .filter { $0.1.isResumable || $0.1.isFinished }
            .max { $0.1.updatedAt < $1.1.updatedAt }
        guard let (index, entry) = latest else { return .start(0) }
        if entry.isResumable { return .resume(index) }
        return index + 1 < count ? .next(index + 1) : .start(0)
    }
}

/// How long to wait before each automatic reconnect. Single-connection IPTV accounts often refuse a new
/// stream until the provider notices the previous one closed, so the first attempts fail spuriously.
public enum ReconnectPolicy {
    public static let delays: [Duration] = [.seconds(1), .seconds(2), .seconds(4), .seconds(6)]

    /// Delay before retry number `attempt + 1`, or nil once every retry has been used.
    public static func delay(afterFailedAttempts attempt: Int) -> Duration? {
        delays.indices.contains(attempt) ? delays[attempt] : nil
    }

    public static var maxAttempts: Int { delays.count }

    /// Whether a file that ended this far from its length should be treated as a dropped connection.
    public static let earlyEndMargin: Double = 60
    /// Playback gained since the previous early end that makes another retry worthwhile.
    public static let earlyEndProgress: Double = 5

    /// FFmpeg reports a connection it gave up on as a normal end of file. A file that is really cut short
    /// stops at the same spot every time, so a retry has to get further or the end is accepted as real.
    public static func endedEarly(position: Double, duration: Double, previousEarlyEnd: Double?) -> Bool {
        guard duration > 0, duration - position > earlyEndMargin else { return false }
        guard let previousEarlyEnd else { return true }
        return position > previousEarlyEnd + earlyEndProgress
    }
}
