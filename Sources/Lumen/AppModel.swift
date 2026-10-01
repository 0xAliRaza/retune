import CoreGraphics
import Foundation
import LumenCore
import Observation

enum LibrarySection: String, CaseIterable, Identifiable {
    case live, movies, series

    var id: String { rawValue }

    var title: String {
        switch self {
        case .live: "Live TV"
        case .movies: "Movies"
        case .series: "Series"
        }
    }

    var symbol: String {
        switch self {
        case .live: "dot.radiowaves.left.and.right"
        case .movies: "film"
        case .series: "play.rectangle.on.rectangle"
        }
    }

    var contentKind: ContentKind {
        switch self {
        case .live: .live
        case .movies: .movie
        case .series: .series
        }
    }
}

enum LayoutMode: String, CaseIterable, Identifiable {
    case grid, list, compact

    var id: String { rawValue }

    var title: String {
        switch self {
        case .grid: "Grid"
        case .list: "List"
        case .compact: "Compact"
        }
    }

    var symbol: String {
        switch self {
        case .grid: "square.grid.2x2"
        case .list: "list.bullet.below.rectangle"
        case .compact: "list.bullet"
        }
    }
}

enum TileSize: String, CaseIterable, Identifiable {
    case small, medium, large

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    /// Minimum grid column width.
    var minWidth: CGFloat {
        switch self {
        case .small: 112
        case .medium: 150
        case .large: 210
        }
    }
}

enum CategoryFilter: Hashable {
    case all, favorites, continueWatching, recent
    case category(String)
}

enum Route: Hashable {
    case movie(Movie)
    case series(Series)
}

/// A pending PIN prompt; `onSuccess` runs once the PIN is created or verified.
struct PINRequest: Identifiable {
    enum Mode { case create, verify(String) }

    let id = UUID()
    let mode: Mode
    /// Which window presents the prompt; Settings and the main window both observe requests.
    var fromSettings = false
    let onSuccess: () -> Void
}

enum LoadStatus: Equatable {
    case idle
    case loading(String)
    case failed(String)
    case ready
}

/// Catalog plus prebuilt indexes for one playlist.
struct LoadedCatalog {
    let playlist: Playlist
    let catalog: Catalog
    let client: XtreamClient?
    let channels: BrowseIndex<Channel>
    let movies: BrowseIndex<Movie>
    let series: BrowseIndex<Series>

    private init(playlist: Playlist, catalog: Catalog, client: XtreamClient?,
                 channels: BrowseIndex<Channel>, movies: BrowseIndex<Movie>, series: BrowseIndex<Series>) {
        self.playlist = playlist
        self.catalog = catalog
        self.client = client
        self.channels = channels
        self.movies = movies
        self.series = series
    }

    /// Builds the three search indexes in parallel (normalising ~88k titles).
    static func build(playlist: Playlist, catalog: Catalog, client: XtreamClient?) async -> LoadedCatalog {
        async let channels = Task.detached(priority: .userInitiated) { BrowseIndex(catalog.channels) }.value
        async let movies = Task.detached(priority: .userInitiated) { BrowseIndex(catalog.movies) }.value
        async let series = Task.detached(priority: .userInitiated) { BrowseIndex(catalog.series) }.value
        return await LoadedCatalog(playlist: playlist, catalog: catalog, client: client,
                                   channels: channels, movies: movies, series: series)
    }

    func categories(for section: LibrarySection) -> [MediaCategory] {
        switch section {
        case .live: catalog.liveCategories
        case .movies: catalog.vodCategories
        case .series: catalog.seriesCategories
        }
    }

    func count(section: LibrarySection, category: String) -> Int {
        switch section {
        case .live: channels.count(in: category)
        case .movies: movies.count(in: category)
        case .series: series.count(in: category)
        }
    }

    /// Display name for a provider category (providers often pad names with spaces).
    func categoryName(_ id: String, in section: LibrarySection) -> String? {
        categories(for: section).first { $0.id == id }?.name.trimmingCharacters(in: .whitespaces)
    }

    func total(_ section: LibrarySection) -> Int {
        switch section {
        case .live: channels.items.count
        case .movies: movies.items.count
        case .series: series.items.count
        }
    }
}

