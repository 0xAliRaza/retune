import LumenCore
import SwiftUI

/// Display-ready description of one channel, movie or series. Built lazily per visible cell.
struct BrowseEntry {
    enum Artwork { case poster, logo, landscape }

    let title: String
    var subtitle: String?
    var number: Int?
    var image: URL?
    var artwork: Artwork = .poster
    var rating: Double?
    var progress: Double?
    var isFavorite = false
    var isPlaying = false
    var kind: ContentKind
    var id: String
}

/// Renders any content list as a grid, a thumbnail list, or a compact list. All three are lazy and share
/// one keyboard model (arrow keys move a focus highlight, Return opens).
struct BrowseCollection<Item: Identifiable, Menu: View>: View where Item.ID == String {
    @Environment(AppModel.self) private var model
    let items: [Item]
    let describe: (Item) -> BrowseEntry
    /// Primary click: play for channels, open details for movies/series.
    let onOpen: (Item) -> Void
    /// Optional direct-play affordance shown on hover (movies).
    var onPlay: ((Item) -> Void)?
    @ViewBuilder let menu: (Item) -> Menu
    @FocusState private var focusedID: String?
    /// Tile to return to when focus comes back into the content column.
    @State private var lastFocusedID: String?
    @State private var gridWidth: CGFloat = 0

    var body: some View {
        Group {
            if items.isEmpty {
                EmptyResults()
            } else {
                switch model.layoutMode {
                case .grid: grid
                case .list: list(compact: false)
                case .compact: list(compact: true)
                }
            }
        }
        .onChange(of: model.focusRequest) { if model.isRequested(.content) { takeFocus() } }
        .onAppear { if model.focusedPane == .content { takeFocus() } }
    }

    /// Focus the remembered (else first) item in whichever layout is showing.
    private func takeFocus() {
        guard !items.isEmpty else { return }
        let remembered = lastFocusedID.flatMap { id in items.contains { $0.id == id } ? id : nil }
        focusedID = remembered ?? items[0].id
    }

    private var tileMinimum: CGFloat {
        // Landscape cards (Continue Watching) need more width than portrait posters.
        items.first.map(describe)?.artwork == .landscape ? model.tileSize.minWidth * 1.7 : model.tileSize.minWidth
    }

