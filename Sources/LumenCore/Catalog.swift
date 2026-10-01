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

    /// nil when the file is missing. A file that exists but can't be decoded is moved aside to
    /// `<name>.corrupt-<timestamp>` first, so the next save can't silently destroy what was in it.
    public func load() -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let value = try? JSONDecoder().decode(Value.self, from: data) { return value }
        let backup = url.appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970))")
        try? FileManager.default.moveItem(at: url, to: backup)
        return nil
    }

    /// Writes atomically with owner-only permissions from the first byte (library and secrets hold private data).
    public func save(_ value: Value) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(value)
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        guard fileManager.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        // rename(2) atomically replaces the target and keeps the temp file's 0600 mode
        // (FileManager.replaceItemAt would carry over the old file's permissions).
        guard rename(temporary.path, url.path) == 0 else {
            try? fileManager.removeItem(at: temporary)
            throw CocoaError(.fileWriteUnknown)
        }
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
