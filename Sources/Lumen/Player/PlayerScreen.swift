import AppKit
import LumenCore
import SwiftUI

struct PlayerScreen: View {
    @Environment(AppModel.self) private var model
    @State private var controlsVisible = true
    @State private var hideTask: Task<Void, Never>?
    @State private var showQueue = false
    @State private var window: NSWindow?
    @State private var keyMonitor: Any?
    @State private var swipeMonitor: SwipeBackMonitor?
    @State private var flash: String?
    @State private var showStats = false
    @State private var stats = PlaybackStats()
    /// Mid-playback stalls only show a spinner if they outlast a blink, so quick seeks don't flicker.
    @State private var showBufferingSpinner = false
    /// Whether the player itself put the window into full screen, so closing can undo only that.
    @State private var enteredFullScreen = false

    private var session: PlaybackSession { model.session }
    private var engine: MPVPlayer { model.session.engine }

    var body: some View {
        ZStack {
            Color.black
            VideoSurface(view: session.videoView)
                .onTapGesture(count: 2) { toggleFullScreen() }
                .onTapGesture { engine.togglePause(); pokeControls() }

            statusOverlay

            if controlsVisible || engine.isPaused {
                VStack(spacing: 0) {
                    PlayerTopBar(onClose: close, showQueue: $showQueue)
                    Spacer()
                    PlayerBottomBar(onFullScreen: toggleFullScreen, showStats: $showStats, stats: stats)
                }
                .transition(.opacity)
            }

            if showQueue, session.queue.count > 1 {
                HStack { Spacer(); QueueDrawer(onPick: { showQueue = false }) }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            if showStats {
                StatsPanel(stats: stats)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.leading, 24).padding(.top, 120)
                    .transition(.opacity)
            }

            if let countdown = session.autoplayCountdown, let next = session.nextItem {
                UpNextCard(item: next, seconds: countdown)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, 28).padding(.bottom, 120)
            }

            if let flash {
                Text(flash)
                    .font(.title2.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .glassPanel()
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .background(WindowAccessor(window: $window))
        .onContinuousHover { phase in
            if case .active = phase { pokeControls() }
        }
        .animation(.easeInOut(duration: 0.2), value: controlsVisible)
        .animation(.easeInOut(duration: 0.25), value: showQueue)
        .animation(.easeInOut(duration: 0.2), value: flash)
        .animation(.easeInOut(duration: 0.2), value: showStats)
        .animation(.easeInOut(duration: 0.3), value: engine.hasVideoFrame)
        .animation(.easeInOut(duration: 0.2), value: showBufferingSpinner)
        .task(id: engine.isBuffering && engine.hasVideoFrame) {
            guard engine.isBuffering, engine.hasVideoFrame else { showBufferingSpinner = false; return }
            try? await Task.sleep(for: .milliseconds(250))
            if !Task.isCancelled { showBufferingSpinner = true }
        }
        .onAppear {
            installKeyMonitor()
            pokeControls()
            let monitor = SwipeBackMonitor(canGoBack: { true }, onBack: { close() })
            monitor.start(window: { window })
            swipeMonitor = monitor
        }
        .task {
            // One poll feeds both the control-bar readout and the detailed panel.
            while !Task.isCancelled {
                stats = engine.readStats()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .onDisappear {
            removeKeyMonitor()
            swipeMonitor?.stop()
            NSCursor.unhide()
        }
    }

    // MARK: Overlays

    @ViewBuilder private var statusOverlay: some View {
        if let error = engine.errorMessage {
            VStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 40)).foregroundStyle(.yellow)
                Text(error).multilineTextAlignment(.center).frame(maxWidth: 420)
                HStack {
                    Button("Try Again") { session.retry() }.buttonStyle(.borderedProminent)
                    if session.current?.isLive == true, session.hasNext || session.hasPrevious {
                        Button("Next Channel") { session.playNext() }
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(28)
            .glassPanel(cornerRadius: 20)
        } else if !engine.hasVideoFrame, let item = session.current {
            TuningCard(item: item)
                .transition(.opacity)
        } else if showBufferingSpinner {
            ProgressView().controlSize(.large).tint(.white)
                .padding(18)
                .background(.black.opacity(0.35), in: .circle)
                .transition(.opacity)
        }
    }

    // MARK: Behaviour

    private func pokeControls() {
        controlsVisible = true
        NSCursor.unhide()
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, !engine.isPaused, !showQueue else { return }
            controlsVisible = false
            NSCursor.setHiddenUntilMouseMoves(true)
        }
    }

    private func showFlash(_ text: String) {
        flash = text
        Task {
            try? await Task.sleep(for: .seconds(1))
            if flash == text { flash = nil }
        }
    }

    private var isFullScreen: Bool { window?.styleMask.contains(.fullScreen) == true }

    private func toggleFullScreen() {
        enteredFullScreen = !isFullScreen
        window?.toggleFullScreen(nil)
    }

    /// Fades back to browsing with the video still running, then stops playback.
    /// Leaves full screen afterwards, and only if the player entered it.
    private func close() {
        let exitFullScreen = enteredFullScreen && isFullScreen
        let window = window
        let session = session
        withAnimation(.easeInOut(duration: 0.28)) {
            model.isPlayerPresented = false
        } completion: {
            session.stop()
            if exitFullScreen { window?.toggleFullScreen(nil) }
        }
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.window === window, !event.modifierFlags.contains(.command) else { return event }
            // Typing into a field (e.g. the list panel's search) must not trigger player shortcuts.
            if event.window?.firstResponder is NSTextView, event.keyCode != 53 { return event }
            return handleKey(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// Space play/pause · ←/→ seek · ↑/↓ previous/next item · F fullscreen · M mute · L channels · ⌫ last channel · [ ] \\ speed · I stats · ? shortcuts · Esc back.
    private func handleKey(_ event: NSEvent) -> Bool {
        let isLive = session.current?.isLive == true
        pokeControls()
        if event.characters == "?" { model.isShowingShortcuts = true; return true }
        switch event.keyCode {
        case 49: engine.togglePause(); return true
        case 123: if !isLive { engine.seek(by: event.modifierFlags.contains(.shift) ? -60 : -10); showFlash("−\(event.modifierFlags.contains(.shift) ? 60 : 10)s") }; return true
        case 124: if !isLive { engine.seek(by: event.modifierFlags.contains(.shift) ? 60 : 10); showFlash("+\(event.modifierFlags.contains(.shift) ? 60 : 10)s") }; return true
        case 126: session.playPrevious(); return true
        case 125: session.playNext(); return true
        case 51: if isLive { session.playLastChannel() }; return true
        case 116: session.playPrevious(); return true
        case 121: session.playNext(); return true
        case 53:
            if showQueue { showQueue = false } else if showStats { showStats = false } else { close() }
            return true
        default: break
        }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "f": toggleFullScreen(); return true
        case "m": engine.setMuted(!engine.isMuted); showFlash(engine.isMuted ? "Sound On" : "Muted"); return true
        case "l": if session.queue.count > 1 { showQueue.toggle() }; return true
        case "n": if event.modifierFlags.contains(.shift) { session.playPrevious() } else { session.playNext() }; return true
        case "s": engine.screenshot(); showFlash("Screenshot saved to Desktop"); return true
        case "i": showStats.toggle(); return true
        case "[": if !isLive { changeSpeed(by: -1) }; return true
        case "]": if !isLive { changeSpeed(by: 1) }; return true
        case "\\": if !isLive { engine.setSpeed(1); showFlash("Speed 1×") }; return true
        case "+", "=": changeVolume(5); return true
        case "-": changeVolume(-5); return true
        default: return false
        }
    }

    /// Steps through the same presets as the speed menu.
    private func changeSpeed(by step: Int) {
        let presets = PlayerSpeeds.presets
        let current = presets.firstIndex { $0 >= engine.speed - 0.01 } ?? presets.firstIndex(of: 1)!
        let next = presets[min(max(current + step, 0), presets.count - 1)]
        engine.setSpeed(next)
        showFlash("Speed \(next.formatted())×")
    }

    private func changeVolume(_ delta: Double) {
        engine.setVolume(engine.volume + delta)
        showFlash("Volume \(Int(engine.volume))%")
    }
}

// MARK: - Bars

private struct PlayerTopBar: View {
    @Environment(AppModel.self) private var model
    let onClose: () -> Void
    @Binding var showQueue: Bool

    var body: some View {
        let session = model.session
        HStack(alignment: .top, spacing: 14) {
            if let item = session.current {
                if item.isLive, item.artwork != nil {
                    RemoteImage(url: item.artwork, maxPixelSize: 160, contentMode: .fit) { EmptyView() }
                        .frame(width: 64, height: 40)
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        if item.isLive {
                            Text("LIVE").font(.caption2.weight(.heavy)).padding(.horizontal, 6).padding(.vertical, 2)
                                .background(.red, in: .rect(cornerRadius: 4))
                        }
                        Text(item.title).font(.title3.weight(.semibold)).lineLimit(1)
                        if let size = session.engine.videoSize,
                           let quality = VideoQuality.label(width: Int(size.width), height: Int(size.height)) {
                            Text(quality).font(.caption2.weight(.bold)).padding(.horizontal, 5).padding(.vertical, 2)
                                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.white.opacity(0.7), lineWidth: 1))
                        }
                        if session.engine.hasNoAudio {
                            Label("No audio in this stream", systemImage: "speaker.slash.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.orange)
                                .help("The provider is sending this channel without a sound track.")
                        }
                    }
                    if let now = session.nowPlaying {
                        Text("Now: \(now.title) · \(Format.timeRange(now.start, now.end))").font(.callout).lineLimit(1)
                        if let next = session.upNext {
                            Text("Next: \(next.title) at \(Format.time(next.start))").font(.caption).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                        }
                    } else if let subtitle = item.subtitle {
                        Text(subtitle).font(.callout).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
                    }
                }
            }
            Spacer()
            if session.queue.count > 1 {
                Button { showQueue.toggle() } label: { Image(systemName: "list.bullet") }
                    .help(session.current?.isLive == true ? "Channel list (L)" : "Up next (L)")
            }
            Button(action: onClose) { Image(systemName: "chevron.down") }
                .help("Back to browsing (Esc)")
        }
        .buttonStyle(PlayerIconButtonStyle())
        .foregroundStyle(.white)
        .padding(.horizontal, 24).padding(.top, 30).padding(.bottom, 40)
        .background(LinearGradient(colors: [.black.opacity(0.75), .clear], startPoint: .top, endPoint: .bottom))
    }
}

private struct PlayerBottomBar: View {
    @Environment(AppModel.self) private var model
    let onFullScreen: () -> Void
    @Binding var showStats: Bool
    let stats: PlaybackStats

    var body: some View {
        let session = model.session
        let engine = session.engine
        let isLive = session.current?.isLive == true

        VStack(spacing: 10) {
            if !isLive, engine.isSeekable { Scrubber() }
            HStack(spacing: 6) {
                // Same layout for live and on-demand: previous · (−10s) · play · (+10s) · next.
                Button { session.playPrevious() } label: { Image(systemName: "backward.end.fill") }
                    .help("Previous (↑)").disabled(!session.hasPrevious && !isLive)
                if engine.isSeekable {
                    Button { engine.seek(by: -10) } label: { Image(systemName: "gobackward.10") }.help("Back 10 seconds (←)")
                }
                Button { engine.togglePause() } label: {
                    Image(systemName: engine.isPaused ? "play.fill" : "pause.fill").font(.title2).frame(width: 30)
                }
                .help(engine.isPaused ? "Play (Space)" : "Pause (Space)")
                if engine.isSeekable {
                    Button { engine.seek(by: 10) } label: { Image(systemName: "goforward.10") }.help("Forward 10 seconds (→)")
                }
                Button { session.playNext() } label: { Image(systemName: "forward.end.fill") }
                    .help("Next (↓)").disabled(!session.hasNext && !isLive)
                VolumeControl().padding(.leading, 8)
                Spacer()
                if let readout = readout {
                    Text(readout)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.trailing, 4)
                }
                TrackMenus()
                Button { showStats.toggle() } label: { Image(systemName: showStats ? "info.circle.fill" : "info.circle") }
                    .help("Stats for nerds (I)")
                Button(action: onFullScreen) { Image(systemName: "arrow.up.left.and.arrow.down.right") }.help("Full screen (F)")
            }
        }
        .buttonStyle(PlayerIconButtonStyle())
        .foregroundStyle(.white)
        .padding(.horizontal, 18).padding(.vertical, 14)
        .glassPanel(cornerRadius: 18)
        .environment(\.colorScheme, .dark)
        .padding(.horizontal, 24).padding(.bottom, 24)
    }

    /// "1080p · 25 fps" — just enough to judge the stream at a glance.
    private var readout: String? {
        let parts = [stats.qualityLabel, (stats.sourceFPS ?? stats.outputFPS).map { String(format: "%.0f fps", $0) }]
        let text = parts.compactMap { $0 }.joined(separator: " · ")
        return text.isEmpty ? nil : text
    }
}

private struct Scrubber: View {
    @Environment(AppModel.self) private var model
    @State private var dragValue: Double?
    @State private var hoverFraction: Double?

