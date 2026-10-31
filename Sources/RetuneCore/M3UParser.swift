import CryptoKit
import Foundation

/// Parses extended M3U playlists (`#EXTM3U` / `#EXTINF` with tvg-* attributes).
public enum M3UParser {
    public struct Entry: Hashable, Sendable {
        public let title: String
        public let url: URL
        public let attributes: [String: String]

        public var group: String? { attributes["group-title"].flatMap { $0.isEmpty ? nil : $0 } }
        public var logo: URL? { URL(lenient: attributes["tvg-logo"]) }
    }

    public static func parse(_ text: String) -> [Entry] {
        var entries: [Entry] = []
        var pendingInfo: (title: String, attributes: [String: String])?
        var pendingGroup: String?

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("#EXTINF") {
                pendingInfo = parseInfo(line)
            } else if line.hasPrefix("#EXTGRP:") {
                pendingGroup = String(line.dropFirst("#EXTGRP:".count)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("#") {
                continue
            } else if let url = URL(string: line), StreamURLPolicy.isAllowed(url) {
                var attributes = pendingInfo?.attributes ?? [:]
                if attributes["group-title"] == nil, let pendingGroup { attributes["group-title"] = pendingGroup }
                let title = pendingInfo?.title ?? attributes["tvg-name"] ?? url.lastPathComponent
                entries.append(Entry(title: title, url: url, attributes: attributes))
                pendingInfo = nil
                pendingGroup = nil
            }
        }
        return entries
    }

    /// `#EXTINF:-1 tvg-id="x" tvg-logo="y" group-title="News",Channel Name`
    /// The title follows the first comma that sits outside quoted attribute values.
    static func parseInfo(_ line: String) -> (title: String, attributes: [String: String]) {
        var inQuotes = false
        var splitIndex: String.Index?
        for index in line.indices {
            let character = line[index]
            if character == "\"" { inQuotes.toggle() }
            if character == ",", !inQuotes { splitIndex = index; break }
        }
        let header = splitIndex.map { String(line[..<$0]) } ?? line
        let title = splitIndex.map { String(line[line.index(after: $0)...]) } ?? ""
        return (title.trimmingCharacters(in: .whitespaces), parseAttributes(header))
    }

    /// Reads `key="value"` pairs. This is a single pass over the bytes because playlists come from
    /// strangers: a regex retries from every position, so one long line could hang the app.
    static func parseAttributes(_ header: String) -> [String: String] {
        let bytes = Array(header.utf8)
        var result: [String: String] = [:]
        var keyStart: Int?
        var index = 0
        while index < bytes.count {
            if isKeyByte(bytes[index]) {
                keyStart = keyStart ?? index
                index += 1
                continue
            }
            if let start = keyStart, bytes[index] == UInt8(ascii: "="), index + 1 < bytes.count,
               bytes[index + 1] == UInt8(ascii: "\"") {
                // No closing quote means no attribute can follow either.
                guard let close = bytes[(index + 2)...].firstIndex(of: UInt8(ascii: "\"")) else { break }
                let key = String(decoding: bytes[start..<index], as: UTF8.self).lowercased()
                result[key] = String(decoding: bytes[(index + 2)..<close], as: UTF8.self)
                index = close
            }
            keyStart = nil
            index += 1
        }
        return result
    }

    private static func isKeyByte(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "a")...UInt8(ascii: "z"),
             UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "_"), UInt8(ascii: "-"):
            true
        default:
            false
        }
    }

    /// Splits entries into live / movie buckets. Xtream-generated playlists put VOD under `/movie/`
    /// and `/series/`; otherwise file extensions decide.
    public static func catalog(from entries: [Entry]) -> Catalog {
        var liveGroups = OrderedGroups()
        var movieGroups = OrderedGroups()
        var channels: [Channel] = []
        var movies: [Movie] = []

        var seenURLs: Set<URL> = []
        // Ids derive from the URL, so a playlist listing the same stream twice would collide.
        for entry in entries where seenURLs.insert(entry.url).inserted {
            let group = entry.group ?? "Uncategorized"
            let id = stableID(for: entry.url)
            if isOnDemand(entry.url) {
                movies.append(Movie(id: id, name: entry.title, poster: entry.logo,
                                    categoryID: movieGroups.id(for: group), rating: nil, added: nil,
                                    containerExtension: entry.url.pathExtension.nilIfEmpty, directURL: entry.url))
            } else {
                channels.append(Channel(id: id, number: channels.count + 1, name: entry.title, logo: entry.logo,
                                        categoryID: liveGroups.id(for: group), epgChannelID: entry.attributes["tvg-id"],
                                        directURL: entry.url, hasArchive: false))
            }
        }
        return Catalog(liveCategories: liveGroups.categories, vodCategories: movieGroups.categories,
                       seriesCategories: [], channels: channels, movies: movies, series: [])
    }

    /// Ids end up in favorites and history keys, and M3U URLs often embed the account password.
    static func stableID(for url: URL) -> String {
        SHA256.hash(data: Data(url.absoluteString.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    static func isOnDemand(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        if path.contains("/movie/") || path.contains("/series/") { return true }
        return ["mkv", "mp4", "avi", "mov", "m4v", "wmv"].contains(url.pathExtension.lowercased())
    }
}

/// Assigns categories in order of first appearance.
private struct OrderedGroups {
    private(set) var categories: [MediaCategory] = []
    private var seen: Set<String> = []

    mutating func id(for name: String) -> String {
        if seen.insert(name).inserted { categories.append(MediaCategory(id: name, name: name)) }
        return name
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
