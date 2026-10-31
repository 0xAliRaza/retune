import Foundation

public enum RetuneError: LocalizedError, Equatable, Sendable {
    case invalidServer
    case invalidCredentials
    case accountInactive(String)
    case http(Int)
    case emptyResponse
    case unreadableResponse
    case emptyPlaylist
    case missingPassword
    case keychain(OSStatus)
    case responseTooLarge

    public var errorDescription: String? {
        switch self {
        case .invalidServer: "That server address doesn't look right. Use something like http://example.com:8080."
        case .invalidCredentials: "The server rejected that username or password."
        case .accountInactive(let status): "This account is \(status.lowercased())."
        case .http(let code): "The server responded with an error (HTTP \(code))."
        case .emptyResponse: "The server returned an empty response. It may be rate limiting — try again in a moment."
        case .unreadableResponse: "The server returned data Retune couldn't read."
        case .emptyPlaylist: "No playable entries were found in this playlist."
        case .missingPassword: "The saved password for this playlist is missing, or Keychain access was denied. Edit the playlist to re-enter it."
        case .keychain(let status): "The password couldn't be saved to your Keychain (error \(status))."
        case .responseTooLarge: "The server sent far more data than a playlist should contain."
        }
    }
}

/// Client for the Xtream Codes player API (`player_api.php`).
public struct XtreamClient: Sendable {
    public enum Section: String, Sendable {
        case live, vod, series

        fileprivate var categoriesAction: String { "get_\(rawValue)_categories" }
    }

    public let credentials: XtreamCredentials
    private let session: URLSession

    public init(credentials: XtreamCredentials, session: URLSession = .retuneAPI) {
        self.credentials = credentials
        self.session = session
    }

    // MARK: API

    public func authenticate() async throws -> AccountInfo {
        let data = try await fetch(action: nil)
        guard let response = try? JSONDecoder().decode(XtreamAuthResponse.self, from: data) else {
            throw RetuneError.unreadableResponse
        }
        guard let account = response.account else { throw RetuneError.invalidCredentials }
        guard account.isActive else { throw RetuneError.accountInactive(account.status) }
        return account
    }

    public func categories(_ section: Section) async throws -> [MediaCategory] {
        try await list(XtreamCategoryDTO.self, action: section.categoriesAction).compactMap(\.category)
    }

    public func channels() async throws -> [Channel] {
        try await list(XtreamLiveDTO.self, action: "get_live_streams").compactMap(\.channel)
    }

    public func movies() async throws -> [Movie] {
        try await list(XtreamVODDTO.self, action: "get_vod_streams").compactMap(\.movie)
    }

    public func series() async throws -> [Series] {
        try await list(XtreamSeriesDTO.self, action: "get_series").compactMap(\.series)
    }

    public func movieInfo(id: String) async throws -> MediaInfo {
        try await decode(XtreamVODInfoResponse.self, action: "get_vod_info", ["vod_id": id]).info
    }

    public func seriesInfo(id: String) async throws -> SeriesDetail {
        try await decode(XtreamSeriesInfoResponse.self, action: "get_series_info", ["series_id": id]).detail
    }

    public func shortEPG(streamID: String, limit: Int = 4) async throws -> [EPGEntry] {
        try await decode(XtreamEPGResponse.self, action: "get_short_epg",
                         ["stream_id": streamID, "limit": String(limit)]).entries
    }

    // MARK: Stream URLs

    public func liveURL(streamID: String, format: String = "ts") -> URL {
        streamURL(kind: "live", id: streamID, ext: format)
    }

    public func movieURL(_ movie: Movie) -> URL {
        movie.directURL ?? streamURL(kind: "movie", id: movie.id, ext: movie.containerExtension ?? "mp4")
    }

    public func episodeURL(_ episode: Episode) -> URL {
        episode.directURL ?? streamURL(kind: "series", id: episode.id, ext: episode.containerExtension ?? "mp4")
    }

    func apiURL(action: String?, _ parameters: [String: String] = [:]) -> URL {
        var components = URLComponents(url: credentials.server.appendingPathComponent("player_api.php"),
                                       resolvingAgainstBaseURL: false)!
        var items = [("username", credentials.username), ("password", credentials.password)]
        if let action { items.append(("action", action)) }
        items += parameters.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
        // URLQueryItem leaves "+" as is, and PHP panels read that as a space, breaking such passwords.
        components.percentEncodedQueryItems = items.map { name, value in
            URLQueryItem(name: name, value: value.addingPercentEncoding(withAllowedCharacters: Self.queryValueAllowed))
        }
        return components.url!
    }

