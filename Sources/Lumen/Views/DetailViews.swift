import LumenCore
import SwiftUI

/// Shared hero layout: blurred backdrop, poster, title, metadata and actions.
private struct DetailHero<Actions: View>: View {
    let title: String
    let poster: URL?
    let backdrop: URL?
    let info: MediaInfo?
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImage(url: backdrop ?? poster, maxPixelSize: 1600) { Color.black.opacity(0.4) }
                .frame(height: 420)
                .frame(maxWidth: .infinity)
                .clipped()
                .overlay {
                    LinearGradient(colors: [.clear, Color(nsColor: .windowBackgroundColor).opacity(0.85), Color(nsColor: .windowBackgroundColor)],
                                   startPoint: .top, endPoint: .bottom)
                }
            HStack(alignment: .bottom, spacing: 28) {
                RemoteImage(url: poster, maxPixelSize: 600) { ArtworkPlaceholder(title: title) }
                    .frame(width: 190, height: 285)
                    .clipShape(.rect(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.4), radius: 18, y: 10)
                VStack(alignment: .leading, spacing: 12) {
                    Text(title).font(.system(size: 34, weight: .bold)).lineLimit(3)
                    if let info { MetadataLine(info: info) }
                    actions()
                }
                Spacer(minLength: 0)
            }
            .padding(32)
        }
    }
}

private struct MetadataLine: View {
    let info: MediaInfo

    var body: some View {
        HStack(spacing: 10) {
            if let rating = info.rating {
                Label(Format.rating(rating), systemImage: "star.fill").foregroundStyle(.yellow)
            }
            if let year = info.year { Text(year) }
            if let duration = info.durationSeconds, duration > 0 { Text(Format.runtime(duration)) }
            if let genre = info.genre { Text(genre).lineLimit(1) }
        }
        .font(.callout.weight(.medium))
        .foregroundStyle(.secondary)
    }
}

private struct InfoBlock: View {
    let info: MediaInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let plot = info.plot {
                Text(plot).font(.body).lineSpacing(3).frame(maxWidth: 760, alignment: .leading).textSelection(.enabled)
            }
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                if let cast = info.cast { row("Cast", cast) }
                if let director = info.director { row("Director", director) }
                if let release = info.releaseDate { row("Released", release) }
            }
            .font(.callout)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).lineLimit(2).textSelection(.enabled)
        }
    }
}

// MARK: - Movie

struct MovieDetailView: View {
    @Environment(AppModel.self) private var model
    let movie: Movie
    @State private var info: MediaInfo?

    var body: some View {
        let progress = model.progress(.movie, movie.id)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                DetailHero(title: movie.name, poster: info?.poster ?? movie.poster, backdrop: info?.backdrop,
                           info: info ?? MediaInfo(rating: movie.rating)) {
                    HStack(spacing: 10) {
                        if let progress, progress.isResumable {
                            Button { model.play(movie: movie, resume: true) } label: {
                                Label("Resume · \(Format.remaining(progress.remaining))", systemImage: "play.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            Button { model.play(movie: movie, resume: false) } label: { Label("Start Over", systemImage: "gobackward") }
                        } else {
                            Button { model.play(movie: movie, resume: false) } label: { Label("Play", systemImage: "play.fill") }
                                .buttonStyle(.borderedProminent)
                        }
                        FavoriteToggle(kind: .movie, id: movie.id)
                        TrailerButton(youtubeID: info?.youtubeTrailer)
                    }
                    .controlSize(.large)
                }
                if let info { InfoBlock(info: info).padding(.horizontal, 32) }
            }
            .padding(.bottom, 32)
        }
        .ignoresSafeArea(edges: .top)
        .navigationTitle(movie.name)
        .task(id: movie.id) { info = await model.movieInfo(movie) }
    }
}

// MARK: - Series