@MainActor
@Observable
final class AppModel {
    private(set) var playlists: [Playlist] = []
    private(set) var loaded: LoadedCatalog? {
        didSet {
            // First load of a playlist: pick a sensible starting category for the current section.
            if oldValue?.playlist.id != loaded?.playlist.id { filter = defaultFilter(for: section) }
        }
    }
    private(set) var status: LoadStatus = .idle
    private(set) var isRefreshing = false
    private(set) var account: AccountInfo?
    private(set) var library = LibraryState()

    var activePlaylistID: UUID? {
        didSet {
            guard activePlaylistID != oldValue else { return }
            UserDefaults.standard.set(activePlaylistID?.uuidString, forKey: "activePlaylist")
            Task { await loadActivePlaylist() }
        }
    }

    var section: LibrarySection = .live { didSet { if section != oldValue { resetBrowsing() } } }
    var filter: CategoryFilter = .all
    var searchText = ""
    var sortOrder: BrowseSort = .provider
    var detailPath: [Route] = []

    /// Layout per section, remembered across launches.
    var layoutMode: LayoutMode {
        get { layoutModes[section] ?? (section == .live ? .list : .grid) }
        set {
            layoutModes[section] = newValue
            UserDefaults.standard.set(newValue.rawValue, forKey: "layout.\(section.rawValue)")
        }
    }

    var tileSize: TileSize = TileSize(rawValue: UserDefaults.standard.string(forKey: "layout.tileSize") ?? "") ?? .medium {
        didSet { UserDefaults.standard.set(tileSize.rawValue, forKey: "layout.tileSize") }
    }

    private var layoutModes: [LibrarySection: LayoutMode] = Dictionary(uniqueKeysWithValues: LibrarySection.allCases.compactMap { section in
        LayoutMode(rawValue: UserDefaults.standard.string(forKey: "layout.\(section.rawValue)") ?? "").map { (section, $0) }
    })
    var isAddingPlaylist = false
    var isShowingShortcuts = false
    /// Bumped by ⌘F; the root view moves focus into the search field.
    var searchFocusRequests = 0

    // MARK: Keyboard focus across columns

    struct FocusRequest: Equatable {
        enum Target: Equatable { case pane(PaneNavigation.Pane), categoryFilter }
        let target: Target
        let id: Int
    }

    /// The column holding keyboard focus, reported by each column as it gains focus.
    @ObservationIgnored var focusedPane: PaneNavigation.Pane?
    private(set) var focusRequest: FocusRequest?

    func focus(_ pane: PaneNavigation.Pane) { request(.pane(pane)) }
    func focusCategoryFilter() { request(.categoryFilter) }
    func focusSearch() { searchFocusRequests += 1 }

    private func request(_ target: FocusRequest.Target) {
        focusRequest = FocusRequest(target: target, id: (focusRequest?.id ?? 0) + 1)
    }

    func isRequested(_ pane: PaneNavigation.Pane) -> Bool { focusRequest?.target == .pane(pane) }

    func goBack() {
        if !detailPath.isEmpty { detailPath.removeLast() }
    }
    var editingPlaylist: Playlist?

    let session: PlaybackSession
    /// Drives the player overlay separately from playback so closing can fade out while video still runs.
    var isPlayerPresented = false

    private let playlistStore = JSONFileStore<[Playlist]>(url: AppPaths.playlists)
    private let libraryStore = JSONFileStore<LibraryState>(url: AppPaths.library)
    let secrets = SecretStore()
    @ObservationIgnored private var librarySaveTask: Task<Void, Never>?
    @ObservationIgnored private var loadGeneration = 0
    @ObservationIgnored private var refreshTask: (generation: Int, task: Task<Void, Never>)?
    /// When each item's progress was last written to the observed library (see `recordProgress`).
    @ObservationIgnored private var lastProgressCommit: [String: Date] = [:]

    /// Catalogs refresh in the background once they are older than this.
    private let catalogMaxAge: TimeInterval = 12 * 60 * 60

    init() {
        session = PlaybackSession()
        playlists = playlistStore.load() ?? []
        library = libraryStore.load() ?? LibraryState()
        // Older builds stored full stream URLs (with the password) in watch history.
        if library.sanitizeStreamURLs() { try? libraryStore.save(library) }
        session.onProgress = { [weak self] item, position, duration, isFinal in
            self?.recordProgress(item: item, position: position, duration: duration, isFinal: isFinal)
        }
        session.epgProvider = { [weak self] item in await self?.epg(for: item) ?? [] }
        session.resumePosition = { [weak self] item in
            item.isLive ? nil : self?.progress(item.kind, item.id)?.resumePosition
        }

        let stored = UserDefaults.standard.string(forKey: "activePlaylist").flatMap(UUID.init(uuidString:))
        activePlaylistID = playlists.first { $0.id == stored }?.id ?? playlists.first?.id
    }

