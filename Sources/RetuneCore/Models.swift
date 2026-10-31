import Foundation

public enum ContentKind: String, Codable, Sendable, CaseIterable {
    case live, movie, series, episode
}

public struct MediaCategory: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct Channel: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let number: Int?
    public let name: String
    public let logo: URL?
    public let categoryID: String?
    public let epgChannelID: String?
    /// Set for M3U entries; Xtream channels derive their URL from credentials.
    public let directURL: URL?
    public let hasArchive: Bool

    public init(id: String, number: Int?, name: String, logo: URL?, categoryID: String?,
                epgChannelID: String?, directURL: URL?, hasArchive: Bool) {
        self.id = id
        self.number = number
        self.name = name
        self.logo = logo
        self.categoryID = categoryID
        self.epgChannelID = epgChannelID
        self.directURL = directURL
        self.hasArchive = hasArchive
    }
}

public struct Movie: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let name: String
    public let poster: URL?
    public let categoryID: String?
    public let rating: Double?
    public let added: Date?
    public let containerExtension: String?
    public let directURL: URL?

    public init(id: String, name: String, poster: URL?, categoryID: String?, rating: Double?,
                added: Date?, containerExtension: String?, directURL: URL?) {
        self.id = id
        self.name = name
        self.poster = poster
        self.categoryID = categoryID
        self.rating = rating
        self.added = added
        self.containerExtension = containerExtension
        self.directURL = directURL
    }
}

public struct Series: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let name: String
    public let cover: URL?
    public let backdrop: URL?
    public let categoryID: String?
    public let plot: String?
    public let genre: String?
    public let releaseDate: String?
    public let rating: Double?
    public let lastModified: Date?

    public init(id: String, name: String, cover: URL?, backdrop: URL?, categoryID: String?, plot: String?,
                genre: String?, releaseDate: String?, rating: Double?, lastModified: Date?) {
        self.id = id
        self.name = name
        self.cover = cover
        self.backdrop = backdrop
        self.categoryID = categoryID
        self.plot = plot
        self.genre = genre
        self.releaseDate = releaseDate
        self.rating = rating
        self.lastModified = lastModified
    }
}

/// Rich metadata shared by movie and series detail screens.
public struct MediaInfo: Hashable, Codable, Sendable {
    public var plot: String?
    public var cast: String?
    public var director: String?
    public var genre: String?
    public var releaseDate: String?
    public var durationSeconds: Int?
    public var rating: Double?
    public var poster: URL?
    public var backdrop: URL?
    public var youtubeTrailer: String?

    public init(plot: String? = nil, cast: String? = nil, director: String? = nil, genre: String? = nil,
                releaseDate: String? = nil, durationSeconds: Int? = nil, rating: Double? = nil,
                poster: URL? = nil, backdrop: URL? = nil, youtubeTrailer: String? = nil) {
        self.plot = plot
        self.cast = cast
        self.director = director
        self.genre = genre
        self.releaseDate = releaseDate
        self.durationSeconds = durationSeconds
        self.rating = rating
        self.poster = poster
        self.backdrop = backdrop
        self.youtubeTrailer = youtubeTrailer
    }

    /// The four-digit year from a release date like "2025-06-20".
    public var year: String? {
        guard let releaseDate, releaseDate.count >= 4 else { return nil }
        let prefix = String(releaseDate.prefix(4))
        return Int(prefix) != nil ? prefix : nil
    }
}

public struct Episode: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let season: Int
    public let number: Int
    public let title: String
    public let containerExtension: String?
    public let plot: String?
    public let image: URL?
    public let durationSeconds: Int?
    public let directURL: URL?

    public init(id: String, season: Int, number: Int, title: String, containerExtension: String?,
                plot: String?, image: URL?, durationSeconds: Int?, directURL: URL? = nil) {
        self.id = id
        self.season = season
        self.number = number
        self.title = title
        self.containerExtension = containerExtension
        self.plot = plot
        self.image = image
        self.durationSeconds = durationSeconds
        self.directURL = directURL
    }
}

public struct Season: Identifiable, Hashable, Codable, Sendable {
    public var id: Int { number }
    public let number: Int
    public let name: String
    public let cover: URL?
    public let episodes: [Episode]

    public init(number: Int, name: String, cover: URL?, episodes: [Episode]) {
        self.number = number
        self.name = name
        self.cover = cover
        self.episodes = episodes
    }
}

public struct SeriesDetail: Hashable, Sendable {
    public let info: MediaInfo
    public let seasons: [Season]

    public init(info: MediaInfo, seasons: [Season]) {
        self.info = info
        self.seasons = seasons
    }
}

public struct EPGEntry: Identifiable, Hashable, Sendable {
    public var id: String { "\(start.timeIntervalSince1970)-\(title)" }
    public let title: String
    public let summary: String?
    public let start: Date
    public let end: Date

    public init(title: String, summary: String?, start: Date, end: Date) {
        self.title = title
        self.summary = summary
        self.start = start
        self.end = end
    }

    public func isLive(at date: Date = .now) -> Bool { start <= date && date < end }

    public func progress(at date: Date = .now) -> Double {
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 0 }
        return min(max(date.timeIntervalSince(start) / total, 0), 1)
    }
}

public struct AccountInfo: Hashable, Sendable {
    public let status: String
    public let message: String?
    public let expiresAt: Date?
    public let isTrial: Bool
    public let activeConnections: Int?
    public let maxConnections: Int?
    public let allowedFormats: [String]
    public let serverTimezone: String?

    public var isActive: Bool { status.caseInsensitiveCompare("Active") == .orderedSame }
}
