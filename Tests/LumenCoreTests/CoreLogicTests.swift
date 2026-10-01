import Foundation
import Testing
@testable import LumenCore

struct ServerAndURLTests {
    @Test(arguments: [
        ("iptv.example:8080", "http://iptv.example:8080"),
        ("http://iptv.example:8080/", "http://iptv.example:8080"),
        ("https://host.example/player_api.php", "https://host.example"),
        ("http://host.example:80/get.php?username=a&password=b", "http://host.example:80"),
        ("  host.example  ", "http://host.example"),
    ])
    func normalizesServer(input: String, expected: String) {
        #expect(XtreamCredentials.normalizeServer(input)?.absoluteString == expected)
    }

    @Test func rejectsGarbageServer() {
        #expect(XtreamCredentials.normalizeServer("") == nil)
        #expect(XtreamCredentials.normalizeServer("not a host") == nil)
    }

    @Test func extractsCredentialsFromM3ULink() throws {
        let creds = try #require(XtreamCredentials.parse(fromPlaylistURL: "http://h.example:8080/get.php?username=viewer&password=12&type=m3u_plus"))
        #expect(creds.server.absoluteString == "http://h.example:8080")
        #expect(creds.username == "viewer")
        #expect(creds.password == "12")
        #expect(XtreamCredentials.parse(fromPlaylistURL: "http://h.example/list.m3u") == nil)
    }

    @Test func buildsStreamAndAPIURLs() {
        let client = XtreamClient(credentials: XtreamCredentials(server: URL(string: "http://h.example:8080")!, username: "u", password: "p w"))
        #expect(client.liveURL(streamID: "42").absoluteString == "http://h.example:8080/live/u/p%20w/42.ts")
        let movie = Movie(id: "7", name: "M", poster: nil, categoryID: nil, rating: nil, added: nil, containerExtension: "mkv", directURL: nil)
        #expect(client.movieURL(movie).absoluteString == "http://h.example:8080/movie/u/p%20w/7.mkv")
        let episode = Episode(id: "9", season: 1, number: 1, title: "E", containerExtension: nil, plot: nil, image: nil, durationSeconds: nil)
        #expect(client.episodeURL(episode).absoluteString == "http://h.example:8080/series/u/p%20w/9.mp4")

        let api = client.apiURL(action: "get_series_info", ["series_id": "5"]).absoluteString
        #expect(api == "http://h.example:8080/player_api.php?username=u&password=p%20w&action=get_series_info&series_id=5")
    }
}

struct M3UParserTests {
    private let sample = """
    #EXTM3U url-tvg="http://epg.example/xmltv.php"
    #EXTINF:-1 tvg-id="bbc1.uk" tvg-name="BBC One" tvg-logo="http://logo/bbc.png" group-title="UK, Entertainment",BBC One HD
    http://h.example:8080/live/u/p/1.ts
    #EXTINF:-1 tvg-logo="http://logo/m.jpg" group-title="Movies",Some Movie (2024)
    http://h.example:8080/movie/u/p/77.mkv

    #EXTINF:-1,No Attributes Channel
    #EXTGRP:Misc
    https://cdn.example/stream.m3u8
    #EXTINF:-1 group-title="Docs",Local File
    http://cdn.example/files/doc.mp4
    """

    @Test func parsesEntriesAttributesAndTitles() {
        let entries = M3UParser.parse(sample)
        #expect(entries.count == 4)
        #expect(entries[0].title == "BBC One HD")
        #expect(entries[0].group == "UK, Entertainment")
        #expect(entries[0].attributes["tvg-id"] == "bbc1.uk")
        #expect(entries[0].logo?.absoluteString == "http://logo/bbc.png")
        #expect(entries[2].title == "No Attributes Channel")
        #expect(entries[2].group == "Misc")
    }

    @Test func splitsLiveAndOnDemand() {
        let catalog = M3UParser.catalog(from: M3UParser.parse(sample))
        #expect(catalog.channels.map(\.name) == ["BBC One HD", "No Attributes Channel"])
        #expect(catalog.movies.map(\.name) == ["Some Movie (2024)", "Local File"])
        #expect(catalog.liveCategories.map(\.name) == ["UK, Entertainment", "Misc"])
        #expect(catalog.vodCategories.map(\.name) == ["Movies", "Docs"])
        #expect(catalog.movies[0].containerExtension == "mkv")
        #expect(catalog.channels[0].directURL?.absoluteString == "http://h.example:8080/live/u/p/1.ts")
    }