    var activePlaylist: Playlist? { playlists.first { $0.id == activePlaylistID } }

    // MARK: Playlists

    func addPlaylist(_ playlist: Playlist, password: String?) {
        if let password { secrets.set(password, for: playlist.id.uuidString) }
        if let index = playlists.firstIndex(where: { $0.id == playlist.id }) {
            playlists[index] = playlist
            savePlaylists()
            if activePlaylistID == playlist.id { Task { await refresh() } }
        } else {
            playlists.append(playlist)
            savePlaylists()
            activePlaylistID = playlist.id
        }
    }

    func deletePlaylist(_ playlist: Playlist) {
        playlists.removeAll { $0.id == playlist.id }
        savePlaylists()
        secrets.remove(playlist.id.uuidString)
        JSONFileStore<Catalog>(url: AppPaths.catalog(for: playlist.id)).delete()
        library.removeAll(playlist: playlist.id)
        scheduleLibrarySave()
        if activePlaylistID == playlist.id {
            loaded = nil
            activePlaylistID = playlists.first?.id
        }
    }

    func credentials(for playlist: Playlist) -> XtreamCredentials? {
        guard case let .xtream(server, username) = playlist.source,
              let password = secrets.get(playlist.id.uuidString) else { return nil }
        return XtreamCredentials(server: server, username: username, password: password)
    }

    private func savePlaylists() {
        try? playlistStore.save(playlists)
    }

    // MARK: Catalog loading

    private func loadActivePlaylist() async {
        loadGeneration += 1
        let generation = loadGeneration
        resetBrowsing()
        account = nil
        // Never show (or key favorites against) the previous playlist's catalog while this one loads.
        loaded = nil
        guard let playlist = activePlaylist else { status = .idle; return }
        if section == .series, !playlist.supportsSeries { section = .live }

        let client = credentials(for: playlist).map { XtreamClient(credentials: $0) }
        let cacheStore = JSONFileStore<Catalog>(url: AppPaths.catalog(for: playlist.id))
        status = .loading("Opening \(playlist.name)…")
        // Fast parallel decode; the plain store load handles (and backs up) a corrupt file.
        let catalog: Catalog?
        if let fast = await Catalog.loadConcurrently(from: cacheStore.url) {
            catalog = fast
        } else {
            catalog = await Task.detached(priority: .userInitiated) { cacheStore.load() }.value
        }
        let cached: LoadedCatalog? = if let catalog { await LoadedCatalog.build(playlist: playlist, catalog: catalog, client: client) } else { nil }
        guard generation == loadGeneration else { return }

        if let cached {
            loaded = cached
            status = .ready
            if cached.catalog.isStale(maxAge: catalogMaxAge) { await refresh() }
        } else {
            await refresh()
        }
        if generation == loadGeneration, let client {
            let info = try? await client.authenticate()
            if generation == loadGeneration { account = info }
        }
    }

    /// Downloads the full catalog for the active playlist and replaces the cache. A refresh already
    /// running for this playlist is joined; one left over from a previous playlist is cancelled.
    func refresh() async {
        if let running = refreshTask, running.generation == loadGeneration {
            await running.task.value
            return
        }
        refreshTask?.task.cancel()
        let generation = loadGeneration
        let task = Task { await performRefresh(generation: generation) }
        refreshTask = (generation, task)
        await task.value
        if refreshTask?.generation == generation { refreshTask = nil }
    }

    private func performRefresh(generation: Int) async {
        guard let playlist = activePlaylist else { return }
        isRefreshing = true
        defer { if generation == loadGeneration { isRefreshing = false } }
        if loaded == nil { status = .loading("Downloading channels, movies and series…") }

        do {
            let client: XtreamClient?
            let catalog: Catalog
            switch playlist.source {
            case .xtream:
                guard let credentials = credentials(for: playlist) else { throw LumenError.missingPassword }
                let xtream = XtreamClient(credentials: credentials)
                client = xtream
                catalog = try await CatalogLoader.fetchXtream(xtream)
            case .m3u(let url):
                client = nil
                catalog = try await CatalogLoader.fetchM3U(url)
            }
            let cacheStore = JSONFileStore<Catalog>(url: AppPaths.catalog(for: playlist.id))
            Task.detached(priority: .utility) { try? cacheStore.save(catalog) }
            let built = await LoadedCatalog.build(playlist: playlist, catalog: catalog, client: client)
            guard generation == loadGeneration else { return }
            loaded = built
            status = .ready
        } catch {
            guard generation == loadGeneration else { return }
            // Keep showing cached content when a background refresh fails.
            if loaded == nil { status = .failed(error.localizedDescription) }
        }
    }