    var body: some View {
        let engine = model.session.engine
        let duration = max(engine.duration, 1)
        let current = dragValue ?? engine.position
        HStack(spacing: 12) {
            Text(Format.clock(current)).frame(minWidth: 56, alignment: .trailing)
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.2))
                    Capsule().fill(.white.opacity(0.35))
                        .frame(width: width * min((engine.position + engine.bufferedAhead) / duration, 1))
                    Capsule().fill(Color.accentColor).frame(width: width * min(current / duration, 1))
                    Circle().fill(.white).frame(width: 14, height: 14)
                        .offset(x: width * min(current / duration, 1) - 7)
                        .shadow(radius: 2)
                    if let hoverFraction, dragValue == nil {
                        Text(Format.clock(hoverFraction * duration))
                            .font(.caption.monospacedDigit())
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(.black.opacity(0.75), in: .rect(cornerRadius: 5))
                            .offset(x: min(max(width * hoverFraction - 28, 0), width - 56), y: -24)
                    }
                }
                .frame(height: 6)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { dragValue = min(max($0.location.x / width, 0), 1) * duration }
                    .onEnded { _ in
                        if let dragValue { engine.seek(to: dragValue) }
                        dragValue = nil
                    })
                .onContinuousHover { phase in
                    if case .active(let point) = phase { hoverFraction = min(max(point.x / width, 0), 1) } else { hoverFraction = nil }
                }
            }
            .frame(height: 18)
            Text("−" + Format.clock(max(duration - current, 0))).frame(minWidth: 64, alignment: .leading)
        }
        .font(.callout.monospacedDigit())
        .foregroundStyle(.white.opacity(0.9))
    }
}

