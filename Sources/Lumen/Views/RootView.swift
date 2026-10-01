import AppKit
import LumenCore
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var window: NSWindow?
    @State private var swipeMonitor: SwipeBackMonitor?

    var body: some View {
        @Bindable var model = model
        ZStack {
            Group {
                if model.playlists.isEmpty {
                    WelcomeView()
                } else {
                    browser
                }
            }
            // The player takes over the window instead of opening a separate one.
            if model.isPlayerPresented {
                PlayerScreen().transition(.opacity.combined(with: .scale(scale: 0.985)))
            }
        }
        .animation(.easeInOut(duration: 0.28), value: model.isPlayerPresented)
        // Stays hidden until playback has fully stopped, so it never pops in over the fading player.
        .toolbar(model.isPlayerPresented || model.session.isActive ? .hidden : .visible, for: .windowToolbar)
        .background(WindowAccessor(window: $window))
        .onAppear {
            // Back-swipe pops movie/series pages; the player installs its own while it's open.
            let monitor = SwipeBackMonitor(canGoBack: { !model.isPlayerPresented && !model.detailPath.isEmpty },
                                           onBack: { model.detailPath.removeLast() })
            monitor.start(window: { window })
            swipeMonitor = monitor
        }
        .sheet(isPresented: $model.isAddingPlaylist) { PlaylistEditor(existing: nil) }
        .sheet(isPresented: $model.isShowingShortcuts) { ShortcutsView() }
        .sheet(item: $model.editingPlaylist) { PlaylistEditor(existing: $0) }
        .sheet(item: Binding(get: { model.pinRequest.flatMap { $0.fromSettings ? nil : $0 } },
                             set: { model.pinRequest = $0 })) { PINSheet(request: $0) }
    }

    private var browser: some View {
        @Bindable var model = model
        return NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } content: {
            CategoryColumn()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
        } detail: {
            NavigationStack(path: $model.detailPath) {
                ContentArea()
                    .navigationDestination(for: Route.self) { route in
                        switch route {
                        case .movie(let movie): MovieDetailView(movie: movie)
                        case .series(let series): SeriesDetailView(series: series)
                        }
                    }
            }
        }
        .searchable(text: $model.searchText, placement: .toolbar, prompt: "Search \(model.section.title)")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if model.isRefreshing {
                    ProgressView().controlSize(.small).help("Refreshing playlist…")
                } else {
                    Button { Task { await model.refresh() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                        .help("Reload channels, movies and series from the provider (⌘R)")
                }
            }
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: Binding(get: { model.section }, set: { if let value = $0 { model.section = value } })) {
            Section("Library") {
                ForEach(LibrarySection.allCases) { section in
                    if section != .series || model.activePlaylist?.supportsSeries == true {
                        Label(section.title, systemImage: section.symbol)
                            .badge(model.loaded?.total(section) ?? 0)
                            .tag(section)
                    }
                }
            }
            Section("Playlists") {
                ForEach(model.playlists) { playlist in
                    PlaylistRow(playlist: playlist, isActive: playlist.id == model.activePlaylistID)
                        .contentShape(Rectangle())
                        .onTapGesture { model.activePlaylistID = playlist.id }
                        .contextMenu {
                            Button("Use This Playlist") { model.activePlaylistID = playlist.id }
                            Button("Edit…") { model.editingPlaylist = playlist }
                            Divider()
                            Button("Delete", role: .destructive) { model.deletePlaylist(playlist) }
                        }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                if let account = model.account { AccountBadge(account: account) }
                Button { model.isAddingPlaylist = true } label: {
                    Label("Add Playlist", systemImage: "plus.circle.fill").frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderless)
            }
            .padding(12)
        }
    }
}