    private func resetBrowsing() {
        detailPath = []
        searchText = ""
        sortOrder = .provider
        filter = defaultFilter(for: section)
    }

    /// Movies and Series open on Continue Watching when something is in progress, otherwise on the first
    /// visible, unlocked category (rendering 60k+ posters under "All" is slow to scan anyway). Live opens on All.
    private func defaultFilter(for section: LibrarySection) -> CategoryFilter {
        guard section != .live else { return .all }
        if !continueWatching.isEmpty { return .continueWatching }
        guard let first = browsableCategories(for: section).first(where: { !isLocked($0.id, in: section) }) else { return .all }
        return .category(first.id)
    }

    // MARK: Categories (hide · lock · pin)

    /// Session-only: locked categories the user has unlocked with the PIN. Cleared on quit or ⌘L.
    private(set) var unlockedCategories: Set<String> = []

    private func categoryKey(_ id: String, in section: LibrarySection? = nil) -> String {
        ContentKey.category(playlist: activePlaylistID ?? UUID(), kind: (section ?? self.section).contentKind, id: id)
    }

    private func categoryIDs(_ keys: some Sequence<String>, in section: LibrarySection) -> [String] {
        LibraryState.ids(in: keys, prefix: ContentKey.categoryPrefix(playlist: activePlaylistID ?? UUID(), kind: section.contentKind))
    }

    func isHidden(_ id: String) -> Bool { library.hiddenCategories.contains(categoryKey(id)) }
    func isPinned(_ id: String) -> Bool { library.pinnedCategories.contains(categoryKey(id)) }
    func hasLock(_ id: String, in section: LibrarySection? = nil) -> Bool { library.lockedCategories.contains(categoryKey(id, in: section)) }

    /// Locked and not unlocked this session.
    func isLocked(_ id: String, in section: LibrarySection? = nil) -> Bool {
        let key = categoryKey(id, in: section)
        return library.lockedCategories.contains(key) && !unlockedCategories.contains(key)
    }

    /// Provider categories minus hidden ones, pinned first.
    func browsableCategories(for section: LibrarySection) -> [MediaCategory] {
        let all = loaded?.categories(for: section) ?? []
        let hidden = Set(categoryIDs(library.hiddenCategories, in: section))
        let pinnedOrder = categoryIDs(library.pinnedCategories, in: section)
        let visible = all.filter { !hidden.contains($0.id) }
        let pinned = pinnedOrder.compactMap { id in visible.first { $0.id == id } }
        return pinned + visible.filter { !pinnedOrder.contains($0.id) }
    }

    func hiddenCategories(for section: LibrarySection) -> [MediaCategory] {
        let all = loaded?.categories(for: section) ?? []
        return categoryIDs(library.hiddenCategories, in: section).map { id in
            all.first { $0.id == id } ?? MediaCategory(id: id, name: "Category \(id)")
        }
    }

    /// Categories whose content must not leak into All, Favorites, Search or history rows.
    private func excludedCategories(for section: LibrarySection) -> Set<String> {
        let hidden = categoryIDs(library.hiddenCategories, in: section)
        let locked = categoryIDs(library.lockedCategories, in: section).filter { isLocked($0, in: section) }
        return Set(hidden + locked)
    }

    func toggleHidden(_ id: String) {
        library.toggleHidden(categoryKey(id))
        if filter == .category(id) { filter = .all }
        scheduleLibrarySave()
    }

    func togglePinned(_ id: String) {
        library.togglePinned(categoryKey(id))
        scheduleLibrarySave()
    }

    func unhide(_ id: String, in section: LibrarySection) {
        library.hiddenCategories.remove(categoryKey(id, in: section))
        scheduleLibrarySave()
    }

