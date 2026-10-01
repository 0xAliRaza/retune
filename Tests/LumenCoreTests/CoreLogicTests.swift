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
        #expect(locator.absoluteString == "lumen://movie/9.mkv")
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
        #expect(state.progress["k"]?.item.url.absoluteString == "lumen://series/42.mkv")
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
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-store-\(UUID().uuidString)")
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
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return XtreamClient(credentials: XtreamCredentials(server: URL(string: "http://h.example")!, username: "u", password: "p"),
                            session: URLSession(configuration: configuration))
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
        await #expect(throws: LumenError.emptyResponse) { try await client().movies() }
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
