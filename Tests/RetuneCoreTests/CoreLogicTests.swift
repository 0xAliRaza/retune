import Foundation
import os
import Testing
@testable import RetuneCore

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

    @Test(arguments: [
        ("http://iptv.example:8080", true),
        ("HTTP://iptv.example", true),
        ("iptv.example:8080", true),
        ("http://iptv.example/get.php?username=a&password=b", true),
        ("https://iptv.example", false),
        ("", false),
    ])
    func flagsPlainHTTPAddresses(input: String, expected: Bool) {
        #expect(XtreamCredentials.usesPlainHTTP(input) == expected)
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
    private func store() -> SecretStore { SecretStore(service: "retune.tests.\(UUID().uuidString)") }

    @Test func storesUpdatesAndRemovesKeychainItems() throws {
        let store = store()
        defer { store.remove("a"); store.remove("b") }
        try store.set("pw1", for: "a")
        try store.set("pw1-changed", for: "a")
        try store.set("pw2", for: "b")
        #expect(store.get("a") == "pw1-changed")
        store.remove("a")
        #expect(store.get("a") == nil)
        #expect(store.get("b") == "pw2")
    }

    @Test func migratesLegacyFileThenDeletesIt() throws {
        let store = store()
        defer { store.remove("a") }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("retune-legacy-\(UUID().uuidString).json")
        try JSONFileStore<[String: String]>(url: file).save(["a": "old-password"])
        store.migrateLegacyFile(at: file)
        #expect(store.get("a") == "old-password")
        #expect(!FileManager.default.fileExists(atPath: file.path))
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

struct QueueWindowTests {
    @Test func smallListsAreQueuedWhole() {
        #expect(QueueWindow.range(count: 10, around: 3, size: 500) == 0..<10)
    }

    @Test func largeListsAreWindowedAroundTheSelection() {
        #expect(QueueWindow.range(count: 1000, around: 500, size: 100) == 450..<550)
        #expect(QueueWindow.range(count: 1000, around: 5, size: 100) == 0..<100)
        #expect(QueueWindow.range(count: 1000, around: 990, size: 100) == 900..<1000)
    }
}

struct QueueNavigationTests {
    private func item(_ id: String, kind: ContentKind, parent: String? = nil) -> PlaybackItem {
        PlaybackItem(id: id, kind: kind, title: id, url: URL(string: "http://h/\(id)")!, parentID: parent)
    }

    @Test func liveWrapsOnDemandStops() {
        #expect(QueueNavigation.target(from: 0, delta: -1, count: 5, wraps: true) == 4)
        #expect(QueueNavigation.target(from: 4, delta: 1, count: 5, wraps: true) == 0)
        #expect(QueueNavigation.target(from: 0, delta: -1, count: 5, wraps: false) == nil)
        #expect(QueueNavigation.target(from: 4, delta: 1, count: 5, wraps: false) == nil)
        #expect(QueueNavigation.target(from: 2, delta: 1, count: 5, wraps: false) == 3)
        #expect(QueueNavigation.target(from: 0, delta: 1, count: 0, wraps: true) == nil)
    }

    @Test func autoplayOnlyWithinSameSeries() {
        let a1 = item("a1", kind: .episode, parent: "A"), a2 = item("a2", kind: .episode, parent: "A")
        let b1 = item("b1", kind: .episode, parent: "B"), movie = item("m", kind: .movie)
        #expect(QueueNavigation.shouldAutoplay(after: a1, next: a2, enabled: true))
        #expect(!QueueNavigation.shouldAutoplay(after: a1, next: a2, enabled: false))
        #expect(!QueueNavigation.shouldAutoplay(after: a1, next: b1, enabled: true))
        #expect(!QueueNavigation.shouldAutoplay(after: movie, next: item("m2", kind: .movie), enabled: true))
        #expect(!QueueNavigation.shouldAutoplay(after: a1, next: nil, enabled: true))
        #expect(!QueueNavigation.shouldAutoplay(after: item("x", kind: .episode), next: item("y", kind: .episode), enabled: true))
    }

    @Test func buildKeepsSelectionAlignedWhenItemsAreSkipped() throws {
        let source = ["a", "skip", "b", "c"]
        let make = { (id: String) in id == "skip" ? nil : self.item(id, kind: .movie) }
        let built = try #require(QueueNavigation.build(source, selected: 2, make: make))
        #expect(built.items.map(\.id) == ["a", "b", "c"])
        #expect(built.items[built.index].id == "b")
        #expect(QueueNavigation.build(source, selected: 1, make: make) == nil)
    }
}

struct SubtitleStyleTests {
    @Test func defaultsForceReadableStyle() {
        let options = Dictionary(uniqueKeysWithValues: SubtitleStyle().mpvOptions)
        #expect(options["sub-ass-override"] == "strip")
        #expect(options["sub-border-style"] == "outline-and-shadow")
        #expect(options["sub-scale"] == "1.0")
        #expect(options["sub-pos"] == "100.0")
    }

    @Test func keepingOriginalStyleAndBackgroundMapToMpv() {
        var style = SubtitleStyle()
        style.keepsOriginalStyle = true
        style.background = true
        let options = Dictionary(uniqueKeysWithValues: style.mpvOptions)
        #expect(options["sub-ass-override"] == "scale")
        #expect(options["sub-border-style"] == "background-box")
    }

    @Test func clampRoundsAndBounds() {
        var style = SubtitleStyle()
        style.scale = 9
        style.position = 10
        style.clamp()
        #expect(style.scale == SubtitleStyle.scaleRange.upperBound)
        #expect(style.position == SubtitleStyle.positionRange.lowerBound)
        style.scale = 1.24
        style.position = 87.6
        style.clamp()
        #expect(style.scale == 1.2)
        #expect(style.position == 88)
    }
}

struct EpisodePickerTests {
    private func progress(_ position: Double, at time: TimeInterval) -> WatchProgress {
        WatchProgress(item: PlaybackItem(id: "e", kind: .episode, title: "e", url: URL(string: "http://h/e")!),
                      position: position, duration: 2400, updatedAt: Date(timeIntervalSince1970: time))
    }

    @Test func startsAtFirstWhenNothingWatched() {
        #expect(EpisodePicker.pick(count: 5) { _ in nil } == .start(0))
        #expect(EpisodePicker.pick(count: 0) { _ in nil } == nil)
    }

    @Test func resumesInProgressEpisode() {
        let saved = [2: progress(600, at: 10)]
        #expect(EpisodePicker.pick(count: 5) { saved[$0] } == .resume(2))
    }

    @Test func offersNextAfterFinishedEpisode() {
        let saved = [0: progress(2400, at: 1), 1: progress(2400, at: 2)]
        #expect(EpisodePicker.pick(count: 5) { saved[$0] } == .next(2))
    }

    @Test func latestActivityWins() {
        // Finished E4 after abandoning E2 part-way: go on to E5, not back to E2.
        let saved = [1: progress(600, at: 1), 3: progress(2400, at: 5)]
        #expect(EpisodePicker.pick(count: 6) { saved[$0] } == .next(4))
        // Started E2 again after finishing E4: resume E2.
        let rewatch = [1: progress(600, at: 9), 3: progress(2400, at: 5)]
        #expect(EpisodePicker.pick(count: 6) { rewatch[$0] } == .resume(1))
    }

    @Test func finishedSeriesStartsOver() {
        let saved = [2: progress(2400, at: 3)]
        #expect(EpisodePicker.pick(count: 3) { saved[$0] } == .start(0))
    }

    @Test func barelyStartedEpisodeIsIgnored() {
        let saved = [3: progress(10, at: 9)]
        #expect(EpisodePicker.pick(count: 5) { saved[$0] } == .start(0))
    }
}

struct GridNavigationTests {
    @Test func columnsMatchAdaptiveLayout() {
        #expect(GridNavigation.columns(width: 1000, minimum: 150, spacing: 20) == 6)
        #expect(GridNavigation.columns(width: 999, minimum: 150, spacing: 20) == 5)
        #expect(GridNavigation.columns(width: 100, minimum: 150, spacing: 20) == 1)
    }

    @Test func movesWithinGrid() {
        // 4 columns, 10 items: rows [0-3] [4-7] [8-9]
        #expect(GridNavigation.move(from: nil, .down, columns: 4, count: 10) == 0)
        #expect(GridNavigation.move(from: 5, .right, columns: 4, count: 10) == 6)
        #expect(GridNavigation.move(from: 5, .left, columns: 4, count: 10) == 4)
        #expect(GridNavigation.move(from: 5, .up, columns: 4, count: 10) == 1)
        #expect(GridNavigation.move(from: 1, .up, columns: 4, count: 10) == 1)
        #expect(GridNavigation.move(from: 5, .down, columns: 4, count: 10) == 9)
        #expect(GridNavigation.move(from: 4, .down, columns: 4, count: 10) == 8)
        #expect(GridNavigation.move(from: 9, .down, columns: 4, count: 10) == 9)
        #expect(GridNavigation.move(from: 0, .left, columns: 4, count: 10) == 0)
        #expect(GridNavigation.move(from: 9, .right, columns: 4, count: 10) == 9)
        #expect(GridNavigation.move(from: 0, .down, columns: 4, count: 0) == nil)
    }
}

struct ReviewHardeningTests {
    @Test func lenientIntRejectsNonFiniteAndHugeValues() throws {
        let json = #"[{"num":"nan","name":"A","stream_id":1},{"num":1e300,"name":"B","stream_id":2},{"num":"inf","name":"C","stream_id":3}]"#
        let channels = try JSONDecoder().decode([Failable<XtreamLiveDTO>].self, from: Data(json.utf8)).compactMap(\.value?.channel)
        #expect(channels.count == 3)
        #expect(channels.allSatisfy { $0.number == nil })
    }

    @Test func runtimeOverflowDoesNotTrap() throws {
        let json = #"{"info":{"episode_run_time":"9223372036854775807"},"seasons":[],"episodes":{}}"#
        let detail = try JSONDecoder().decode(XtreamSeriesInfoResponse.self, from: Data(json.utf8)).detail
        #expect(detail.info.durationSeconds == nil)
    }

    @Test func slashInCredentialsIsEscapedInStreamURLs() {
        let client = XtreamClient(credentials: XtreamCredentials(server: URL(string: "http://h.example:8080")!, username: "u/1", password: "a/b"))
        #expect(client.liveURL(streamID: "7").absoluteString == "http://h.example:8080/live/u%2F1/a%2Fb/7.ts")
    }

    @Test func locatorsStripCredentialsAndResolveBack() throws {
        let client = XtreamClient(credentials: XtreamCredentials(server: URL(string: "http://h.example:8080")!, username: "u", password: "secret"))
        let movie = Movie(id: "9", name: "M", poster: nil, categoryID: nil, rating: nil, added: nil, containerExtension: "mkv", directURL: nil)
        let real = client.movieURL(movie)
        let locator = try #require(XtreamClient.locator(for: real))
        #expect(locator.absoluteString == "retune://movie/9.mkv")
        #expect(!locator.absoluteString.contains("secret"))
        #expect(client.resolve(locator) == real)
        let other = URL(string: "https://cdn.example/file.mp4")!
        #expect(XtreamClient.locator(for: other) == nil)
        #expect(client.resolve(other) == other)
    }

    @Test func sanitizeRewritesStoredStreamURLs() {
        var state = LibraryState()
        let url = URL(string: "http://h.example:8080/series/u/secret/42.mkv")!
        state.recordProgress(key: "k", item: PlaybackItem(id: "42", kind: .episode, title: "E", url: url), position: 100, duration: 1000)
        let firstPass = state.sanitizeStreamURLs()
        let secondPass = state.sanitizeStreamURLs()
        #expect(firstPass)
        #expect(state.progress["k"]?.item.url.absoluteString == "retune://series/42.mkv")
        #expect(!secondPass)
    }

    @Test func pruningKeepsWatchedMarksOverInProgress() {
        var state = LibraryState()
        let item = PlaybackItem(id: "x", kind: .movie, title: "x", url: URL(string: "http://h/x")!)
        state.markWatched(key: "watched-old", item: item, duration: 100)
        for index in 0..<LibraryState.progressLimit {
            state.recordProgress(key: "p\(index)", item: item, position: 50, duration: 100,
                                 at: Date(timeIntervalSince1970: TimeInterval(index + 10)))
        }
        #expect(state.progress.count == LibraryState.progressLimit)
        #expect(state.progress["watched-old"] != nil)
        #expect(state.progress["p0"] == nil)
    }

    @Test func libraryDecodingSkipsOneBadProgressEntry() throws {
        let json = """
        {"favorites":[],"recentChannels":[],"progress":{
          "good":{"item":{"id":"1","kind":"movie","title":"A","url":"http://h/1"},"position":10,"duration":100,"updatedAt":0},
          "bad":{"item":{"id":"2","kind":"hologram","title":"B","url":"http://h/2"},"position":10,"duration":100,"updatedAt":0}}}
        """
        let state = try JSONDecoder().decode(LibraryState.self, from: Data(json.utf8))
        #expect(state.progress.keys.sorted() == ["good"])
    }

    @Test func corruptStoreIsBackedUpNotOverwritten() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("retune-store-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("library.json")
        try Data("{not json".utf8).write(to: url)
        let store = JSONFileStore<[String: String]>(url: url)
        #expect(store.load() == nil)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(files.contains { $0.hasPrefix("library.json.corrupt-") })
        try Data("{}".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        try store.save(["a": "b"])
        #expect(store.load() == ["a": "b"])
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)
    }

    @Test func m3uDuplicateURLsAreDropped() {
        let text = """
        #EXTM3U
        #EXTINF:-1 group-title="A",One
        http://h/1.ts
        #EXTINF:-1 group-title="A",One again
        http://h/1.ts
        """
        #expect(M3UParser.catalog(from: M3UParser.parse(text)).channels.map(\.name) == ["One"])
    }
}

/// Serves canned responses so XtreamClient's retry rules can be tested without a network.
final class StubProtocol: URLProtocol, @unchecked Sendable {
    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: configuration)
    }

    nonisolated(unsafe) static var responses: [(Int, Data)] = []
    nonisolated(unsafe) static var requests = 0

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let (status, body) = Self.responses.isEmpty ? (200, Data()) : Self.responses.removeFirst()
        Self.requests += 1
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized)
struct XtreamRetryTests {
    private func client() -> XtreamClient {
        XtreamClient(credentials: XtreamCredentials(server: URL(string: "http://h.example")!, username: "u", password: "p"),
                     session: StubProtocol.session())
    }

