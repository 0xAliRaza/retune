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

extension Catalog {
    private struct ChannelsPart: Decodable { let channels: [Channel] }
    private struct MoviesPart: Decodable { let movies: [Movie] }
    private struct RestPart: Decodable {
        let fetchedAt: Date
        let liveCategories, vodCategories, seriesCategories: [MediaCategory]
        let series: [Series]
    }

    /// Decodes a cached catalog with its large sections in parallel (~25% faster on 80k+ items,
    /// measured: 445 ms → 345 ms). Returns nil if the file is missing or doesn't decode.
    public static func loadConcurrently(from url: URL) async -> Catalog? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        async let channels = Task.detached(priority: .userInitiated) { try? JSONDecoder().decode(ChannelsPart.self, from: data) }.value
        async let movies = Task.detached(priority: .userInitiated) { try? JSONDecoder().decode(MoviesPart.self, from: data) }.value
        async let rest = Task.detached(priority: .userInitiated) { try? JSONDecoder().decode(RestPart.self, from: data) }.value
        guard let channels = await channels, let movies = await movies, let rest = await rest else { return nil }
        return Catalog(fetchedAt: rest.fetchedAt, liveCategories: rest.liveCategories, vodCategories: rest.vodCategories,
                       seriesCategories: rest.seriesCategories, channels: channels.channels, movies: movies.movies,
                       series: rest.series)
    }
}

public enum CatalogLoader {
    public static func fetchXtream(_ client: XtreamClient) async throws -> Catalog {
        // Categories are tiny; fetch them first so a bad account fails fast.
        async let liveCategories = client.categories(.live)
        async let vodCategories = client.categories(.vod)
        async let seriesCategories = client.categories(.series)
        let categories = try await (liveCategories, vodCategories, seriesCategories)

        // All three stream lists download at once; throttled responses are retried by the client.
        async let channels = client.channels()
        async let movies = client.movies()
        async let series = client.series()
        let lists = try await (channels, movies, series)

        return Catalog(liveCategories: categories.0, vodCategories: categories.1, seriesCategories: categories.2,
                       channels: lists.0, movies: lists.1, series: lists.2)
    }

    public static func fetchM3U(_ url: URL, session: URLSession = .retuneAPI) async throws -> Catalog {
        let data: Data
        if url.isFileURL {
            data = try Data(contentsOf: url)
        } else {
            let (body, response) = try await session.boundedData(from: url, limit: URLSession.apiResponseLimit)
            if let status = (response as? HTTPURLResponse)?.statusCode, status != 200 { throw RetuneError.http(status) }
            data = body
        }
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw RetuneError.unreadableResponse
        }
        let catalog = M3UParser.catalog(from: M3UParser.parse(text))
        guard !catalog.isEmpty else { throw RetuneError.emptyPlaylist }
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
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
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
        return base.appendingPathComponent("Retune", isDirectory: true)
    }()

    public static var playlists: URL { support.appendingPathComponent("playlists.json") }
    public static var library: URL { support.appendingPathComponent("library.json") }
    /// Plain password file from early builds; `SecretStore.migrateLegacyFile` removes it.
    public static var legacySecrets: URL { support.appendingPathComponent("secrets.json") }

    public static func catalog(for playlist: UUID) -> URL {
        support.appendingPathComponent("Catalogs", isDirectory: true)
            .appendingPathComponent("\(playlist.uuidString).json")
    }

    /// M3U links, catalogs and history can reveal account details, so everything under `root` is made
    /// private to the user, including files written by builds that used looser permissions.
    public static func restrictPermissions(root: URL = support) {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: root.path) else { return }
        try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        guard let contents = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
        for case let item as URL in contents {
            let isDirectory = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            try? fileManager.setAttributes([.posixPermissions: isDirectory ? 0o700 : 0o600], ofItemAtPath: item.path)
        }
    }

    /// Earlier builds let URLSession's shared cache store API requests, whose URLs contain the password.
    /// The folders are deleted rather than emptied, because deleted SQLite rows stay readable on disk.
    public static func purgeNetworkCaches(bundleID: String?, library: URL? = nil) {
        guard let bundleID, !bundleID.isEmpty else { return }
        let fileManager = FileManager.default
        guard let root = library ?? fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first else { return }
        for folder in ["Caches", "HTTPStorages"] {
            try? fileManager.removeItem(at: root.appendingPathComponent(folder).appendingPathComponent(bundleID))
        }
    }
}
