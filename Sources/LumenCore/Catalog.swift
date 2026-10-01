import Foundation

/// The full browsable content of one playlist. Cached on disk so launches are instant.
public struct Catalog: Codable, Sendable {
    public var fetchedAt: Date
    public var liveCategories: [MediaCategory]
    public var vodCategories: [MediaCategory]
    public var seriesCategories: [MediaCategory]
    public var channels: [Channel]
    public var movies: [Movie]
    public var series: [Series]

    public init(fetchedAt: Date = .now, liveCategories: [MediaCategory], vodCategories: [MediaCategory],
                seriesCategories: [MediaCategory], channels: [Channel], movies: [Movie], series: [Series]) {
        self.fetchedAt = fetchedAt
        self.liveCategories = liveCategories
        self.vodCategories = vodCategories
        self.seriesCategories = seriesCategories
        self.channels = channels
        self.movies = movies
        self.series = series
    }

    public var isEmpty: Bool { channels.isEmpty && movies.isEmpty && series.isEmpty }

    public func isStale(maxAge: TimeInterval, now: Date = .now) -> Bool {
        now.timeIntervalSince(fetchedAt) > maxAge
    }
}

public enum CatalogLoader {
    public static func fetchXtream(_ client: XtreamClient) async throws -> Catalog {
        // Categories are tiny; fetch them first so a bad account fails fast. The large stream
        // lists run with limited concurrency because panels throttle request bursts.
        async let liveCategories = client.categories(.live)
        async let vodCategories = client.categories(.vod)
        async let seriesCategories = client.categories(.series)
        let categories = try await (liveCategories, vodCategories, seriesCategories)

        async let channels = client.channels()
        async let movies = client.movies()
        let firstBatch = try await (channels, movies)
        let series = try await client.series()

        return Catalog(liveCategories: categories.0, vodCategories: categories.1, seriesCategories: categories.2,
                       channels: firstBatch.0, movies: firstBatch.1, series: series)
    }

    public static func fetchM3U(_ url: URL, session: URLSession = .lumenAPI) async throws -> Catalog {
        let data: Data
        if url.isFileURL {
            data = try Data(contentsOf: url)
        } else {
            let (body, response) = try await session.data(from: url)
            if let status = (response as? HTTPURLResponse)?.statusCode, status != 200 { throw LumenError.http(status) }
            data = body
        }
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw LumenError.unreadableResponse
        }
        let catalog = M3UParser.catalog(from: M3UParser.parse(text))
        guard !catalog.isEmpty else { throw LumenError.emptyPlaylist }
        return catalog
    }
}

/// Atomic JSON persistence for small app state and the catalog cache.
public struct JSONFileStore<Value: Codable>: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func load() -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    public func save(_ value: Value) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(value)
        try data.write(to: url, options: .atomic)
    }

    public func delete() {
        try? FileManager.default.removeItem(at: url)
    }
}

public enum AppPaths {
    public static let support: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Lumen", isDirectory: true)
    }()

    public static var playlists: URL { support.appendingPathComponent("playlists.json") }
    public static var library: URL { support.appendingPathComponent("library.json") }
    public static var secrets: URL { support.appendingPathComponent("secrets.json") }

    public static func catalog(for playlist: UUID) -> URL {
        support.appendingPathComponent("Catalogs", isDirectory: true)
            .appendingPathComponent("\(playlist.uuidString).json")
    }
}