    private static let queryValueAllowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))

    private func streamURL(kind: String, id: String, ext: String) -> URL {
        streamURL(kind: kind, file: "\(id).\(ext)")
    }

    /// `appendingPathComponent` leaves "/" unescaped, which would split a password like "a/b" into two segments.
    private func streamURL(kind: String, file: String) -> URL {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove("/")
        let segments = [kind, credentials.username, credentials.password, file]
            .map { $0.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0 }
        let base = credentials.server.absoluteString.hasSuffix("/") ? String(credentials.server.absoluteString.dropLast()) : credentials.server.absoluteString
        return URL(string: base + "/" + segments.joined(separator: "/"))!
    }

    // MARK: Credential-free locators

    /// Watch history stores `retune://<kind>/<file>` instead of the real stream URL, so the password never
    /// lands in library.json and items keep working after the password or server changes.
    public static let locatorScheme = "retune"

    public static func locator(for streamURL: URL) -> URL? {
        // Percent-encoded, or a "/" inside the password would look like an extra path segment.
        let parts = streamURL.path(percentEncoded: true).split(separator: "/").map(String.init)
        guard parts.count >= 4, ["movie", "series", "live"].contains(parts[parts.count - 4]) else { return nil }
        return URL(string: "\(locatorScheme)://\(parts[parts.count - 4])/\(parts[parts.count - 1])")
    }

    /// Locator for a playlist entry with no Xtream account behind it. M3U stream URLs often embed
    /// credentials, so history keeps only the entry's id and the URL comes back from the catalog.
    public static func opaqueLocator(id: String) -> URL? {
        URL(string: "\(locatorScheme)://item/\(id)")
    }

    /// Turns a locator back into a playable URL for the current credentials; other URLs pass through.
    public func resolve(_ url: URL) -> URL {
        guard url.scheme == Self.locatorScheme, let kind = url.host() else { return url }
        return streamURL(kind: kind, file: url.lastPathComponent)
    }

    // MARK: Transport

    private func list<T: Decodable>(_ type: T.Type, action: String) async throws -> [T] {
        let data = try await fetch(action: action)
        // An empty body is how throttling panels answer bursts; treating it as "no rows" would cache an
        // empty section over a good one. Genuinely empty sections come back as `[]` or `{}`.
        if data.isEmpty { throw RetuneError.emptyResponse }
        if data == Data("{}".utf8) { return [] }
        guard let rows = try? JSONDecoder().decode([Failable<T>].self, from: data) else {
            throw RetuneError.unreadableResponse
        }
        return rows.compactMap(\.value)
    }

    private func decode<T: Decodable>(_ type: T.Type, action: String, _ parameters: [String: String]) async throws -> T {
        let data = try await fetch(action: action, parameters)
        guard !data.isEmpty else { throw RetuneError.emptyResponse }
        guard let value = try? JSONDecoder().decode(T.self, from: data) else { throw RetuneError.unreadableResponse }
        return value
    }

    /// Fetches with a small backoff: panels commonly throttle bursts with HTTP 222/429 and empty bodies.
    private func fetch(action: String?, _ parameters: [String: String] = [:]) async throws -> Data {
        let url = apiURL(action: action, parameters)
        var lastError: Error = RetuneError.emptyResponse
        for attempt in 0..<3 {
            if attempt > 0 { try await Task.sleep(for: .milliseconds(700 * attempt)) }
            do {
                let (data, response) = try await session.boundedData(from: url, limit: URLSession.apiResponseLimit)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 200
                if status == 200, !(data.isEmpty && action != nil) { return data }
                if status == 200 { lastError = RetuneError.emptyResponse; continue }
                lastError = RetuneError.http(status)
                guard status == 222 || status == 429 || status >= 500 else { throw lastError }
            } catch let error as URLError where error.code == .timedOut || error.code == .networkConnectionLost {
                lastError = error
            }
        }
        throw lastError
    }
}

extension URLSession {
    /// Far above any real catalog (88k titles is under 100 MB), low enough to stop a hostile endless response.
    public static let apiResponseLimit = 256 << 20

    /// Long resource timeout: full VOD catalogs can be tens of megabytes.
    /// No URL cache or cookies: Xtream requests carry the password in the URL, and a disk cache would
    /// store it in plain text whatever the request's cache policy says.
    public static let retuneAPI: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 45
        configuration.timeoutIntervalForResource = 600
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: configuration)
    }()

    /// Like `data(from:)`, but gives up as soon as the body passes `limit` bytes.
    public func boundedData(from url: URL, limit: Int) async throws -> (Data, URLResponse) {
        let collector = BoundedDataCollector(limit: limit)
        let task = dataTask(with: url)
        task.delegate = collector
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                collector.begin(continuation)
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }
}

private final class BoundedDataCollector: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let limit: Int
    private let lock = NSLock()
    // Guarded by `lock`.
    private var received = Data()
    private var continuation: CheckedContinuation<(Data, URLResponse), Error>?

    init(limit: Int) {
        self.limit = limit
    }

    func begin(_ continuation: CheckedContinuation<(Data, URLResponse), Error>) {
        lock.withLock { self.continuation = continuation }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let overflowed = lock.withLock {
            received.append(data)
            return received.count > limit
        }
        guard overflowed else { return }
        finish(.failure(RetuneError.responseTooLarge))
        dataTask.cancel()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            finish(.failure(error))
        } else if let response = task.response {
            finish(.success((lock.withLock { received }, response)))
        } else {
            finish(.failure(URLError(.badServerResponse)))
        }
    }

    private func finish(_ result: Result<(Data, URLResponse), Error>) {
        let pending = lock.withLock {
            defer { continuation = nil }
            return continuation
        }
        pending?.resume(with: result)
    }
}