    @Test func titleCommaInsideQuotedAttributeIsNotTheSeparator() {
        let info = M3UParser.parseInfo(#"#EXTINF:-1 tvg-name="A, B" group-title="G",Real, Title"#)
        #expect(info.title == "Real, Title")
        #expect(info.attributes["tvg-name"] == "A, B")
    }
}

struct BrowseIndexTests {
    private func movie(_ id: String, _ name: String, category: String, rating: Double? = nil, added: TimeInterval = 0) -> Movie {
        Movie(id: id, name: name, poster: nil, categoryID: category, rating: rating,
              added: Date(timeIntervalSince1970: added), containerExtension: nil, directURL: nil)
    }

    private var index: BrowseIndex<Movie> {
        BrowseIndex([
            movie("1", "The Batman", category: "a", rating: 7.8, added: 300),
            movie("2", "Amélie", category: "b", rating: 8.3, added: 100),
            movie("3", "Batman Begins", category: "a", rating: nil, added: 200),
        ])
    }

    @Test func countsAndFiltersByCategory() {
        #expect(index.count(in: "a") == 2)
        #expect(index.count(in: "missing") == 0)
        #expect(index.select(category: "b").map(\.id) == ["2"])
        #expect(index.select(category: nil).count == 3)
    }

    @Test func searchIsAccentAndCaseInsensitiveAndMultiTerm() {
        #expect(index.select(category: nil, query: "amelie").map(\.id) == ["2"])
        #expect(index.select(category: nil, query: "BATMAN").map(\.id) == ["1", "3"])
        #expect(index.select(category: nil, query: "batman begins").map(\.id) == ["3"])
    }

    @Test func sortsAndRestrictsToIDs() {
        #expect(index.select(category: nil, sort: .title).map(\.id) == ["2", "3", "1"])
        #expect(index.select(category: nil, sort: .rating).map(\.id) == ["2", "1", "3"])
        #expect(index.select(category: nil, sort: .recentlyAdded).map(\.id) == ["1", "3", "2"])
        #expect(index.select(category: nil, ids: ["3", "2"]).map(\.id) == ["2", "3"])
        #expect(index.item(id: "3")?.name == "Batman Begins")
    }
}

struct LibraryStateTests {
    private let playlist = UUID()

    private func item(_ id: String, kind: ContentKind = .movie, parent: String? = nil) -> PlaybackItem {
        PlaybackItem(id: id, kind: kind, title: id, url: URL(string: "http://h/\(id)")!, parentID: parent)
    }

    @Test func progressThresholds() {
        let base = item("m")
        #expect(!WatchProgress(item: base, position: 10, duration: 6000).isResumable)
        #expect(WatchProgress(item: base, position: 600, duration: 6000).isResumable)
        #expect(WatchProgress(item: base, position: 5800, duration: 6000).isFinished)
        #expect(WatchProgress(item: base, position: 3000, duration: 6000).fraction == 0.5)
    }

    @Test func continueWatchingIsScopedSortedAndCollapsesSeries() {
        var state = LibraryState()
        let key = { (id: String, kind: ContentKind) in ContentKey.make(playlist: self.playlist, kind: kind, id: id) }
        state.recordProgress(key: key("m1", .movie), item: item("m1"), position: 600, duration: 6000, at: Date(timeIntervalSince1970: 1))
        state.recordProgress(key: key("e1", .episode), item: item("e1", kind: .episode, parent: "s"), position: 300, duration: 2400, at: Date(timeIntervalSince1970: 2))
        state.recordProgress(key: key("e2", .episode), item: item("e2", kind: .episode, parent: "s"), position: 300, duration: 2400, at: Date(timeIntervalSince1970: 3))
        state.recordProgress(key: key("done", .movie), item: item("done"), position: 5990, duration: 6000)
        state.recordProgress(key: ContentKey.make(playlist: UUID(), kind: .movie, id: "x"), item: item("x"), position: 600, duration: 6000)

        #expect(state.continueWatching(playlist: playlist).map(\.item.id) == ["e2", "m1"])
    }

