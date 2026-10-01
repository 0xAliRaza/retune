import Foundation

public enum LumenError: LocalizedError, Equatable, Sendable {
    case invalidServer
    case invalidCredentials
    case accountInactive(String)
    case http(Int)
    case emptyResponse
    case unreadableResponse
    case emptyPlaylist
    case missingPassword

    public var errorDescription: String? {
        switch self {
        case .invalidServer: "That server address doesn't look right. Use something like http://example.com:8080."
        case .invalidCredentials: "The server rejected that username or password."
        case .accountInactive(let status): "This account is \(status.lowercased())."
        case .http(let code): "The server responded with an error (HTTP \(code))."
        case .emptyResponse: "The server returned an empty response. It may be rate limiting — try again in a moment."
        case .unreadableResponse: "The server returned data Lumen couldn't read."
        case .emptyPlaylist: "No playable entries were found in this playlist."
        case .missingPassword: "The saved password for this playlist is missing. Edit the playlist to re-enter it."
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

    public init(credentials: XtreamCredentials, session: URLSession = .lumenAPI) {
        self.credentials = credentials
        self.session = session
    }

    // MARK: API

    public func authenticate() async throws -> AccountInfo {
        let data = try await fetch(action: nil)
        guard let response = try? JSONDecoder().decode(XtreamAuthResponse.self, from: data) else {
            throw LumenError.unreadableResponse
        }
        guard let account = response.account else { throw LumenError.invalidCredentials }
        guard account.isActive else { throw LumenError.accountInactive(account.status) }
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
        var items = [URLQueryItem(name: "username", value: credentials.username),
                     URLQueryItem(name: "password", value: credentials.password)]
        if let action { items.append(URLQueryItem(name: "action", value: action)) }
        items += parameters.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        components.queryItems = items
        return components.url!
    }

    private func streamURL(kind: String, id: String, ext: String) -> URL {
        credentials.server
            .appendingPathComponent(kind)
            .appendingPathComponent(credentials.username)
            .appendingPathComponent(credentials.password)
            .appendingPathComponent("\(id).\(ext)")
    }

    // MARK: Transport

    private func list<T: Decodable>(_ type: T.Type, action: String) async throws -> [T] {
        let data = try await fetch(action: action)
        // Panels answer an empty section with `[]`, `{}` or an empty body.
        if data.isEmpty || data == Data("{}".utf8) { return [] }
        guard let rows = try? JSONDecoder().decode([Failable<T>].self, from: data) else {
            throw LumenError.unreadableResponse
        }
        return rows.compactMap(\.value)
    }

    private func decode<T: Decodable>(_ type: T.Type, action: String, _ parameters: [String: String]) async throws -> T {
        let data = try await fetch(action: action, parameters)
        guard !data.isEmpty else { throw LumenError.emptyResponse }
        guard let value = try? JSONDecoder().decode(T.self, from: data) else { throw LumenError.unreadableResponse }
        return value
    }

    /// Fetches with a small backoff: panels commonly throttle bursts with HTTP 222/429 and empty bodies.
    private func fetch(action: String?, _ parameters: [String: String] = [:]) async throws -> Data {
        let url = apiURL(action: action, parameters)
        var lastError: Error = LumenError.emptyResponse
        for attempt in 0..<3 {
            if attempt > 0 { try await Task.sleep(for: .milliseconds(700 * attempt)) }
            do {
                let (data, response) = try await session.data(from: url)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 200
                if status == 200 { return data }
                lastError = LumenError.http(status)
                guard status == 222 || status == 429 || status >= 500 else { throw lastError }
            } catch let error as URLError where error.code == .timedOut || error.code == .networkConnectionLost {
                lastError = error
            }
        }
        throw lastError
    }
}

extension URLSession {
    /// Long resource timeout: full VOD catalogs can be tens of megabytes.
    public static let lumenAPI: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 45
        configuration.timeoutIntervalForResource = 600
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: configuration)
    }()
}