    private var grid: some View {
        let minimum = tileMinimum
        let columns = [GridItem(.adaptive(minimum: minimum, maximum: minimum * 1.35), spacing: Self.gridSpacing, alignment: .top)]
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: 24) {
                    ForEach(items) { item in
                        tile(describe(item), item: item)
                            .padding(4)
                            .overlay {
                                // Visible keyboard focus; the system ring doesn't follow custom tile shapes.
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(Color.accentColor, lineWidth: 3)
                                    .opacity(focusedID == item.id ? 1 : 0)
                            }
                            .focusable()
                            .focusEffectDisabled()
                            .focused($focusedID, equals: item.id)
                            .onTapGesture { onOpen(item) }
                            .contextMenu { menu(item) }
                    }
                }
                .padding(Self.gridPadding)
                .background(GeometryReader { geometry in
                    Color.clear.onAppear { gridWidth = geometry.size.width }
                        .onChange(of: geometry.size.width) { gridWidth = geometry.size.width }
                })
            }
            .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow, .return]) { press in
                handleGridKey(press.key)
            }
            .onChange(of: focusedID) {
                guard let focusedID else { return }
                lastFocusedID = focusedID
                model.focusedPane = .content
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(focusedID) }
            }
        }
    }

    private static var gridSpacing: CGFloat { 20 }
    private static var gridPadding: CGFloat { 24 }

    private func handleGridKey(_ key: KeyEquivalent) -> KeyPress.Result {
        let index = focusedID.flatMap { id in items.firstIndex { $0.id == id } }
        if key == .return {
            guard let index else { return .ignored }
            onOpen(items[index])
            return .handled
        }
        let direction: GridNavigation.Direction = switch key {
        case .upArrow: .up
        case .downArrow: .down
        case .leftArrow: .left
        default: .right
        }
        let isGrid = model.layoutMode == .grid
        let columnCount = isGrid ? GridNavigation.columns(width: gridWidth - Self.gridPadding * 2, minimum: tileMinimum,
                                                          spacing: Self.gridSpacing) : 1
        // Lists only move vertically; → means nothing there and ← always leaves to the categories.
        if !isGrid, direction == .right { return .ignored }
        // Leaving the grid: ← from the first column goes to the categories, ↑ from the top row to search.
        if let index, GridNavigation.isAtEdge(index, direction, columns: columnCount) {
            if direction == .left { model.focus(.categories); return .handled }
            if direction == .up { model.focusSearch(); return .handled }
        }
        guard let target = GridNavigation.move(from: index, direction, columns: columnCount, count: items.count) else { return .ignored }
        focusedID = items[target].id
        return .handled
    }

    @ViewBuilder private func tile(_ entry: BrowseEntry, item: Item) -> some View {
        switch entry.artwork {
        case .poster:
            // Movie subtitles ("Added …") are list metadata; posters stay clean.
            PosterCard(title: entry.title, caption: entry.kind == .movie ? nil : entry.subtitle, artwork: entry.image, rating: entry.rating,
                       progress: entry.progress, isFavorite: entry.isFavorite,
                       onPlay: onPlay.map { play in { play(item) } })
        case .logo:
            LogoTile(entry: entry)
        case .landscape:
            LandscapeTile(entry: entry)
        }
    }

    /// Rows render lazily like the grid: SwiftUI's `List` walks every row identity up front, which froze
    /// the UI for ~1 s when opening Live TV "All" (16k channels). Keyboard focus reuses the grid's logic
    /// with a single column.
    private func list(compact: Bool) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { offset, item in
                        let entry = describe(item)
                        Group {
                            if compact { CompactRow(entry: entry) } else { ThumbnailRow(entry: entry) }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, compact ? 3 : 2)
                        .frame(maxWidth: .infinity, minHeight: compact ? 26 : 46, alignment: .leading)
                        .background(rowBackground(offset: offset, isFocused: focusedID == item.id))
                        .contentShape(Rectangle())
                        .focusable()
                        .focusEffectDisabled()
                        .focused($focusedID, equals: item.id)
                        .onTapGesture { onOpen(item) }
                        .contextMenu { menu(item) }
                    }
                }
                .padding(.vertical, 6)
            }
            .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow, .return]) { press in
                handleGridKey(press.key)
            }
            .onChange(of: focusedID) {
                guard let focusedID else { return }
                lastFocusedID = focusedID
                model.focusedPane = .content
                proxy.scrollTo(focusedID)
            }
        }
    }

    private func rowBackground(offset: Int, isFocused: Bool) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(isFocused ? AnyShapeStyle(Color.accentColor.opacity(0.28))
                            : offset.isMultiple(of: 2) ? AnyShapeStyle(.clear) : AnyShapeStyle(.quaternary.opacity(0.35)))
            .padding(.horizontal, 6)
    }
}

// MARK: - Cells