    @Test func favoritesToggleAndScope() {
        var state = LibraryState()
        let key = ContentKey.make(playlist: playlist, kind: .live, id: "42")
        state.toggleFavorite(key)
        #expect(state.favoriteIDs(playlist: playlist, kind: .live) == ["42"])
        #expect(state.favoriteIDs(playlist: playlist, kind: .movie).isEmpty)
        state.toggleFavorite(key)
        #expect(state.favorites.isEmpty)
    }

    @Test func recentChannelsDedupeAndCap() {
        var state = LibraryState()
        for index in 0..<40 { state.recordChannel(key: "k\(index)") }
        state.recordChannel(key: "k5")
        #expect(state.recentChannels.first == "k5")
        #expect(state.recentChannels.count == LibraryState.recentChannelLimit)
        #expect(state.recentChannels.filter { $0 == "k5" }.count == 1)
    }

    @Test func removeAllClearsOnlyThatPlaylist() {
        var state = LibraryState()
        let other = UUID()
        state.toggleFavorite(ContentKey.make(playlist: playlist, kind: .movie, id: "1"))
        state.toggleFavorite(ContentKey.make(playlist: other, kind: .movie, id: "1"))
        state.removeAll(playlist: playlist)
        #expect(state.favorites == [ContentKey.make(playlist: other, kind: .movie, id: "1")])
    }

    @Test func catalogStaleness() {
        let catalog = Catalog(fetchedAt: Date(timeIntervalSince1970: 0), liveCategories: [], vodCategories: [],
                              seriesCategories: [], channels: [], movies: [], series: [])
        #expect(catalog.isStale(maxAge: 60, now: Date(timeIntervalSince1970: 61)))
        #expect(!catalog.isStale(maxAge: 60, now: Date(timeIntervalSince1970: 59)))
    }
}

struct SecretStoreTests {
    @Test func storesSecretsInUserOnlyFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-secrets-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = SecretStore(url: url)
        store.set("pw1", for: "a")
        store.set("pw2", for: "b")
        store.remove("a")
        #expect(store.get("a") == nil)
        #expect(store.get("b") == "pw2")
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)
    }
}

struct VideoQualityTests {
    @Test(arguments: [
        (3840, 2160, "4K"), (3840, 1600, "4K"), (2560, 1440, "1440p"), (1920, 1080, "1080p"),
        (1920, 800, "1080p"), (1280, 720, "720p"), (1280, 534, "720p"), (720, 576, "SD"), (640, 360, "SD"),
    ])
    func labels(width: Int, height: Int, expected: String) {
        #expect(VideoQuality.label(width: width, height: height) == expected)
    }

    @Test func rejectsUnknownSizeAndFormatsBitrate() {
        #expect(VideoQuality.label(width: 0, height: 1080) == nil)
        #expect(VideoQuality.bitrate(4_200_000) == "4.2 Mbps")
        #expect(VideoQuality.bitrate(640_000) == "640 kbps")
    }
}

struct CategoryAndHistoryTests {
    private let playlist = UUID()

    private func item(_ id: String, kind: ContentKind = .movie, parent: String? = nil) -> PlaybackItem {
        PlaybackItem(id: id, kind: kind, title: id, url: URL(string: "http://h/\(id)")!, parentID: parent)
    }

    @Test func pinHashVerifiesAndRemovalClearsLocks() {
        var state = LibraryState()
        #expect(!state.hasPIN)
        #expect(!state.verifyPIN("1234"))
        state.setPIN("1234")
        #expect(state.verifyPIN("1234"))
        #expect(!state.verifyPIN("4321"))
        state.setLocked("k", true)
        state.removePIN()
        #expect(!state.hasPIN)
        #expect(state.lockedCategories.isEmpty)
    }

    @Test func pinValidation() {
        #expect(LibraryState.isValidPIN("1234"))
        #expect(LibraryState.isValidPIN("12345678"))
        #expect(!LibraryState.isValidPIN("123"))
        #expect(!LibraryState.isValidPIN("12a4"))
        #expect(!LibraryState.isValidPIN("123456789"))
    }

    @Test func hidePinAndCategoryIDs() {
        var state = LibraryState()
        let key = ContentKey.category(playlist: playlist, kind: .live, id: "104")
        state.toggleHidden(key)
        state.togglePinned(key)
        let prefix = ContentKey.categoryPrefix(playlist: playlist, kind: .live)
        #expect(LibraryState.ids(in: state.hiddenCategories, prefix: prefix) == ["104"])
        #expect(LibraryState.ids(in: state.pinnedCategories, prefix: ContentKey.categoryPrefix(playlist: playlist, kind: .movie)).isEmpty)
        state.toggleHidden(key)
        state.togglePinned(key)
        #expect(state.hiddenCategories.isEmpty && state.pinnedCategories.isEmpty)
    }