private struct VolumeControl: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let engine = model.session.engine
        HStack(spacing: 4) {
            Button { engine.setMuted(!engine.isMuted) } label: {
                Image(systemName: engine.isMuted || engine.volume == 0 ? "speaker.slash.fill" : engine.volume < 50 ? "speaker.wave.1.fill" : "speaker.wave.3.fill")
                    .frame(width: 22)
            }
            .help("Mute (M)")
            Slider(value: Binding(get: { engine.isMuted ? 0 : engine.volume }, set: { engine.setVolume($0) }), in: 0...150)
                .frame(width: 100)
                .controlSize(.small)
                .tint(.white)
        }
    }
}

private struct TrackMenus: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let engine = model.session.engine
        let isLive = model.session.current?.isLive == true
        HStack(spacing: 6) {
            if engine.audioTracks.count > 1 {
                Menu {
                    ForEach(engine.audioTracks) { track in
                        Toggle(track.displayName, isOn: Binding(get: { track.isSelected }, set: { _ in engine.selectAudio(track) }))
                    }
                } label: { Image(systemName: "waveform") }
                .menuIndicator(.hidden).fixedSize().help("Audio track")
            }
            if !engine.subtitleTracks.isEmpty {
                Menu {
                    Toggle("Off", isOn: Binding(get: { !engine.subtitleTracks.contains(where: \.isSelected) }, set: { _ in engine.selectSubtitle(nil) }))
                    Divider()
                    ForEach(engine.subtitleTracks) { track in
                        Toggle(track.displayName, isOn: Binding(get: { track.isSelected }, set: { _ in engine.selectSubtitle(track) }))
                    }
                } label: { Image(systemName: "captions.bubble") }
                .menuIndicator(.hidden).fixedSize().help("Subtitles")
            }
            if !isLive {
                Menu {
                    ForEach(PlayerSpeeds.presets, id: \.self) { rate in
                        Toggle(rate == 1 ? "Normal" : "\(rate.formatted())×", isOn: Binding(get: { engine.speed == rate }, set: { _ in engine.setSpeed(rate) }))
                    }
                } label: { Image(systemName: "gauge.with.dots.needle.67percent") }
                .menuIndicator(.hidden).fixedSize().help("Playback speed ([ slower · ] faster · \\ normal)")
            }
        }
        .menuStyle(.borderlessButton)
        .tint(.white)
    }
}