    /// Locks immediately; asks to create a PIN first if none exists.
    func lockCategory(_ id: String) {
        let key = categoryKey(id)
        let apply = { [weak self] in
            guard let self else { return }
            library.setLocked(key, true)
            unlockedCategories.remove(key)
            scheduleLibrarySave()
        }
        if library.hasPIN { apply() } else { pinRequest = PINRequest(mode: .create, onSuccess: apply) }
    }

    func removeLock(_ id: String) {
        let key = categoryKey(id)
        pinRequest = PINRequest(mode: .verify("Enter your PIN to remove this lock."), onSuccess: { [weak self] in
            self?.library.setLocked(key, false)
            self?.scheduleLibrarySave()
        })
    }

    @discardableResult
    func unlock(_ id: String, pin: String) -> Bool {
        guard library.verifyPIN(pin) else { return false }
        unlockedCategories.insert(categoryKey(id))
        return true
    }

    func relockAll() { unlockedCategories = [] }

    // MARK: Parental PIN

    var hasPIN: Bool { library.hasPIN }
    var pinRequest: PINRequest?

    func verifyPIN(_ pin: String) -> Bool { library.verifyPIN(pin) }

    func setPIN(_ pin: String) {
        library.setPIN(pin)
        scheduleLibrarySave()
    }

    func createPINFromSettings() {
        pinRequest = PINRequest(mode: .create, fromSettings: true, onSuccess: {})
    }

    func changePIN() {
        pinRequest = PINRequest(mode: .verify("Enter your current PIN."), fromSettings: true, onSuccess: { [weak self] in
            self?.createPINFromSettings()
        })
    }

    func removePIN() {
        pinRequest = PINRequest(mode: .verify("Enter your PIN. Removing it also removes every category lock."), fromSettings: true, onSuccess: { [weak self] in
            self?.library.removePIN()
            self?.unlockedCategories = []
            self?.scheduleLibrarySave()
        })
    }

    // MARK: History

    func removeFromContinueWatching(_ entry: WatchProgress) {
        library.removeFromContinueWatching(key: key(entry.item.kind, entry.item.id))
        scheduleLibrarySave()
    }

    func removeFromRecent(_ channel: Channel) {
        library.removeRecentChannel(key(.live, channel.id))
        scheduleLibrarySave()
    }

    func clearContinueWatching() {
        guard let playlist = activePlaylistID else { return }
        library.clearContinueWatching(playlist: playlist)
        scheduleLibrarySave()
    }

    func clearRecentChannels() {
        guard let playlist = activePlaylistID else { return }
        library.clearRecentChannels(playlist: playlist)
        scheduleLibrarySave()
    }

    func isWatched(_ kind: ContentKind, _ id: String) -> Bool { progress(kind, id)?.isFinished == true }

    func setWatched(movie: Movie, _ watched: Bool) {
        if watched {
            guard let item = movieItem(movie).map(storable) else { return }
            library.markWatched(key: key(.movie, movie.id), item: item, duration: progress(.movie, movie.id)?.duration)
        } else {
            library.markUnwatched(key: key(.movie, movie.id))
        }
        scheduleLibrarySave()
    }

    func setWatched(episode: Episode, of series: Series, _ watched: Bool) {
        if watched {
            guard let client = loaded?.client else { return }
            let item = storable(episodeItem(episode, of: series, client: client))
            library.markWatched(key: key(.episode, episode.id), item: item,
                                duration: episode.durationSeconds.map(Double.init) ?? progress(.episode, episode.id)?.duration)
        } else {
            library.markUnwatched(key: key(.episode, episode.id))
        }
        scheduleLibrarySave()
    }

    // MARK: Browsing

    var isSearching: Bool { !searchText.trimmingCharacters(in: .whitespaces).isEmpty }

    /// The selected category is locked, so the content area shows the unlock prompt.
    var selectedLockedCategory: String? {
        guard !isSearching, case .category(let id) = filter, isLocked(id) else { return nil }
        return id
    }

    /// While searching, results span every category in the current section.
    private var effectiveCategory: String? {
        if isSearching { return nil }
        if case .category(let id) = filter { return id }
        return nil
    }

    private var restrictedIDs: Set<String>? {
        guard !isSearching, let playlist = activePlaylistID else { return nil }
        switch filter {
        case .favorites: return library.favoriteIDs(playlist: playlist, kind: section.contentKind)
        case .recent: return Set(recentChannelIDs)
        default: return nil
        }
    }

    /// Exclusions only apply when browsing across categories; a chosen category is already unlocked.
    private var activeExclusions: Set<String> { effectiveCategory == nil ? excludedCategories(for: section) : [] }