    @Test func removingEpisodeFromContinueWatchingClearsWholeSeriesButKeepsWatched() {
        var state = LibraryState()
        let key = { (id: String) in ContentKey.make(playlist: self.playlist, kind: .episode, id: id) }
        state.recordProgress(key: key("e1"), item: item("e1", kind: .episode, parent: "s"), position: 300, duration: 2400)
        state.recordProgress(key: key("e2"), item: item("e2", kind: .episode, parent: "s"), position: 600, duration: 2400)
        state.markWatched(key: key("e0"), item: item("e0", kind: .episode, parent: "s"), duration: 2400)
        state.recordProgress(key: key("x1"), item: item("x1", kind: .episode, parent: "other"), position: 300, duration: 2400)

        state.removeFromContinueWatching(key: key("e2"))
        #expect(state.progress[key("e1")] == nil)
        #expect(state.progress[key("e2")] == nil)
        #expect(state.progress[key("e0")]?.isFinished == true)
        #expect(state.continueWatching(playlist: playlist).map(\.item.id) == ["x1"])
    }

    @Test func markWatchedAndUnwatched() {
        var state = LibraryState()
        let key = ContentKey.make(playlist: playlist, kind: .movie, id: "m")
        state.markWatched(key: key, item: item("m"), duration: nil)
        #expect(state.progress[key]?.isFinished == true)
        #expect(state.continueWatching(playlist: playlist).isEmpty)
        state.markUnwatched(key: key)
        #expect(state.progress[key] == nil)
    }

    @Test func clearingHistoryIsScopedAndKeepsWatchedMarks() {
        var state = LibraryState()
        let other = UUID()
        state.recordProgress(key: ContentKey.make(playlist: playlist, kind: .movie, id: "a"), item: item("a"), position: 600, duration: 6000)
        state.markWatched(key: ContentKey.make(playlist: playlist, kind: .movie, id: "b"), item: item("b"), duration: 100)
        state.recordProgress(key: ContentKey.make(playlist: other, kind: .movie, id: "c"), item: item("c"), position: 600, duration: 6000)
        state.recordChannel(key: ContentKey.make(playlist: playlist, kind: .live, id: "1"))
        state.recordChannel(key: ContentKey.make(playlist: other, kind: .live, id: "2"))

        state.clearContinueWatching(playlist: playlist)
        state.clearRecentChannels(playlist: playlist)
        #expect(state.continueWatching(playlist: playlist).isEmpty)
        #expect(state.progress[ContentKey.make(playlist: playlist, kind: .movie, id: "b")] != nil)
        #expect(state.continueWatching(playlist: other).count == 1)
        #expect(state.recentChannels == [ContentKey.make(playlist: other, kind: .live, id: "2")])

        state.removeRecentChannel(ContentKey.make(playlist: other, kind: .live, id: "2"))
        #expect(state.recentChannels.isEmpty)
    }

    @Test func decodesLegacyLibraryWithoutNewFields() throws {
        let legacy = #"{"favorites":["a"],"progress":{},"recentChannels":["r"]}"#
        let state = try JSONDecoder().decode(LibraryState.self, from: Data(legacy.utf8))
        #expect(state.favorites == ["a"])
        #expect(state.hiddenCategories.isEmpty && !state.hasPIN)
    }

    @Test func excludedCategoriesAreFilteredOut() {
        let movies = [
            Movie(id: "1", name: "A", poster: nil, categoryID: "kids", rating: nil, added: nil, containerExtension: nil, directURL: nil),
            Movie(id: "2", name: "B", poster: nil, categoryID: "adult", rating: nil, added: nil, containerExtension: nil, directURL: nil),
            Movie(id: "3", name: "C", poster: nil, categoryID: nil, rating: nil, added: nil, containerExtension: nil, directURL: nil),
        ]
        let index = BrowseIndex(movies)
        #expect(index.select(category: nil, excludedCategories: ["adult"]).map(\.id) == ["1", "3"])
        #expect(index.select(category: nil, query: "b", excludedCategories: ["adult"]).isEmpty)
    }
}
