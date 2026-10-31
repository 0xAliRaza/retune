import Foundation

/// A user-configured source. The Xtream password is stored separately in `SecretStore`.
public struct Playlist: Identifiable, Hashable, Codable, Sendable {
    public enum Source: Hashable, Codable, Sendable {
        case xtream(server: URL, username: String)
        case m3u(URL)
    }

    public let id: UUID
    public var name: String
    public var source: Source
    public let createdAt: Date

    public init(id: UUID = UUID(), name: String, source: Source, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.source = source
        self.createdAt = createdAt
    }

    public var kindLabel: String {
        switch source {
        case .xtream: "Xtream Codes"
        case .m3u(let url): url.isFileURL ? "M3U File" : "M3U URL"
        }
    }

    public var supportsSeries: Bool {
        if case .xtream = source { return true }
        return false
    }
}

public struct XtreamCredentials: Hashable, Codable, Sendable {
    public let server: URL
    public let username: String
    public let password: String

    public init(server: URL, username: String, password: String) {
        self.server = server
        self.username = username
        self.password = password
    }

    /// Xtream logins travel inside URLs, so a plain HTTP address exposes them to the network path.
    /// A bare "host:8080" counts, because `normalizeServer` defaults it to HTTP.
    public static func usesPlainHTTP(_ raw: String) -> Bool {
        normalizeServer(raw)?.scheme?.lowercased() == "http"
    }

    /// Normalises what users paste ("host:8080", "http://host:8080/", ".../player_api.php") into a base URL.
    public static func normalizeServer(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(" ") else { return nil }
        if !text.lowercased().hasPrefix("http://"), !text.lowercased().hasPrefix("https://") {
            text = "http://" + text
        }
        guard var components = URLComponents(string: text), let host = components.host, !host.isEmpty else { return nil }
        components.query = nil
        components.fragment = nil
        var path = components.path
        for suffix in ["/player_api.php", "/get.php", "/xmltv.php"] where path.lowercased().hasSuffix(suffix) {
            path = String(path.dropLast(suffix.count))
        }
        while path.hasSuffix("/") { path.removeLast() }
        components.path = path
        return components.url
    }

    /// Extracts Xtream credentials from a provider M3U link such as
    /// `http://host:8080/get.php?username=u&password=p&type=m3u_plus`.
    public static func parse(fromPlaylistURL raw: String) -> XtreamCredentials? {
        guard let components = URLComponents(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              let items = components.queryItems,
              let username = items.first(where: { $0.name == "username" })?.value, !username.isEmpty,
              let password = items.first(where: { $0.name == "password" })?.value, !password.isEmpty,
              let server = normalizeServer(raw) else { return nil }
        return XtreamCredentials(server: server, username: username, password: password)
    }
}

/// Everything the player needs to start and describe one stream.
public struct PlaybackItem: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let kind: ContentKind
    public let title: String
    public let subtitle: String?
    public let url: URL
    public let artwork: URL?
    /// Provider stream id, used for EPG lookups on live channels.
    public let streamID: String?
    /// For episodes: the parent series id, so "continue watching" can open the show.
    public let parentID: String?

    public init(id: String, kind: ContentKind, title: String, subtitle: String? = nil, url: URL,
                artwork: URL? = nil, streamID: String? = nil, parentID: String? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.url = url
        self.artwork = artwork
        self.streamID = streamID
        self.parentID = parentID
    }

    public var isLive: Bool { kind == .live }

    public func with(url newURL: URL) -> PlaybackItem {
        PlaybackItem(id: id, kind: kind, title: title, subtitle: subtitle, url: newURL,
                     artwork: artwork, streamID: streamID, parentID: parentID)
    }
}

/// Stable keys used for favorites and watch progress, scoped per playlist.
public enum ContentKey {
    /// Prefix shared by every key belonging to one playlist.
    public static func playlistPrefix(_ playlist: UUID) -> String { playlist.uuidString + "/" }

    public static func make(playlist: UUID, kind: ContentKind, id: String) -> String {
        "\(playlist.uuidString)/\(kind.rawValue)/\(id)"
    }

    /// Key for a provider category in one section, e.g. `<uuid>/category/live/104`.
    public static func category(playlist: UUID, kind: ContentKind, id: String) -> String {
        categoryPrefix(playlist: playlist, kind: kind) + id
    }

    public static func categoryPrefix(playlist: UUID, kind: ContentKind) -> String {
        "\(playlist.uuidString)/category/\(kind.rawValue)/"
    }
}