    var visibleChannels: [Channel] {
        guard let loaded else { return [] }
        if filter == .recent, !isSearching {
            let excluded = excludedCategories(for: .live)
            return recentChannelIDs.compactMap { loaded.channels.item(id: $0) }
                .filter { $0.categoryID.map { !excluded.contains($0) } ?? true }
        }
        return loaded.channels.select(category: effectiveCategory, query: searchText, ids: restrictedIDs,
                                      excludedCategories: activeExclusions, sort: sortOrder)
    }

    var visibleMovies: [Movie] {
        loaded?.movies.select(category: effectiveCategory, query: searchText, ids: restrictedIDs,
                              excludedCategories: activeExclusions, sort: sortOrder) ?? []
    }

    var visibleSeries: [Series] {
        loaded?.series.select(category: effectiveCategory, query: searchText, ids: restrictedIDs,
                              excludedCategories: activeExclusions, sort: sortOrder) ?? []
    }

    var continueWatching: [WatchProgress] {
        guard let playlist = activePlaylistID, let loaded else { return [] }
        let excluded = excludedCategories(for: section)
        return library.continueWatching(playlist: playlist).filter { entry in
            switch (section, entry.item.kind) {
            case (.movies, .movie):
                return loaded.movies.item(id: entry.item.id)?.categoryID.map { !excluded.contains($0) } ?? true
            case (.series, .episode):
                return entry.item.parentID.flatMap { loaded.series.item(id: $0)?.categoryID }.map { !excluded.contains($0) } ?? true
            default:
                return false
            }
        }
    }

    private var recentChannelIDs: [String] {
        guard let playlist = activePlaylistID else { return [] }
        let prefix = ContentKey.make(playlist: playlist, kind: .live, id: "")
        return library.recentChannels.filter { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
    }

    var filterTitle: String {
        if isSearching { return "Results for “\(searchText)”" }
        switch filter {
        case .all: return "All \(section.title)"
        case .favorites: return "Favorites"
        case .continueWatching: return "Continue Watching"
        case .recent: return "Recently Watched"
        case .category(let id): return loaded?.categoryName(id, in: section) ?? section.title
        }
    }

    // MARK: Library

    func key(_ kind: ContentKind, _ id: String) -> String {
        ContentKey.make(playlist: activePlaylistID ?? UUID(), kind: kind, id: id)
    }

    func isFavorite(_ kind: ContentKind, _ id: String) -> Bool { library.favorites.contains(key(kind, id)) }

    func toggleFavorite(_ kind: ContentKind, _ id: String) {
        library.toggleFavorite(key(kind, id))
        scheduleLibrarySave()
    }

    func progress(_ kind: ContentKind, _ id: String) -> WatchProgress? { library.progress[key(kind, id)] }

    /// Periodic ticks only reach the observed library every 30 s; stops, switches and endings always do.
    /// Every library write re-renders the browse view under the player, which holds up to 65k items.
    private func recordProgress(item: PlaybackItem, position: Double, duration: Double, isFinal: Bool) {
        if item.isLive {
            library.recordChannel(key: key(.live, item.streamID ?? item.id))
        } else {
            let key = key(item.kind, item.id)
            if !isFinal, let last = lastProgressCommit[key], Date().timeIntervalSince(last) < 30 { return }
            lastProgressCommit[key] = Date()
            library.recordProgress(key: key, item: storable(item), position: position, duration: duration)
        }
        scheduleLibrarySave()
    }

    /// Strips credentials from Xtream stream URLs before they're persisted.
    private func storable(_ item: PlaybackItem) -> PlaybackItem {
        XtreamClient.locator(for: item.url).map(item.with(url:)) ?? item
    }

    /// Turns a stored (credential-free) item back into a playable one for the current account.
    private func playable(_ item: PlaybackItem) -> PlaybackItem? {
        guard item.url.scheme == XtreamClient.locatorScheme else { return item }
        guard let client = loaded?.client else { return nil }
        return item.with(url: client.resolve(item.url))
    }

    private func scheduleLibrarySave() {
        librarySaveTask?.cancel()
        let snapshot = library
        let store = libraryStore
        librarySaveTask = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            try? store.save(snapshot)
        }
    }

    func flushLibrary() {
        librarySaveTask?.cancel()
        try? libraryStore.save(library)
    }

    // MARK: Playback