private struct PlaylistRow: View {
    let playlist: Playlist
    let isActive: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isActive ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(playlist.name).lineLimit(1)
                Text(playlist.kindLabel).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct AccountBadge: View {
    let account: AccountInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(account.status, systemImage: "person.crop.circle.badge.checkmark")
                .font(.caption.weight(.semibold))
                .foregroundStyle(account.isActive ? .green : .orange)
            if let expiry = account.expiresAt {
                Text("Expires \(expiry.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if let max = account.maxConnections {
                Text("\(max) connection\(max == 1 ? "" : "s") allowed").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Category column

struct CategoryColumn: View {
    @Environment(AppModel.self) private var model
    @State private var categoryQuery = ""
    @State private var confirmClear: ClearTarget?

    var body: some View {
        Group {
            if let loaded = model.loaded {
                categoryList(loaded)
            } else {
                Color.clear
            }
        }
        .navigationTitle(model.section.title)
        .onChange(of: model.section) { categoryQuery = "" }
    }

    private var selection: Binding<CategoryFilter?> {
        Binding(get: { model.filter }, set: { value in
            guard let value else { return }
            model.filter = value
            model.detailPath = []
        })
    }

    private func categoryList(_ loaded: LoadedCatalog) -> some View {
        let section = model.section
        let categories = filteredCategories()
        let pinned = categories.filter { model.isPinned($0.id) }
        let others = categories.filter { !model.isPinned($0.id) }
        return List(selection: selection) {
            Section {
                Label("All", systemImage: "square.grid.2x2").badge(loaded.total(section)).tag(CategoryFilter.all)
                Label("Favorites", systemImage: "star").tag(CategoryFilter.favorites)
                if section == .live {
                    Label("Recently Watched", systemImage: "clock.arrow.circlepath").tag(CategoryFilter.recent)
                        .contextMenu { Button("Clear Recently Watched…", role: .destructive) { confirmClear = .recent } }
                } else {
                    Label("Continue Watching", systemImage: "play.circle").tag(CategoryFilter.continueWatching)
                        .contextMenu { Button("Clear Continue Watching…", role: .destructive) { confirmClear = .continueWatching } }
                }
            }
            if !pinned.isEmpty {
                Section("Pinned") { rows(pinned, loaded: loaded) }
            }
            Section("Categories") { rows(others, loaded: loaded) }
        }
        .safeAreaInset(edge: .top) {
            TextField("Filter categories", text: $categoryQuery)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 10).padding(.vertical, 6)
        }
        .safeAreaInset(edge: .bottom) {
            let hiddenCount = model.hiddenCategories(for: section).count
            if hiddenCount > 0 {
                SettingsLink {
                    Label("\(hiddenCount) hidden", systemImage: "eye.slash").font(.caption)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .help("Manage hidden categories in Settings")
            }
        }
        .confirmationDialog(confirmClear?.title ?? "", isPresented: Binding(get: { confirmClear != nil }, set: { if !$0 { confirmClear = nil } }),
                            titleVisibility: .visible) {
            Button("Clear", role: .destructive) {
                if confirmClear == .recent { model.clearRecentChannels() } else { model.clearContinueWatching() }
            }
        } message: {
            Text("This only affects this playlist. Favorites and watched marks are kept.")
        }
    }

    private func rows(_ categories: [MediaCategory], loaded: LoadedCatalog) -> some View {
        ForEach(categories) { category in
            CategoryRow(name: category.name, count: loaded.count(section: model.section, category: category.id),
                        isPinned: model.isPinned(category.id), lock: lockState(category.id))
                .tag(CategoryFilter.category(category.id))
                .contextMenu { menu(for: category.id) }
        }
    }

    private func lockState(_ id: String) -> CategoryRow.LockState {
        guard model.hasLock(id) else { return .none }
        return model.isLocked(id) ? .locked : .unlocked
    }

    @ViewBuilder private func menu(for id: String) -> some View {
        Button(model.isPinned(id) ? "Unpin" : "Pin to Top", systemImage: model.isPinned(id) ? "pin.slash" : "pin") { model.togglePinned(id) }
        if model.hasLock(id) {
            Button("Remove Lock…", systemImage: "lock.open") { model.removeLock(id) }
        } else {
            Button("Lock with PIN", systemImage: "lock") { model.lockCategory(id) }
        }
        Divider()
        Button("Hide Category", systemImage: "eye.slash") { model.toggleHidden(id) }
    }

    private func filteredCategories() -> [MediaCategory] {
        let terms = SearchText.terms(categoryQuery)
        let all = model.browsableCategories(for: model.section)
        guard !terms.isEmpty else { return all }
        return all.filter { SearchText.matches(normalizedName: SearchText.normalize($0.name), terms: terms) }
    }
}

private enum ClearTarget {
    case recent, continueWatching

    var title: String { self == .recent ? "Clear Recently Watched?" : "Clear Continue Watching?" }
}

private struct CategoryRow: View {
    enum LockState { case none, locked, unlocked }

    let name: String
    let count: Int
    let isPinned: Bool
    let lock: LockState

    var body: some View {
        HStack(spacing: 6) {
            Text(name.trimmingCharacters(in: .whitespaces)).lineLimit(1)
            Spacer(minLength: 4)
            switch lock {
            case .locked: Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary)
            case .unlocked: Image(systemName: "lock.open").font(.caption).foregroundStyle(.tertiary)
            case .none: EmptyView()
            }
        }
        // Counts would reveal what a locked category holds.
        .badge(lock == .locked ? 0 : count)
    }
}

// MARK: - Content

struct ContentArea: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.status {
        case .loading(let message) where model.loaded == nil:
            VStack(spacing: 14) {
                ProgressView().controlSize(.large)
                Text(message).font(.headline)
                Text("Large playlists can take a minute the first time. After that they open instantly.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message) where model.loaded == nil:
            ContentUnavailableView {
                Label("Couldn't load playlist", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { Task { await model.refresh() } }.buttonStyle(.borderedProminent)
                if let playlist = model.activePlaylist { Button("Edit Playlist…") { model.editingPlaylist = playlist } }
            }
        default:
            if model.loaded == nil {
                ContentUnavailableView("No playlist selected", systemImage: "list.bullet.rectangle")
            } else {
                sectionContent
                    .navigationTitle(model.filterTitle)
                    .toolbar { viewToolbar }
            }
        }
    }

    @ViewBuilder private var sectionContent: some View {
        if let locked = model.selectedLockedCategory {
            LockedCategoryView(categoryID: locked)
        } else if model.filter == .continueWatching, !model.isSearching {
            ContinueWatchingGrid(entries: model.continueWatching)
        } else {
            switch model.section {
            case .live:
                let channels = model.visibleChannels
                BrowseCollection(items: channels, describe: model.entry(for:),
                                 onOpen: { model.play(channel: $0, in: channels) }) { channel in
                    Button("Play", systemImage: "play.fill") { model.play(channel: channel, in: channels) }
                    FavoriteButton(kind: .live, id: channel.id)
                    if model.filter == .recent {
                        Button("Remove from Recently Watched", systemImage: "minus.circle") { model.removeFromRecent(channel) }
                    }
                }
            case .movies:
                BrowseCollection(items: model.visibleMovies, describe: model.entry(for:),
                                 onOpen: { model.detailPath.append(.movie($0)) },
                                 onPlay: { model.play(movie: $0) }) { movie in
                    Button("Play", systemImage: "play.fill") { model.play(movie: movie) }
                    Button("Show Details", systemImage: "info.circle") { model.detailPath.append(.movie(movie)) }
                    FavoriteButton(kind: .movie, id: movie.id)
                    WatchedButton(isWatched: model.isWatched(.movie, movie.id)) { model.setWatched(movie: movie, $0) }
                }
            case .series:
                BrowseCollection(items: model.visibleSeries, describe: model.entry(for:),
                                 onOpen: { model.detailPath.append(.series($0)) }) { series in
                    Button("Open", systemImage: "info.circle") { model.detailPath.append(.series(series)) }
                    FavoriteButton(kind: .series, id: series.id)
                }
            }
        }
    }

    @ToolbarContentBuilder private var viewToolbar: some ToolbarContent {
        ToolbarItem {
            @Bindable var model = model
            Picker("Layout", selection: $model.layoutMode) {
                ForEach(LayoutMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.symbol).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelStyle(.iconOnly)
            .help("Layout: Grid (⌃⌘1), List (⌃⌘2), Compact (⌃⌘3)")
        }
        ToolbarItem {
            @Bindable var model = model
            Menu {
                Picker("Sort By", selection: $model.sortOrder) {
                    ForEach(BrowseSort.allCases.filter { model.section != .live || $0 == .provider || $0 == .title }) {
                        Text($0.label).tag($0)
                    }
                }
                .pickerStyle(.inline)
                if model.layoutMode == .grid {
                    Picker("Tile Size", selection: $model.tileSize) {
                        ForEach(TileSize.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                }
            } label: {
                Label("View Options", systemImage: "arrow.up.arrow.down")
            }
            .help("Sort and tile size")
        }
    }
}

struct EmptyResults: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.isSearching {
            ContentUnavailableView.search(text: model.searchText)
        } else if model.filter == .favorites {
            ContentUnavailableView("No favorites yet", systemImage: "star",
                                   description: Text("Right-click anything or use the star to add it here."))
        } else {
            ContentUnavailableView("Nothing here", systemImage: "tray")
        }
    }
}
