import LumenCore
import SwiftUI

/// Display-ready description of one channel, movie or series. Built lazily per visible cell.
struct BrowseEntry {
    enum Artwork { case poster, logo }

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

/// Renders any content list as a grid, a thumbnail list, or a compact list.
struct BrowseCollection<Item: Identifiable, Menu: View>: View where Item.ID == String {
    @Environment(AppModel.self) private var model
    let items: [Item]
    let describe: (Item) -> BrowseEntry
    /// Primary click: play for channels, open details for movies/series.
    let onOpen: (Item) -> Void
    /// Optional direct-play affordance shown on hover (movies).
    var onPlay: ((Item) -> Void)?
    @ViewBuilder let menu: (Item) -> Menu

    var body: some View {
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

    private var grid: some View {
        let columns = [GridItem(.adaptive(minimum: model.tileSize.minWidth, maximum: model.tileSize.minWidth * 1.35),
                                spacing: 20, alignment: .top)]
        return ScrollView {
            LazyVGrid(columns: columns, spacing: 24) {
                ForEach(items) { item in
                    let entry = describe(item)
                    tile(entry, item: item)
                        .onTapGesture { onOpen(item) }
                        .contextMenu { menu(item) }
                }
            }
            .padding(24)
        }
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
        }
    }

    private func list(compact: Bool) -> some View {
        List(items) { item in
            let entry = describe(item)
            Group {
                if compact { CompactRow(entry: entry) } else { ThumbnailRow(entry: entry) }
            }
            .contentShape(Rectangle())
            .onTapGesture { onOpen(item) }
            .contextMenu { menu(item) }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .environment(\.defaultMinListRowHeight, compact ? 24 : 44)
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

    func entry(for series: Series) -> BrowseEntry {
        let year = series.releaseDate.flatMap { MediaInfo(releaseDate: $0).year }
        let subtitle = [year, series.genre].compactMap { $0 }.joined(separator: " · ")
        return BrowseEntry(title: series.name, subtitle: subtitle.isEmpty ? nil : subtitle, image: series.cover,
                           rating: series.rating, isFavorite: isFavorite(.series, series.id), kind: .series, id: series.id)
    }
}