    @Test func emptyBodyIsRetriedThenSucceeds() async throws {
        StubProtocol.requests = 0
        StubProtocol.responses = [(200, Data()), (222, Data()), (200, Data(#"[{"category_id":"1","category_name":"News"}]"#.utf8))]
        let categories = try await client().categories(.live)
        #expect(categories.map(\.name) == ["News"])
        #expect(StubProtocol.requests == 3)
    }

    @Test func persistentEmptyBodyIsAnErrorNotAnEmptySection() async {
        StubProtocol.responses = [(200, Data()), (200, Data()), (200, Data())]
        await #expect(throws: RetuneError.emptyResponse) { try await client().movies() }
    }

    @Test func oversizedResponsesAreCutOff() async {
        StubProtocol.responses = [(200, Data(repeating: 0, count: 2048))]
        let session = StubProtocol.session()
        await #expect(throws: RetuneError.responseTooLarge) {
            _ = try await session.boundedData(from: URL(string: "http://stub.example/big")!, limit: 1024)
        }
    }

    @Test func boundedDataReturnsNormalBodies() async throws {
        StubProtocol.responses = [(200, Data("hello".utf8))]
        let (data, _) = try await StubProtocol.session().boundedData(from: URL(string: "http://stub.example/ok")!, limit: 1024)
        #expect(data == Data("hello".utf8))
    }

    @Test func emptyArrayIsAGenuinelyEmptySection() async throws {
        StubProtocol.responses = [(200, Data("[]".utf8))]
        #expect(try await client().series().isEmpty)
    }
}

struct PaneNavigationTests {
    private func action(_ key: PaneNavigation.Key, _ pane: PaneNavigation.Pane, grid: Bool = false, detail: Bool = false) -> PaneNavigation.Action {
        PaneNavigation.action(for: key, in: pane, contentHandlesHorizontal: grid, showingDetail: detail)
    }

    @Test func movesForwardThroughColumns() {
        #expect(action(.tab, .sidebar) == .focus(.categories))
        #expect(action(.right, .sidebar) == .focus(.categories))
        #expect(action(.enter, .sidebar) == .focus(.categories))
        #expect(action(.tab, .categories) == .focus(.content))
        #expect(action(.enter, .categories) == .focus(.content))
        #expect(action(.tab, .content) == .focus(.sidebar))
    }

    @Test func movesBackThroughColumns() {
        #expect(action(.left, .categories) == .focus(.sidebar))
        #expect(action(.escape, .categories) == .focus(.sidebar))
        #expect(action(.backTab, .content) == .focus(.categories))
        #expect(action(.escape, .content) == .focus(.categories))
        #expect(action(.left, .content) == .focus(.categories))
    }

    @Test func contentKeepsItsOwnKeys() {
        #expect(action(.left, .content, grid: true) == .passThrough)
        #expect(action(.enter, .content) == .passThrough)
        #expect(action(.right, .content) == .passThrough)
    }

    @Test func detailPageEscapeGoesBack() {
        #expect(action(.escape, .content, detail: true) == .goBack)
        #expect(action(.left, .content, detail: true) == .passThrough)
    }
}

struct GridEdgeTests {
    @Test func detectsTopRowAndFirstColumn() {
        #expect(GridNavigation.isAtEdge(2, .up, columns: 4))
        #expect(!GridNavigation.isAtEdge(5, .up, columns: 4))
        #expect(GridNavigation.isAtEdge(4, .left, columns: 4))
        #expect(!GridNavigation.isAtEdge(5, .left, columns: 4))
        #expect(!GridNavigation.isAtEdge(0, .down, columns: 4))
    }
}

struct ReconnectPolicyTests {
    @Test func backsOffThenGivesUp() {
        #expect(ReconnectPolicy.delay(afterFailedAttempts: 0) == .seconds(1))
        #expect(ReconnectPolicy.delay(afterFailedAttempts: 3) == .seconds(6))
        #expect(ReconnectPolicy.delay(afterFailedAttempts: ReconnectPolicy.maxAttempts) == nil)
        let total = ReconnectPolicy.delays.reduce(Duration.zero, +)
        #expect(total >= .seconds(10))
    }
}

/// The replay bug: FFmpeg reconnecting inside a live stream spliced whatever the server sent next
/// (often minutes old) into the running playback, and hid the failure from `PlaybackSession`.
struct StreamProfileTests {
    private func value(_ profile: StreamProfile, _ name: String) -> String? {
        profile.mpvProperties.first { $0.name == name }?.value
    }

    @Test func liveNeverReconnectsInsideFFmpeg() {
        #expect(value(.live, "stream-lavf-o") == "")
        #expect(value(.live, "demuxer-max-back-bytes") == "0")
        #expect(value(.live, "demuxer-seekable-cache") == "no")
    }

    @Test func onDemandNeverRestartsAnUnseekableFile() throws {
        let options = try #require(value(.onDemand, "stream-lavf-o"))
        #expect(options.contains("reconnect=1"))
        #expect(!options.contains("reconnect_streamed"))
    }

    @Test func bothProfilesSetTheSameProperties() {
        // mpv keeps properties across files, so anything set for one profile must be reset by the other.
        #expect(StreamProfile.live.mpvProperties.map(\.name) == StreamProfile.onDemand.mpvProperties.map(\.name))
    }
}

struct UntrustedInputTests {
    @Test(arguments: [
        "av://lavfi:testsrc,vmafmotion@h=/Users/x/.zshrc", "file:///etc/passwd", "edl://a.mkv", "memory://x",
        "fd://3", "lavf://x", "javascript:alert(1)", "/etc/passwd", "httpx://host/a",
    ])
    func rejectsLocalAndSpecialProtocols(_ raw: String) throws {
        let url = URL(string: raw)
        #expect(url.map(StreamURLPolicy.isAllowed) != true)
        #expect(M3UParser.parse("#EXTM3U\n#EXTINF:-1,Evil\n\(raw)\n").isEmpty)
    }

    @Test(arguments: ["http://h.example/a.ts", "HTTPS://h.example/a.m3u8", "rtmp://h.example/live", "rtsp://h.example/s", "udp://@239.0.0.1:1234"])
    func acceptsNetworkStreams(_ raw: String) throws {
        #expect(StreamURLPolicy.isAllowed(try #require(URL(string: raw))))
    }

    @Test func lenientURLRejectsHTTPLookalikes() {
        #expect(URL(lenient: "httpx://host/a.png") == nil)
        #expect(URL(lenient: "https://host/a.png") != nil)
    }

    @Test func absurdEPGTimestampsAreDiscarded() throws {
        struct Holder: Decodable {
            let date: Date?
            enum CodingKeys: String, CodingKey { case stop }
            init(from decoder: Decoder) throws { date = try decoder.container(keyedBy: CodingKeys.self).lenientDate(.stop) }
        }
        #expect(try JSONDecoder().decode(Holder.self, from: Data(#"{"stop":1e21}"#.utf8)).date == nil)
        #expect(try JSONDecoder().decode(Holder.self, from: Data(#"{"stop":1700000000}"#.utf8)).date != nil)
    }

    @Test func implausibleDurationsAreNotSaved() {
        var state = LibraryState()
        let item = PlaybackItem(id: "x", kind: .movie, title: "x", url: URL(string: "http://h/x")!)
        state.recordProgress(key: "k", item: item, position: 10, duration: 9e18)
        #expect(state.progress["k"] == nil)
    }
}

struct CredentialHygieneTests {
    @Test func apiSessionNeverPersistsRequests() {
        let configuration = URLSession.retuneAPI.configuration
        #expect(configuration.urlCache == nil)
        #expect(configuration.httpCookieStorage == nil)
    }

    @Test func plusInPasswordSurvivesPHPQueryParsing() throws {
        let client = XtreamClient(credentials: XtreamCredentials(server: URL(string: "http://h.example")!, username: "u", password: "ab+c&d=e"))
        let query = try #require(client.apiURL(action: nil).query(percentEncoded: true))
        #expect(query.contains("password=ab%2Bc%26d%3De"))
    }

    @Test func slashInPasswordStillProducesACredentialFreeLocator() throws {
        let client = XtreamClient(credentials: XtreamCredentials(server: URL(string: "http://h.example")!, username: "u", password: "a/b"))
        let movie = Movie(id: "9", name: "M", poster: nil, categoryID: nil, rating: nil, added: nil, containerExtension: "mkv", directURL: nil)
        let locator = try #require(XtreamClient.locator(for: client.movieURL(movie)))
        #expect(locator.absoluteString == "retune://movie/9.mkv")
    }

    @Test func m3uIDsNeverContainTheStreamURL() {
        let text = "#EXTM3U\n#EXTINF:-1,Channel\nhttp://h.example/live/user/secret/1.ts\n"
        let channel = M3UParser.catalog(from: M3UParser.parse(text)).channels[0]
        #expect(!channel.id.contains("secret"))
        #expect(channel.directURL?.absoluteString.contains("secret") == true)
        #expect(XtreamClient.opaqueLocator(id: channel.id)?.absoluteString.contains("secret") == false)
    }

    @Test func restrictPermissionsTightensExistingFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("retune-perms-\(UUID().uuidString)")
        let nested = root.appendingPathComponent("Catalogs")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        let file = root.appendingPathComponent("playlists.json")
        try Data("[]".utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)

        AppPaths.restrictPermissions(root: root)

        func mode(_ url: URL) throws -> Int? { try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int }
        #expect(try mode(root) == 0o700)
        #expect(try mode(nested) == 0o700)
        #expect(try mode(file) == 0o600)
    }

    @Test func purgeRemovesOnlyThisAppsNetworkCaches() throws {
        let library = FileManager.default.temporaryDirectory.appendingPathComponent("retune-lib-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: library) }
        let ours = library.appendingPathComponent("Caches/app.test")
        let other = library.appendingPathComponent("Caches/Retune/Artwork")
        try FileManager.default.createDirectory(at: ours, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)

        AppPaths.purgeNetworkCaches(bundleID: nil, library: library)
        #expect(FileManager.default.fileExists(atPath: ours.path))

        AppPaths.purgeNetworkCaches(bundleID: "app.test", library: library)
        #expect(!FileManager.default.fileExists(atPath: ours.path))
        #expect(FileManager.default.fileExists(atPath: other.path))
    }
}

struct PINHashTests {
    @Test func saltsEveryHashAndRejectsWrongPINs() {
        let first = PINHash.make("1234"), second = PINHash.make("1234")
        #expect(first != second)
        #expect(first.hasPrefix("pbkdf2-sha256$"))
        #expect(PINHash.verify("1234", against: first))
        #expect(!PINHash.verify("1235", against: first))
    }

    @Test func legacyHashesStillVerifyAndAreFlaggedForUpgrade() {
        let legacy = PINHash.legacyHash("1234")
        #expect(PINHash.isLegacy(legacy))
        #expect(PINHash.verify("1234", against: legacy))
        #expect(!PINHash.verify("0000", against: legacy))
    }

    @Test func malformedStoredValuesNeverVerify() {
        #expect(!PINHash.verify("1234", against: "pbkdf2-sha256$0$00$00"))
        #expect(!PINHash.verify("1234", against: "pbkdf2-sha256$x$y$z"))
    }
}

@Suite struct ScreenshotFileTests {
    @Test func namesFilesFromTheTimeInTheChosenFolder() throws {
        let folder = URL(fileURLWithPath: "/tmp/shots", isDirectory: true)
        let zone = try #require(TimeZone(secondsFromGMT: 0))
        let url = ScreenshotFile.url(in: folder, date: Date(timeIntervalSince1970: 0), timeZone: zone)
        #expect(url.path == "/tmp/shots/Retune 1970-01-01 at 00.00.00.000.png")
    }

    @Test func flipsRowsTopToBottomAndKeepsPixelOrder() {
        #expect(ScreenshotFile.flippedRows([1, 2, 3, 4, 5, 6], bytesPerRow: 2) == [5, 6, 3, 4, 1, 2])
    }

    @Test func flippingSurvivesEmptyInput() {
        #expect(ScreenshotFile.flippedRows([], bytesPerRow: 4).isEmpty)
        #expect(ScreenshotFile.flippedRows([1, 2], bytesPerRow: 0).isEmpty)
    }
}

@Suite struct CredentialFreeItemTests {
    private func item(_ url: String, id: String = "42") -> PlaybackItem {
        PlaybackItem(id: id, kind: .movie, title: "Film", url: URL(string: url)!)
    }

    @Test func xtreamItemsKeepOnlyALocator() throws {
        let stored = try #require(item("http://host/movie/user/secret/42.mp4").credentialFree(hasAccount: true))
        #expect(stored.url.absoluteString == "retune://movie/42.mp4")
    }

    @Test func playlistEntriesKeepOnlyTheirID() throws {
        let stored = try #require(item("http://host/get?user=me&password=secret").credentialFree(hasAccount: false))
        #expect(stored.url.absoluteString == "retune://item/42")
    }

    /// An address the locator can't parse must not reach history, because it may hold the password.
    @Test func unrecognizedAccountURLsAreNeverStored() {
        #expect(item("http://host/get.php?username=me&password=secret").credentialFree(hasAccount: true) == nil)
    }

    @Test func storedItemsStayAsTheyAre() throws {
        let stored = try #require(item("retune://movie/42.mp4").credentialFree(hasAccount: true))
        #expect(stored.url.absoluteString == "retune://movie/42.mp4")
    }
}

@Suite struct EarlyEndTests {
    @Test(arguments: [
        (position: 600.0, duration: 3600.0, previous: Double?.none, expected: true),
        (position: 3539.0, duration: 3600.0, previous: nil, expected: true),
        (position: 3540.0, duration: 3600.0, previous: nil, expected: false),
        (position: 3599.0, duration: 3600.0, previous: nil, expected: false),
        (position: 600.0, duration: 0.0, previous: nil, expected: false),
        (position: 600.0, duration: 3600.0, previous: 600.0, expected: false),
        (position: 605.0, duration: 3600.0, previous: 600.0, expected: false),
        (position: 606.0, duration: 3600.0, previous: 600.0, expected: true),
        (position: 590.0, duration: 3600.0, previous: 600.0, expected: false),
    ])
    func decision(position: Double, duration: Double, previous: Double?, expected: Bool) {
        #expect(ReconnectPolicy.endedEarly(position: position, duration: duration, previousEarlyEnd: previous) == expected)
    }

    /// A file truly cut short stops at the same spot, so retries have to come to an end.
    @Test func aTruncatedFileIsRetriedOnce() {
        var previous: Double?
        var retries = 0
        while ReconnectPolicy.endedEarly(position: 600, duration: 3600, previousEarlyEnd: previous), retries < 10 {
            previous = 600
            retries += 1
        }
        #expect(retries == 1)
    }
}

@Suite struct ForcedSpeedTests {
    @Test func liveAlwaysRunsAtNormalSpeed() {
        #expect(StreamProfile.live.forcedSpeed == 1)
    }

    @Test func onDemandKeepsTheChosenSpeed() {
        #expect(StreamProfile.onDemand.forcedSpeed == nil)
    }
}

@Suite struct AttributeScannerTests {
    /// The regex the scanner replaced, kept here as the definition of correct behavior.
    private func regexResult(_ header: String) -> [String: String] {
        var result: [String: String] = [:]
        for match in header.matches(of: /([A-Za-z0-9_-]+)="([^"]*)"/) {
            result[String(match.output.1).lowercased()] = String(match.output.2)
        }
        return result
    }