/// Channel logo tile for grid layout.
private struct LogoTile: View {
    let entry: BrowseEntry
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RemoteImage(url: entry.image, maxPixelSize: 300, contentMode: .fit) {
                ArtworkPlaceholder(title: entry.title, symbol: "tv")
            }
            .padding(entry.image == nil ? 0 : 16)
            .frame(maxWidth: .infinity)
            .aspectRatio(16 / 10, contentMode: .fit)
            .background(.quaternary.opacity(0.6))
            .clipShape(.rect(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(entry.isPlaying ? Color.accentColor : .clear, lineWidth: 2.5)
            }
            .overlay(alignment: .topTrailing) {
                if entry.isFavorite {
                    Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow).padding(7)
                }
            }
            .overlay {
                if isHovering {
                    Image(systemName: "play.fill").font(.title3).frame(width: 40, height: 40)
                        .background(.ultraThinMaterial, in: .circle)
                }
            }
            .shadow(color: .black.opacity(isHovering ? 0.25 : 0.08), radius: isHovering ? 10 : 3, y: 2)
            HStack(spacing: 6) {
                if let number = entry.number {
                    Text("\(number)").font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                }
                Text(entry.title).font(.callout.weight(entry.isPlaying ? .semibold : .medium)).lineLimit(2)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering } }
        .help(entry.title)
    }
}

/// Wide card with progress, used for Continue Watching.
private struct LandscapeTile: View {
    let entry: BrowseEntry
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // A fixed 16:9 box with the artwork filling it; sizing the image itself lets odd-shaped
            // artwork (portrait posters, tall stills) overflow into neighbouring cards.
            Color.clear
                .aspectRatio(16 / 9, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .overlay {
                    RemoteImage(url: entry.image, maxPixelSize: 600) { ArtworkPlaceholder(title: entry.title) }
                }
                .clipShape(.rect(cornerRadius: 10))
                .overlay(alignment: .bottom) {
                    if let progress = entry.progress {
                        ProgressView(value: progress).tint(.accentColor).padding(10)
                    }
                }
                .overlay {
                    Image(systemName: "play.fill").font(.title2).foregroundStyle(.white)
                        .frame(width: 48, height: 48).background(.ultraThinMaterial, in: .circle)
                        .opacity(isHovering ? 1 : 0.85)
                }
                .shadow(color: .black.opacity(isHovering ? 0.3 : 0.12), radius: isHovering ? 12 : 4, y: 3)
            Text(entry.title).font(.callout.weight(.medium)).lineLimit(1)
            if let subtitle = entry.subtitle {
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering } }
    }
}

/// List row with a small artwork thumbnail on the left.
private struct ThumbnailRow: View {
    @Environment(AppModel.self) private var model
    let entry: BrowseEntry
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            if let number = entry.number {
                Text("\(number)").font(.callout.monospacedDigit()).foregroundStyle(.tertiary)
                    .frame(width: 44, alignment: .trailing)
            }
            thumbnail
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).font(.body.weight(entry.isPlaying ? .semibold : .regular)).lineLimit(1)
                if entry.isPlaying {
                    Text("Now playing").font(.caption).foregroundStyle(Color.accentColor)
                } else if let subtitle = entry.subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let progress = entry.progress, progress > 0.01 {
                ProgressView(value: progress).frame(width: 60).tint(.accentColor)
            }
            if let rating = entry.rating { RatingLabel(rating: rating) }
            FavoriteStar(entry: entry, alwaysVisible: isHovering)
            Image(systemName: entry.isPlaying ? "speaker.wave.2.fill" : "play.fill")
                .foregroundStyle(entry.isPlaying ? Color.accentColor : .secondary)
                .opacity(entry.isPlaying || isHovering ? 1 : 0)
        }
        .padding(.vertical, 3)
        .onHover { isHovering = $0 }
    }

    @ViewBuilder private var thumbnail: some View {
        switch entry.artwork {
        case .logo:
            RemoteImage(url: entry.image, maxPixelSize: 120, contentMode: .fit) {
                Image(systemName: "tv").foregroundStyle(.tertiary)
            }
            .frame(width: 56, height: 34)
            .padding(4)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 6))
        case .poster:
            RemoteImage(url: entry.image, maxPixelSize: 140) { ArtworkPlaceholder(title: entry.title) }
                .frame(width: 40, height: 60)
                .clipShape(.rect(cornerRadius: 5))
        case .landscape:
            RemoteImage(url: entry.image, maxPixelSize: 200) { ArtworkPlaceholder(title: entry.title) }
                .frame(width: 80, height: 45)
                .clipShape(.rect(cornerRadius: 5))
        }
    }
}

