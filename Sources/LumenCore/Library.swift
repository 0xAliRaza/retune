import CryptoKit
import Foundation

public struct WatchProgress: Codable, Hashable, Sendable {
    public var item: PlaybackItem
    public var position: Double
    public var duration: Double
    public var updatedAt: Date

    public init(item: PlaybackItem, position: Double, duration: Double, updatedAt: Date = .now) {
        self.item = item
        self.position = position
        self.duration = duration
        self.updatedAt = updatedAt
    }

    public var fraction: Double { duration > 0 ? min(max(position / duration, 0), 1) : 0 }

    /// Treat the last few minutes (credits) as finished.
    public var isFinished: Bool {
        guard duration > 0 else { return false }
        return position >= duration * 0.95 || duration - position < 90
    }

    /// Worth offering "Resume" for.
    public var isResumable: Bool { position >= 30 && !isFinished }

    public var remaining: Double { max(duration - position, 0) }
}

/// Favorites, resume points, recently watched channels and category preferences.
/// Content keys come from `ContentKey.make`, category keys from `ContentKey.category`.
public struct LibraryState: Codable, Sendable {
    public var favorites: Set<String> = []
    public var progress: [String: WatchProgress] = [:]
    public var recentChannels: [String] = []
    public var hiddenCategories: Set<String> = []
    public var lockedCategories: Set<String> = []
    public var pinnedCategories: [String] = []
    /// Salted SHA-256 of the parental PIN; nil when no PIN is set.
    public private(set) var pinHash: String?