// MARK: - Queue drawer

/// Side panel listing the play queue: channels, a category's movies, or a series' episodes.
private struct QueueDrawer: View {
    @Environment(AppModel.self) private var model
    let onPick: () -> Void
    @State private var query = ""

    var body: some View {
        let session = model.session
        let terms = SearchText.terms(query)
        let items = session.queue.filter { item in
            terms.isEmpty || SearchText.matches(normalizedName: SearchText.normalize(label(item) + " " + item.title), terms: terms)
        }
        VStack(alignment: .leading, spacing: 10) {
            Text(session.queueTitle ?? session.current?.subtitle ?? "Up Next").font(.headline).foregroundStyle(.white).lineLimit(1)
            TextField(session.current?.isLive == true ? "Find channel" : "Find", text: $query).textFieldStyle(.roundedBorder)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(items) { item in
                            Button { session.jump(to: item); onPick() } label: { row(item, isCurrent: item == session.current) }
                                .buttonStyle(.plain)
                                .id(item.id)
                        }
                    }
                }
                .onAppear { if let id = session.current?.id { proxy.scrollTo(id, anchor: .center) } }
            }
        }
        .padding(16)
        .frame(width: 340)
        .frame(maxHeight: .infinity)
        .glassPanel(cornerRadius: 18)
        .environment(\.colorScheme, .dark)
        .padding(.vertical, 90).padding(.trailing, 24)
    }

    /// Episodes are identified by "S1 E2 · Title"; everything else by its own title.
    private func label(_ item: PlaybackItem) -> String {
        item.kind == .episode ? (item.subtitle ?? item.title) : item.title
    }

    private func row(_ item: PlaybackItem, isCurrent: Bool) -> some View {
        HStack(spacing: 10) {
            thumbnail(item)
            VStack(alignment: .leading, spacing: 3) {
                Text(label(item)).lineLimit(2).foregroundStyle(.white)
                if let progress = model.progress(item.kind, item.id), progress.fraction > 0.01, !item.isLive {
                    ProgressView(value: progress.fraction).tint(.accentColor).frame(maxWidth: 120)
                }
            }
            Spacer(minLength: 0)
            if isCurrent { Image(systemName: "speaker.wave.2.fill").font(.caption).foregroundStyle(.white) }
        }
        .padding(8)
        .background(isCurrent ? Color.accentColor.opacity(0.45) : .clear, in: .rect(cornerRadius: 8))
        .contentShape(Rectangle())
    }

    @ViewBuilder private func thumbnail(_ item: PlaybackItem) -> some View {
        switch item.kind {
        case .live:
            RemoteImage(url: item.artwork, maxPixelSize: 100, contentMode: .fit) {
                Image(systemName: "tv").foregroundStyle(.white.opacity(0.4))
            }
            .frame(width: 44, height: 28)
        case .episode:
            RemoteImage(url: item.artwork, maxPixelSize: 180) { ArtworkPlaceholder(title: item.title, symbol: "play.rectangle") }
                .frame(width: 72, height: 40).clipShape(.rect(cornerRadius: 5))
        case .movie, .series:
            RemoteImage(url: item.artwork, maxPixelSize: 120) { ArtworkPlaceholder(title: item.title) }
                .frame(width: 32, height: 48).clipShape(.rect(cornerRadius: 4))
        }
    }
}

