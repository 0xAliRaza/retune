import LumenCore
import SwiftUI

struct FavoriteButton: View {
    @Environment(AppModel.self) private var model
    let kind: ContentKind
    let id: String

    var body: some View {
        let isFavorite = model.isFavorite(kind, id)
        Button(isFavorite ? "Remove from Favorites" : "Add to Favorites",
               systemImage: isFavorite ? "star.slash" : "star") { model.toggleFavorite(kind, id) }
    }
}

struct WatchedButton: View {
    let isWatched: Bool
    let setWatched: (Bool) -> Void

    var body: some View {
        Button(isWatched ? "Mark as Unwatched" : "Mark as Watched",
               systemImage: isWatched ? "eye.slash" : "checkmark.circle") { setWatched(!isWatched) }
    }
}

// MARK: - Poster card

struct PosterCard: View {
    let title: String
    let caption: String?
    let artwork: URL?
    let rating: Double?
    let progress: Double?
    let isFavorite: Bool
    let onPlay: (() -> Void)?
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RemoteImage(url: artwork, maxPixelSize: 420) { ArtworkPlaceholder(title: title) }
                .aspectRatio(2 / 3, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(.rect(cornerRadius: 10))
                .overlay(alignment: .topLeading) { badges }
                .overlay(alignment: .bottom) { progressBar }
                .overlay { hoverOverlay }
                .shadow(color: .black.opacity(isHovering ? 0.35 : 0.15), radius: isHovering ? 14 : 5, y: isHovering ? 8 : 3)
                .scaleEffect(isHovering ? 1.03 : 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.medium)).lineLimit(2)
                if let caption { Text(caption).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering } }
        .help(title)
    }

    @ViewBuilder private var badges: some View {
        HStack(spacing: 4) {
            if let rating {
                Label(Format.rating(rating), systemImage: "star.fill")
                    .font(.caption2.weight(.bold))
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(.black.opacity(0.6), in: .capsule)
                    .foregroundStyle(.yellow)
            }
            if isFavorite {
                Image(systemName: "heart.fill").font(.caption2).padding(5)
                    .background(.black.opacity(0.6), in: .circle).foregroundStyle(.pink)
            }
        }
        .padding(7)
    }

    @ViewBuilder private var progressBar: some View {
        if let progress, progress > 0.01 {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle().fill(.black.opacity(0.5))
                    Rectangle().fill(Color.accentColor).frame(width: proxy.size.width * progress)
                }
            }
            .frame(height: 4)
            .clipShape(.rect(bottomLeadingRadius: 10, bottomTrailingRadius: 10))
        }
    }

    @ViewBuilder private var hoverOverlay: some View {
        if isHovering, let onPlay {
            Button(action: onPlay) {
                Image(systemName: "play.fill")
                    .font(.title2)
                    .frame(width: 52, height: 52)
                    .background(.ultraThinMaterial, in: .circle)
            }
            .buttonStyle(.plain)
            .help("Play")
            .transition(.opacity.combined(with: .scale(scale: 0.8)))
        }
    }
}

// MARK: - Continue watching

struct ContinueWatchingGrid: View {
    @Environment(AppModel.self) private var model
    let entries: [WatchProgress]

    private let columns = [GridItem(.adaptive(minimum: 260, maximum: 340), spacing: 20, alignment: .top)]

    var body: some View {
        if entries.isEmpty {
            ContentUnavailableView("Nothing in progress", systemImage: "play.circle",
                                   description: Text("Movies and episodes you start will appear here so you can pick up where you left off."))
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 22) {
                    ForEach(entries, id: \.item.id) { entry in
                        Button { model.resume(entry) } label: { ResumeCard(entry: entry) }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Resume", systemImage: "play.fill") { model.resume(entry) }
                                Button("Remove from Continue Watching", systemImage: "minus.circle") {
                                    withAnimation { model.removeFromContinueWatching(entry) }
                                }
                            }
                    }
                }
                .padding(24)
            }
        }
    }
}

private struct ResumeCard: View {
    let entry: WatchProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RemoteImage(url: entry.item.artwork, maxPixelSize: 600) { ArtworkPlaceholder(title: entry.item.title) }
                .frame(height: 150)
                .frame(maxWidth: .infinity)
                .clipped()
                .clipShape(.rect(cornerRadius: 10))
                .overlay(alignment: .bottom) {
                    ProgressView(value: entry.fraction).tint(.accentColor).padding(10)
                }
                .overlay {
                    Image(systemName: "play.fill").font(.title2).foregroundStyle(.white)
                        .frame(width: 48, height: 48).background(.ultraThinMaterial, in: .circle)
                }
            Text(entry.item.title).font(.callout.weight(.medium)).lineLimit(1)
            Text([entry.item.subtitle, Format.remaining(entry.remaining)].compactMap { $0 }.joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}