/// Text-only row for scanning long lists quickly.
private struct CompactRow: View {
    let entry: BrowseEntry
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            if let number = entry.number {
                Text("\(number)").font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                    .frame(width: 40, alignment: .trailing)
            }
            if entry.isPlaying {
                Image(systemName: "speaker.wave.2.fill").font(.caption).foregroundStyle(Color.accentColor)
            }
            Text(entry.title).font(.callout.weight(entry.isPlaying ? .semibold : .regular)).lineLimit(1)
            Spacer(minLength: 8)
            if let subtitle = entry.subtitle {
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            if let progress = entry.progress, progress > 0.01 {
                Text("\(Int(progress * 100))%").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            if let rating = entry.rating { RatingLabel(rating: rating).font(.caption) }
            FavoriteStar(entry: entry, alwaysVisible: isHovering).font(.caption)
        }
        .onHover { isHovering = $0 }
    }
}

private struct RatingLabel: View {
    let rating: Double

    var body: some View {
        Label(Format.rating(rating), systemImage: "star.fill")
            .labelStyle(.titleAndIcon)
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
    }
}

/// Favorite toggle that stays visible when set and appears on hover otherwise.
private struct FavoriteStar: View {
    @Environment(AppModel.self) private var model
    let entry: BrowseEntry
    let alwaysVisible: Bool

    var body: some View {
        Button { model.toggleFavorite(entry.kind, entry.id) } label: {
            Image(systemName: entry.isFavorite ? "star.fill" : "star")
                .foregroundStyle(entry.isFavorite ? .yellow : .secondary)
        }
        .buttonStyle(.borderless)
        .opacity(entry.isFavorite || alwaysVisible ? 1 : 0)
        .help(entry.isFavorite ? "Remove from Favorites" : "Add to Favorites")
    }
}

// MARK: - Entry builders

extension AppModel {
    func entry(for channel: Channel) -> BrowseEntry {
        BrowseEntry(title: channel.name, number: channel.number, image: channel.logo, artwork: .logo,
                    isFavorite: isFavorite(.live, channel.id),
                    isPlaying: session.current?.isLive == true && session.current?.streamID == channel.id,
                    kind: .live, id: channel.id)
    }

    func entry(for movie: Movie) -> BrowseEntry {
        BrowseEntry(title: movie.name, subtitle: movie.added.map { "Added \($0.formatted(date: .abbreviated, time: .omitted))" },
                    image: movie.poster, rating: movie.rating, progress: progress(.movie, movie.id)?.fraction,
                    isFavorite: isFavorite(.movie, movie.id),
                    isPlaying: session.current?.kind == .movie && session.current?.id == movie.id,
                    kind: .movie, id: movie.id)
    }

    func entry(for resume: ResumeEntry) -> BrowseEntry {
        let item = resume.progress.item
        let detail = [item.subtitle, Format.remaining(resume.progress.remaining)].compactMap { $0 }.joined(separator: " · ")
        return BrowseEntry(title: item.title, subtitle: detail, image: item.artwork, artwork: .landscape,
                           progress: resume.progress.fraction, kind: item.kind, id: item.id)
    }

    func entry(for series: Series) -> BrowseEntry {
        let year = series.releaseDate.flatMap { MediaInfo(releaseDate: $0).year }
        let subtitle = [year, series.genre].compactMap { $0 }.joined(separator: " · ")
        return BrowseEntry(title: series.name, subtitle: subtitle.isEmpty ? nil : subtitle, image: series.cover,
                           rating: series.rating, isFavorite: isFavorite(.series, series.id), kind: .series, id: series.id)
    }
}

/// Continue Watching row: one resumable title.
struct ResumeEntry: Identifiable {
    let progress: WatchProgress
    var id: String { progress.item.id }
}