/// Covers the gap between choosing something and its first frame: artwork, title and a spinner,
/// cross-fading as the user zaps so the screen never flashes black.
private struct TuningCard: View {
    let item: PlaybackItem

    var body: some View {
        ZStack {
            Color.black.opacity(0.88)
            VStack(spacing: 16) {
                artwork
                VStack(spacing: 4) {
                    Text(item.title).font(.title2.weight(.semibold)).lineLimit(2).multilineTextAlignment(.center)
                    if let subtitle = item.subtitle {
                        Text(subtitle).font(.callout).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
                    }
                }
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).tint(.white)
                    Text(item.isLive ? "Tuning…" : "Loading…").font(.callout).foregroundStyle(.white.opacity(0.7))
                }
            }
            .foregroundStyle(.white)
            .padding(32)
            .id(item.id)
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
        }
        .animation(.easeOut(duration: 0.18), value: item.id)
    }

    @ViewBuilder private var artwork: some View {
        if item.isLive {
            RemoteImage(url: item.artwork, maxPixelSize: 320, contentMode: .fit) {
                Image(systemName: "tv").font(.system(size: 40)).foregroundStyle(.white.opacity(0.4))
            }
            .padding(14)
            .frame(width: 180, height: 112)
            .background(.white.opacity(0.08), in: .rect(cornerRadius: 16))
        } else {
            // Episode stills are landscape; movie posters are portrait.
            RemoteImage(url: item.artwork, maxPixelSize: 480) { ArtworkPlaceholder(title: item.title) }
                .frame(width: item.kind == .episode ? 260 : 140, height: item.kind == .episode ? 146 : 210)
                .clipShape(.rect(cornerRadius: 12))
                .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
        }
    }
}

