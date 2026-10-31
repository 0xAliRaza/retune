import RetuneCore
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
            // Fixed 2:3 box; the artwork fills and is clipped to it whatever its own shape.
            Color.clear
                .aspectRatio(2 / 3, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .overlay { RemoteImage(url: artwork, maxPixelSize: 420) { ArtworkPlaceholder(title: title) } }
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