    func play(channel: Channel, in list: [Channel]) {
        guard let loaded else { return }
        startQueue(from: list, selected: channel, title: filterTitle) { self.liveItem($0, loaded: loaded) }
    }

    /// Queues the list the movie was picked from so ↑/↓ and the list panel can switch titles.
    /// From a detail page there's no list in hand, so the current browse results are used.
    func play(movie: Movie, in list: [Movie]? = nil, resume: Bool = true) {
        let source = list ?? visibleMovies
        startQueue(from: source.contains(movie) ? source : [movie], selected: movie, title: filterTitle,
                   startAt: resume ? progress(.movie, movie.id)?.resumePosition : nil, make: movieItem)
    }

    /// Plays an episode with the rest of the series queued for autoplay.
    func play(episode: Episode, of series: Series, seasons: [Season], resume: Bool = true) {
        guard let client = loaded?.client else { return }
        startQueue(from: seasons.flatMap(\.episodes), selected: episode, title: series.name,
                   startAt: resume ? progress(.episode, episode.id)?.resumePosition : nil) {
            self.episodeItem($0, of: series, client: client)
        }
    }

    /// Resumes one entry with the rest of Continue Watching queued alongside it.
    func resume(_ entry: WatchProgress) {
        let entries = continueWatching
        startQueue(from: entries.contains(entry) ? entries : [entry], selected: entry, title: "Continue Watching",
                   startAt: entry.resumePosition) { self.playable($0.item) }
    }

    /// Plays one standalone item (used by the `--play` developer hook).
    func playDirect(_ item: PlaybackItem) {
        session.queueTitle = nil
        session.play([item], at: 0)
        isPlayerPresented = true
    }

    /// Windows `list` around `selected`, builds playable items (skipping unplayable ones without
    /// shifting the selection) and starts playback.
    private func startQueue<Element: Equatable>(from list: [Element], selected: Element, title: String?,
                                                startAt: Double? = nil, make: (Element) -> PlaybackItem?) {
        guard let position = list.firstIndex(of: selected) else { return }
        let range = QueueWindow.range(count: list.count, around: position)
        guard let queue = QueueNavigation.build(Array(list[range]), selected: position - range.lowerBound, make: make) else { return }
        session.queueTitle = title
        session.play(queue.items, at: queue.index, startAt: startAt)
        isPlayerPresented = true
    }

    private func movieItem(_ movie: Movie) -> PlaybackItem? {
        guard let url = loaded?.client?.movieURL(movie) ?? movie.directURL else { return nil }
        return PlaybackItem(id: movie.id, kind: .movie, title: movie.name, url: url, artwork: movie.poster)
    }

    private func episodeItem(_ episode: Episode, of series: Series, client: XtreamClient) -> PlaybackItem {
        PlaybackItem(id: episode.id, kind: .episode, title: series.name,
                     subtitle: "S\(episode.season) E\(episode.number) · \(episode.title)",
                     url: client.episodeURL(episode), artwork: episode.image ?? series.cover, parentID: series.id)
    }

    private func liveItem(_ channel: Channel, loaded: LoadedCatalog) -> PlaybackItem? {
        let format = PlayerPreferences.liveFormat.resolve(allowed: account?.allowedFormats ?? [])
        guard let url = channel.directURL ?? loaded.client?.liveURL(streamID: channel.id, format: format) else { return nil }
        return PlaybackItem(id: channel.id, kind: .live, title: channel.name,
                            subtitle: channel.categoryID.flatMap { loaded.categoryName($0, in: .live) },
                            url: url, artwork: channel.logo, streamID: channel.id)
    }

    private func epg(for item: PlaybackItem) async -> [EPGEntry] {
        guard item.isLive, let streamID = item.streamID, let client = loaded?.client else { return [] }
        return (try? await client.shortEPG(streamID: streamID, limit: 4)) ?? []
    }

    // MARK: Details

    func movieInfo(_ movie: Movie) async -> MediaInfo? {
        try? await loaded?.client?.movieInfo(id: movie.id)
    }

    func seriesDetail(_ series: Series) async throws -> SeriesDetail {
        guard let client = loaded?.client else { throw LumenError.unreadableResponse }
        return try await client.seriesInfo(id: series.id)
    }
}

extension WatchProgress {
    /// Back up a few seconds so viewers regain context.
    var resumePosition: Double? { isResumable ? max(position - 5, 0) : nil }
}