/// Detailed technical readout (I key).
private struct StatsPanel: View {
    let stats: PlaybackStats

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
            row("Resolution", resolution)
            row("Video", [stats.videoCodec, stats.pixelFormat, stats.isHDR ? "HDR" : nil].compactMap { $0 }.joined(separator: " · "))
            row("Decoder", decoder)
            row("Frame rate", frameRate)
            row("Dropped", "\(stats.droppedFrames) output · \(stats.decoderDroppedFrames) decoder")
            row("Video bitrate", stats.videoBitrate.map(VideoQuality.bitrate))
            row("Audio", [stats.audioCodec, stats.audioChannels, stats.audioSampleRate.map { "\($0 / 1000) kHz" },
                          stats.audioBitrate.map(VideoQuality.bitrate)].compactMap { $0 }.joined(separator: " · "))
            row("Buffer", stats.cacheSeconds.map { String(format: "%.1f s ahead", $0) })
            row("Network", stats.networkSpeed.map { VideoQuality.bitrate($0 * 8) })
            row("A/V sync", stats.avSync.map { String(format: "%+.0f ms", $0 * 1000) })
        }
        .font(.system(size: 12, design: .monospaced))
        .foregroundStyle(.white)
        .padding(14)
        .background(.black.opacity(0.72), in: .rect(cornerRadius: 12))
    }

    private var resolution: String? {
        guard let size = stats.resolutionText else { return nil }
        return stats.qualityLabel.map { "\(size) (\($0))" } ?? size
    }

    private var decoder: String? {
        stats.isHardwareDecoding.map { $0 ? "Hardware (\(stats.hardwareDecoder ?? ""))" : "Software (CPU)" }
    }

    private var frameRate: String? {
        switch (stats.sourceFPS, stats.outputFPS) {
        case let (source?, output?): String(format: "%.3f source · %.2f rendered", source, output)
        case let (source?, nil): String(format: "%.3f source", source)
        default: nil
        }
    }

    @ViewBuilder private func row(_ label: String, _ value: String?) -> some View {
        GridRow {
            Text(label).foregroundStyle(.white.opacity(0.6))
            Text(value.flatMap { $0.isEmpty ? nil : $0 } ?? "—")
        }
    }
}

private struct UpNextCard: View {
    @Environment(AppModel.self) private var model
    let item: PlaybackItem
    let seconds: Int

    var body: some View {
        HStack(spacing: 14) {
            RemoteImage(url: item.artwork, maxPixelSize: 300) { ArtworkPlaceholder(title: item.title) }
                .frame(width: 120, height: 68).clipShape(.rect(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 4) {
                Text("Up next in \(seconds)s").font(.caption).foregroundStyle(.white.opacity(0.7))
                Text(item.subtitle ?? item.title).font(.headline).foregroundStyle(.white).lineLimit(2)
                HStack {
                    Button("Play Now") { model.session.playNext() }.buttonStyle(.borderedProminent)
                    Button("Cancel") { model.session.cancelAutoplay() }
                }
                .controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 380)
        .glassPanel(cornerRadius: 16)
        .environment(\.colorScheme, .dark)
    }
}

enum PlayerSpeeds {
    static let presets: [Double] = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 3]
}

private struct PlayerIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3.weight(.medium))
            .frame(minWidth: 34, minHeight: 34)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// Exposes the hosting NSWindow to SwiftUI.
struct WindowAccessor: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { window = view.window }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if nsView.window !== window { DispatchQueue.main.async { window = nsView.window } }
    }
}
