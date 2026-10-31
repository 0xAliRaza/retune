import AppKit
import OSLog
import RetuneCore

#if DEBUG
/// Developer hooks that run a stored playlist through the app's real code path without touching the UI.
/// They log health numbers only, never stream addresses, logins or titles.
///
///   Retune --probe refresh|live|movie|episode|resume [--probe-index 0] [--probe-seconds 30]
///   Retune --screens <folder>
///
/// `--probe` plays the chosen item and logs one line a second. It uses a null audio output, so it can't reach
/// the speakers, and because real catalogs can contain adult content and these runs are unattended, it only
/// picks from plainly family-safe categories. `--screens` writes a PNG of each main screen. Both quit when finished, so they can be scripted.
@MainActor
enum DevProbe {
    private static let log = Logger(subsystem: "io.github.0xaliraza.retune", category: "dev")
    private static let safeCategories = #"(?i)\b(news|kids|children|cartoons?|animation|family)\b"#
    private static let unsafeNames = #"(?i)adult|xxx|porn|18\+|erotic|sex"#

    static func startIfRequested(_ model: AppModel) {
        if let target = value(after: "--probe") {
            Task { await probe(target, model: model) }
        } else if let folder = value(after: "--screens") {
            Task { await captureScreens(to: URL(fileURLWithPath: folder), model: model) }
        }
    }

    private static func value(after flag: String) -> String? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    // MARK: Probe

    private static func probe(_ target: String, model: AppModel) async {
        guard let catalog = await waitForCatalog(model) else {
            log.notice("probe failed: no catalog after 180 s")
            return NSApp.terminate(nil)
        }
        log.notice("catalog channels=\(catalog.channels.count) movies=\(catalog.movies.count) series=\(catalog.series.count)")
        let index = value(after: "--probe-index").flatMap(Int.init) ?? 0
        guard await start(target, index: index, catalog: catalog, model: model) else {
            log.notice("probe failed: nothing to play for \(target, privacy: .public)")
            return NSApp.terminate(nil)
        }
        let seconds = value(after: "--probe-seconds").flatMap(Int.init) ?? 30
        for second in 1...seconds {
            try? await Task.sleep(for: .seconds(1))
            logHealth(second: second, model: model)
        }
        log.notice("probe done")
        NSApp.terminate(nil)
    }

    private static func waitForCatalog(_ model: AppModel) async -> Catalog? {
        for _ in 0..<1800 {
            if let catalog = model.loaded?.catalog { return catalog }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }

    private static func safeItems<Item>(_ items: [Item], in categories: [MediaCategory], categoryID: (Item) -> String?,
                                        name: (Item) -> String) -> [Item] {
        let allowed = Set(categories.filter { matches($0.name, safeCategories) && !matches($0.name, unsafeNames) }.map(\.id))
        return items.filter { item in
            categoryID(item).map(allowed.contains) == true && !matches(name(item), unsafeNames)
        }
    }

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }

    private static func start(_ target: String, index: Int, catalog: Catalog, model: AppModel) async -> Bool {
        switch target {
        case "refresh":
            await model.refresh()
            let age = model.loaded.map { Date.now.timeIntervalSince($0.catalog.fetchedAt) } ?? -1
            log.notice("refreshed catalog age=\(age, format: .fixed(precision: 0))s channels=\(model.loaded?.catalog.channels.count ?? 0)")
        case "live":
            model.section = .live
            let channels = safeItems(catalog.channels, in: catalog.liveCategories, categoryID: \.categoryID, name: \.name)
            guard let channel = channels.dropFirst(index).first else { return false }
            model.play(channel: channel, in: [channel])
        case "movie":
            model.section = .movies
            let movies = safeItems(catalog.movies, in: catalog.vodCategories, categoryID: \.categoryID, name: \.name)
            guard let movie = movies.dropFirst(index).first else { return false }
            model.play(movie: movie, in: [movie], resume: false)
        case "episode":
            model.section = .series
            let shows = safeItems(catalog.series, in: catalog.seriesCategories, categoryID: \.categoryID, name: \.name)
            guard let series = shows.dropFirst(index).first,
                  let detail = try? await model.seriesDetail(series),
                  let episode = detail.seasons.first?.episodes.first else { return false }
            model.play(episode: episode, of: series, seasons: detail.seasons, resume: false)
        case "resume":
            model.section = .movies
            let entries = model.continueWatching.filter { !matches($0.item.title, unsafeNames) }
            guard let entry = entries.dropFirst(index).first else { return false }
            log.notice("resuming saved position \(entry.position, format: .fixed(precision: 0))")
            model.resume(entry)
        default:
            return false
        }
        return true
    }

    private static func logHealth(second: Int, model: AppModel) {
        let engine = model.session.engine
        let stats = engine.readStats()
        log.notice("""
            t=\(second) pos=\(engine.position, format: .fixed(precision: 1)) dur=\(engine.duration, format: .fixed(precision: 0)) \
            ao=\(engine.audioOutput ?? "none", privacy: .public) visible=\(NSApp.windows.contains { $0.occlusionState.contains(.visible) }) frame=\(engine.hasVideoFrame) buffering=\(engine.isBuffering) cache=\(stats.cacheSeconds ?? -1, format: .fixed(precision: 1)) \
            netKBs=\((stats.networkSpeed ?? 0) / 1000, format: .fixed(precision: 0)) \
            fps=\(stats.outputFPS ?? 0, format: .fixed(precision: 1)) size=\(stats.width)x\(stats.height) hw=\(stats.isHardwareDecoding ?? false) \
            dropped=\(stats.droppedFrames) reconnects=\(model.session.reconnectAttempt) error=\(engine.errorMessage ?? "none", privacy: .public)
            """)
    }

    // MARK: Screens

    private static func captureScreens(to folder: URL, model: AppModel) async {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        _ = await waitForCatalog(model)
        for section in LibrarySection.allCases {
            model.section = section
            try? await Task.sleep(for: .seconds(3))
            snapshotKeyWindow(to: folder.appendingPathComponent("\(section.rawValue).png"))
        }
        model.editingPlaylist = model.activePlaylist
        try? await Task.sleep(for: .seconds(1.5))
        snapshotKeyWindow(to: folder.appendingPathComponent("playlist-form.png"))
        model.editingPlaylist = nil
        log.notice("screens done")
        NSApp.terminate(nil)
    }

    /// Captures the frontmost sheet if one is open, otherwise the main window.
    private static func snapshotKeyWindow(to url: URL) {
        guard let window = NSApp.windows.first(where: \.isVisible) else { return }
        guard let view = (window.attachedSheet ?? window).contentView?.superview,
              let image = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: image)
        try? image.representation(using: .png, properties: [:])?.write(to: url)
        log.notice("wrote \(url.lastPathComponent, privacy: .public)")
    }
}
#endif