struct SeriesDetailView: View {
    @Environment(AppModel.self) private var model
    let series: Series
    @State private var detail: SeriesDetail?
    @State private var error: String?
    @State private var seasonNumber: Int?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                DetailHero(title: series.name, poster: series.cover, backdrop: detail?.info.backdrop ?? series.backdrop,
                           info: detail?.info ?? MediaInfo(genre: series.genre, releaseDate: series.releaseDate, rating: series.rating)) {
                    HStack(spacing: 10) {
                        if let (episode, label) = primaryEpisode {
                            Button { play(episode) } label: { Label(label, systemImage: "play.fill") }
                                .buttonStyle(.borderedProminent)
                        }
                        FavoriteToggle(kind: .series, id: series.id)
                        TrailerButton(youtubeID: detail?.info.youtubeTrailer)
                    }
                    .controlSize(.large)
                }
                VStack(alignment: .leading, spacing: 24) {
                    InfoBlock(info: detail?.info ?? MediaInfo(plot: series.plot))
                    episodesSection
                }
                .padding(.horizontal, 32)
            }
            .padding(.bottom, 32)
        }
        .ignoresSafeArea(edges: .top)
        .navigationTitle(series.name)
        .task(id: series.id) { await load() }
    }

    @ViewBuilder private var episodesSection: some View {
        if let detail {
            if detail.seasons.isEmpty {
                Text("No episodes available yet.").foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Episodes").font(.title2.weight(.semibold))
                        Spacer()
                        if detail.seasons.count > 1 {
                            Picker("Season", selection: Binding(get: { selectedSeason?.number ?? 0 }, set: { seasonNumber = $0 })) {
                                ForEach(detail.seasons) { Text($0.name).tag($0.number) }
                            }
                            .fixedSize()
                        }
                    }
                    LazyVStack(spacing: 10) {
                        ForEach(selectedSeason?.episodes ?? []) { episode in
                            EpisodeRow(episode: episode, fallbackArtwork: series.cover,
                                       progress: model.progress(.episode, episode.id)) { play(episode) }
                                .contextMenu {
                                    Button("Play", systemImage: "play.fill") { play(episode) }
                                    WatchedButton(isWatched: model.isWatched(.episode, episode.id)) {
                                        model.setWatched(episode: episode, of: series, $0)
                                    }
                                }
                        }
                    }
                }
            }
        } else if let error {
            ContentUnavailableView {
                Label("Couldn't load episodes", systemImage: "exclamationmark.triangle")
            } description: { Text(error) } actions: {
                Button("Try Again") { Task { await load() } }
            }
        } else {
            ProgressView("Loading episodes…").frame(maxWidth: .infinity).padding(40)
        }
    }

    private var selectedSeason: Season? {
        guard let detail else { return nil }
        return detail.seasons.first { $0.number == seasonNumber } ?? detail.seasons.first
    }

    /// "Resume S1 E3" if something is in progress, otherwise the first episode.
    private var primaryEpisode: (Episode, String)? {
        guard let detail else { return nil }
        let all = detail.seasons.flatMap(\.episodes)
        let inProgress = all
            .compactMap { episode in model.progress(.episode, episode.id).map { (episode, $0) } }
            .filter { $0.1.isResumable }
            .max { $0.1.updatedAt < $1.1.updatedAt }
        if let (episode, _) = inProgress { return (episode, "Resume S\(episode.season) E\(episode.number)") }
        return all.first.map { ($0, "Play S\($0.season) E\($0.number)") }
    }

    private func play(_ episode: Episode) {
        guard let detail else { return }
        model.play(episode: episode, of: series, seasons: detail.seasons)
    }

    private func load() async {
        error = nil
        do {
            let loaded = try await model.seriesDetail(series)
            detail = loaded
            if seasonNumber == nil { seasonNumber = primaryEpisode?.0.season ?? loaded.seasons.first?.number }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct EpisodeRow: View {
    let episode: Episode
    let fallbackArtwork: URL?
    let progress: WatchProgress?
    let onPlay: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: onPlay) {
            HStack(alignment: .top, spacing: 16) {
                RemoteImage(url: episode.image ?? fallbackArtwork, maxPixelSize: 480) { ArtworkPlaceholder(title: episode.title, symbol: "play.rectangle") }
                    .frame(width: 200, height: 112)
                    .clipShape(.rect(cornerRadius: 8))
                    .overlay(alignment: .bottom) {
                        if let progress, progress.fraction > 0.01 {
                            ProgressView(value: progress.fraction).tint(.accentColor).padding(6)
                        }
                    }
                    .overlay {
                        if isHovering {
                            Image(systemName: "play.fill").font(.title3).foregroundStyle(.white)
                                .frame(width: 40, height: 40).background(.ultraThinMaterial, in: .circle)
                        }
                    }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("\(episode.number). \(episode.title)").font(.headline).lineLimit(1)
                        Spacer()
                        if let duration = episode.durationSeconds, duration > 0 {
                            Text(Format.runtime(duration)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let plot = episode.plot {
                        Text(plot).font(.callout).foregroundStyle(.secondary).lineLimit(3)
                    }
                    if let progress, progress.isFinished {
                        Label("Watched", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
                    }
                }
            }
            .padding(10)
            .background(isHovering ? AnyShapeStyle(.quaternary.opacity(0.6)) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

private struct FavoriteToggle: View {
    @Environment(AppModel.self) private var model
    let kind: ContentKind
    let id: String

    var body: some View {
        let isFavorite = model.isFavorite(kind, id)
        Button { model.toggleFavorite(kind, id) } label: {
            Label(isFavorite ? "Favorited" : "Favorite", systemImage: isFavorite ? "heart.fill" : "heart")
        }
        .tint(isFavorite ? .pink : nil)
    }
}

private struct TrailerButton: View {
    @Environment(\.openURL) private var openURL
    let youtubeID: String?

    var body: some View {
        if let youtubeID, let url = URL(string: "https://www.youtube.com/watch?v=\(youtubeID)") {
            Button { openURL(url) } label: { Label("Trailer", systemImage: "play.rectangle") }
        }
    }
}