    @Test(arguments: [
        #"#EXTINF:-1 tvg-id="a" TVG-Logo="http://x/y.png" group-title="News, Sport",Name"#,
        #"key="""#,
        #"a="b" a="c""#,
        #"a="b c="d""#,
        #"a="unclosed"#,
        #"="no key""#,
        #"a=b c="d""#,
        #"a = "spaced" b="ok""#,
        #"x-y_z9="v"tail="w""#,
        #"a="é ü 日本語" b="😀""#,
        "",
    ])
    func matchesTheRegex(header: String) {
        #expect(M3UParser.parseAttributes(header) == regexResult(header))
    }

    @Test func matchesTheRegexOnGeneratedInput() {
        let alphabet = Array(#"ab-_9="" ,:"#)
        var state: UInt64 = 0x1234_5678
        for _ in 0..<5_000 {
            var header = ""
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            for _ in 0..<(state >> 59) {
                state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                header.append(alphabet[Int((state >> 33) % UInt64(alphabet.count))])
            }
            #expect(M3UParser.parseAttributes(header) == regexResult(header), "\(header)")
        }
    }

    /// Long enough that a parser retrying from every position would take minutes.
    @Test func aHugeLineParsesQuickly() {
        let header = String(repeating: "a", count: 500_000)
        let elapsed = ContinuousClock().measure { _ = M3UParser.parseAttributes(header) }
        #expect(elapsed < .seconds(2))
    }
}

@Suite struct SerialWorkTests {
    @Test func aDeleteWaitsForTheSaveBeforeIt() async {
        let order = OSAllocatedUnfairLock(initialState: [String]())
        var work = SerialWork()
        work.enqueue {
            Thread.sleep(forTimeInterval: 0.1)
            order.withLock { $0.append("save") }
        }
        work.enqueue { order.withLock { $0.append("delete") } }
        await work.finished()
        #expect(order.withLock { $0 } == ["save", "delete"])
    }