    public static let recentChannelLimit = 30
    public static let progressLimit = 2000

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case favorites, progress, recentChannels, hiddenCategories, lockedCategories, pinnedCategories, pinHash
    }

    /// Tolerates files written by older versions that lack newer fields.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        favorites = try c.decodeIfPresent(Set<String>.self, forKey: .favorites) ?? []
        // One malformed entry shouldn't take the rest of the history with it.
        progress = (try? c.decodeIfPresent([String: Failable<WatchProgress>].self, forKey: .progress))?
            .flatMap { $0 }?.compactMapValues(\.value) ?? [:]
        recentChannels = try c.decodeIfPresent([String].self, forKey: .recentChannels) ?? []
        hiddenCategories = try c.decodeIfPresent(Set<String>.self, forKey: .hiddenCategories) ?? []
        lockedCategories = try c.decodeIfPresent(Set<String>.self, forKey: .lockedCategories) ?? []
        pinnedCategories = try c.decodeIfPresent([String].self, forKey: .pinnedCategories) ?? []
        pinHash = try c.decodeIfPresent(String.self, forKey: .pinHash)
    }

    // MARK: Categories

    public mutating func toggleHidden(_ categoryKey: String) {
        if hiddenCategories.remove(categoryKey) == nil { hiddenCategories.insert(categoryKey) }
    }

    public mutating func togglePinned(_ categoryKey: String) {
        if let index = pinnedCategories.firstIndex(of: categoryKey) {
            pinnedCategories.remove(at: index)
        } else {
            pinnedCategories.append(categoryKey)
        }
    }

    public mutating func setLocked(_ categoryKey: String, _ locked: Bool) {
        if locked { lockedCategories.insert(categoryKey) } else { lockedCategories.remove(categoryKey) }
    }

    /// Provider category ids under `prefix` (from `ContentKey.categoryPrefix`) in a key set.
    public static func ids(in keys: some Sequence<String>, prefix: String) -> [String] {
        keys.filter { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
    }

    // MARK: Parental PIN

    public var hasPIN: Bool { pinHash != nil }

    public mutating func setPIN(_ pin: String) { pinHash = Self.hash(pin) }

    public func verifyPIN(_ pin: String) -> Bool { pinHash != nil && pinHash == Self.hash(pin) }

    /// Removing the PIN also removes every lock, since nothing could unlock them anymore.
    public mutating func removePIN() {
        pinHash = nil
        lockedCategories = []
    }

    public static func isValidPIN(_ pin: String) -> Bool { pin.count >= 4 && pin.count <= 8 && pin.allSatisfy(\.isNumber) }

    private static func hash(_ pin: String) -> String {
        SHA256.hash(data: Data("lumen.parental.\(pin)".utf8)).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: History

    /// Drops an entry from Continue Watching. For episodes, every in-progress episode of the same
    /// series goes too; otherwise the row would just fall back to an older episode.
    public mutating func removeFromContinueWatching(key: String) {
        guard let entry = progress[key] else { return }
        guard entry.item.kind == .episode, let parent = entry.item.parentID else {
            progress.removeValue(forKey: key)
            return
        }
        let scope = String(key.prefix(while: { $0 != "/" })) + "/"
        progress = progress.filter { candidate in
            !(candidate.key.hasPrefix(scope) && candidate.value.item.parentID == parent && candidate.value.isResumable)
        }
    }

    public mutating func markWatched(key: String, item: PlaybackItem, duration: Double?) {
        let length = max(duration ?? 1, 1)
        progress[key] = WatchProgress(item: item, position: length, duration: length)
    }

    public mutating func markUnwatched(key: String) { progress.removeValue(forKey: key) }

    public mutating func removeRecentChannel(_ key: String) { recentChannels.removeAll { $0 == key } }

    public mutating func clearContinueWatching(playlist: UUID) {
        let prefix = ContentKey.playlistPrefix(playlist)
        progress = progress.filter { !($0.key.hasPrefix(prefix) && $0.value.isResumable) }
    }

    public mutating func clearRecentChannels(playlist: UUID) {
        let prefix = ContentKey.playlistPrefix(playlist)
        recentChannels.removeAll { $0.hasPrefix(prefix) }
    }

    public mutating func toggleFavorite(_ key: String) {
        if favorites.remove(key) == nil { favorites.insert(key) }
    }

    public mutating func recordProgress(key: String, item: PlaybackItem, position: Double, duration: Double, at date: Date = .now) {
        guard duration > 0, position.isFinite, duration.isFinite else { return }
        progress[key] = WatchProgress(item: item, position: position, duration: duration, updatedAt: date)
        pruneProgress()
    }

    /// Over the cap, drop barely-started and in-progress entries before "watched" marks, oldest first.
    private mutating func pruneProgress() {
        guard progress.count > Self.progressLimit else { return }
        let ordered = progress.sorted { lhs, rhs in
            if lhs.value.isFinished != rhs.value.isFinished { return !lhs.value.isFinished }
            return lhs.value.updatedAt < rhs.value.updatedAt
        }
        ordered.prefix(progress.count - Self.progressLimit).forEach { progress.removeValue(forKey: $0.key) }
    }

    /// Replaces stored stream URLs with credential-free locators (see `XtreamClient.locator`).
    /// Returns true when anything changed, so callers know to persist the cleaned state.
    @discardableResult
    public mutating func sanitizeStreamURLs() -> Bool {
        var changed = false
        for (key, entry) in progress {
            guard let locator = XtreamClient.locator(for: entry.item.url) else { continue }
            progress[key]?.item = entry.item.with(url: locator)
            changed = true
        }
        return changed
    }

    public mutating func recordChannel(key: String) {
        recentChannels.removeAll { $0 == key }
        recentChannels.insert(key, at: 0)
        if recentChannels.count > Self.recentChannelLimit { recentChannels.removeLast(recentChannels.count - Self.recentChannelLimit) }
    }

    /// Resumable items for a playlist, most recent first. Episodes collapse to one entry per series.
    public func continueWatching(playlist: UUID) -> [WatchProgress] {
        let prefix = ContentKey.playlistPrefix(playlist)
        var seenSeries: Set<String> = []
        return progress
            .filter { $0.key.hasPrefix(prefix) && $0.value.isResumable }
            .map(\.value)
            .sorted { $0.updatedAt > $1.updatedAt }
            .filter { entry in
                guard entry.item.kind == .episode, let parent = entry.item.parentID else { return true }
                return seenSeries.insert(parent).inserted
            }
    }

    /// Favorite ids of one kind for a playlist (the raw provider ids, without the key prefix).
    public func favoriteIDs(playlist: UUID, kind: ContentKind) -> Set<String> {
        let prefix = "\(playlist.uuidString)/\(kind.rawValue)/"
        return Set(favorites.lazy.filter { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) })
    }

    public mutating func removeAll(playlist: UUID) {
        let prefix = ContentKey.playlistPrefix(playlist)
        favorites = favorites.filter { !$0.hasPrefix(prefix) }
        progress = progress.filter { !$0.key.hasPrefix(prefix) }
        recentChannels.removeAll { $0.hasPrefix(prefix) }
        hiddenCategories = hiddenCategories.filter { !$0.hasPrefix(prefix) }
        lockedCategories = lockedCategories.filter { !$0.hasPrefix(prefix) }
        pinnedCategories.removeAll { $0.hasPrefix(prefix) }
    }
}