    @Test func finishedReturnsWithNothingEnqueued() async {
        await SerialWork().finished()
    }
}

@Suite struct PendingUntilReadyTests {
    @Test func runsAtOnceWhenReady() {
        var gate = PendingUntilReady<Int>()
        _ = gate.setReady(true)
        #expect(gate.submit(1) == 1)
    }

    @Test func waitsUntilReady() {
        var gate = PendingUntilReady<Int>()
        #expect(gate.submit(1) == nil)
        #expect(gate.setReady(true) == 1)
    }

    @Test func onlyTheLatestRequestRuns() {
        var gate = PendingUntilReady<Int>()
        _ = gate.submit(1)
        _ = gate.submit(2)
        #expect(gate.setReady(true) == 2)
    }

    @Test func aRequestRunsOnlyOnce() {
        var gate = PendingUntilReady<Int>()
        _ = gate.submit(1)
        _ = gate.setReady(true)
        #expect(gate.setReady(true) == nil)
    }

    @Test func aCancelledRequestNeverRuns() {
        var gate = PendingUntilReady<Int>()
        _ = gate.submit(1)
        gate.cancel()
        #expect(gate.setReady(true) == nil)
    }

    @Test func requestsWaitAgainAfterReadinessIsLost() {
        var gate = PendingUntilReady<Int>()
        _ = gate.setReady(true)
        _ = gate.setReady(false)
        #expect(gate.submit(1) == nil)
        #expect(gate.setReady(true) == 1)
    }
}
