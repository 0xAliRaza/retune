import CMPV
import Foundation
import RetuneCore
import Observation

struct MediaTrack: Identifiable, Hashable {
    enum Kind: String { case audio, sub, video }

    let id: Int
    let kind: Kind
    let title: String?
    let language: String?
    let codec: String?
    let channels: Int?
    let isSelected: Bool
    let isExternal: Bool

    var displayName: String {
        var parts: [String] = []
        if let language, let name = Locale.current.localizedString(forLanguageCode: language) {
            parts.append(name)
        } else if let language {
            parts.append(language.uppercased())
        }
        if let title, !parts.contains(title) { parts.append(title) }
        if parts.isEmpty { parts.append("Track \(id)") }
        var detail: [String] = []
        if let codec { detail.append(codec.uppercased()) }
        if let channels, channels > 0 { detail.append(channels == 6 ? "5.1" : channels == 8 ? "7.1" : "\(channels)ch") }
        return detail.isEmpty ? parts.joined(separator: " · ") : "\(parts.joined(separator: " · ")) (\(detail.joined(separator: ", ")))"
    }
}

/// Point-in-time technical details for the stats overlay.
struct PlaybackStats {
    var width = 0
    var height = 0
    var videoCodec: String?
    var pixelFormat: String?
    var isHDR = false
    var hardwareDecoder: String?
    var sourceFPS: Double?
    var outputFPS: Double?
    var droppedFrames = 0
    var decoderDroppedFrames = 0
    var videoBitrate: Double?
    var audioCodec: String?
    var audioChannels: String?
    var audioSampleRate: Int?
    var audioBitrate: Double?
    var cacheSeconds: Double?
    var networkSpeed: Double?
    var avSync: Double?

    var resolutionText: String? { width > 0 && height > 0 ? "\(width)×\(height)" : nil }
    var qualityLabel: String? { VideoQuality.label(width: width, height: height) }
    /// nil until mpv reports which decoder is active.
    var isHardwareDecoding: Bool? { hardwareDecoder.map { $0 != "no" } }
}

/// Thin, observable wrapper around a libmpv handle. All state mutation happens on the main thread;
/// mpv's wakeup callback just schedules an event drain there.
@MainActor
@Observable
final class MPVPlayer {
    private(set) var isPaused = false { didSet { updateDisplayActivity() } }
    private(set) var position: Double = 0
    private(set) var duration: Double = 0
    private(set) var bufferedAhead: Double = 0
    private(set) var isBuffering = false
    private(set) var isLoaded = false { didSet { updateDisplayActivity() } }
    /// True once a frame of the current file is on screen (mpv's playback-restart); drives the tuning card.
    private(set) var hasVideoFrame = false
    private(set) var reachedEnd = false
    private(set) var errorMessage: String?
    private(set) var volume: Double = 100
    private(set) var isMuted = false
    private(set) var speed: Double = 1
    private(set) var tracks: [MediaTrack] = []
    private(set) var videoSize: CGSize?
    private(set) var subtitleStyle = SubtitleStyle.load()
    /// Per-file subtitle timing offset in seconds; resets whenever a new file loads.
    private(set) var subtitleDelay: Double = 0
    @ObservationIgnored private var lastSubtitleTrackID: Int?
    /// Held while video plays. mpv's own screensaver handling lives in its window code, which libmpv's
    /// render API doesn't use, so without this the display sleeps in the middle of a film.
    @ObservationIgnored private var displayActivity: NSObjectProtocol?

    var audioTracks: [MediaTrack] { tracks.filter { $0.kind == .audio } }
    var subtitleTracks: [MediaTrack] { tracks.filter { $0.kind == .sub } }
    var isSeekable: Bool { duration > 0 }
    /// The stream itself carries video but no audio (a provider-side problem, common on broken IPTV feeds).
    var hasNoAudio: Bool { isLoaded && audioTracks.isEmpty && tracks.contains { $0.kind == .video } }

    @ObservationIgnored var onEndOfFile: (() -> Void)?
    /// Fires when playback leaves the end of a file again (replay, seek back).
    @ObservationIgnored var onLeftEnd: (() -> Void)?
    /// A load or stream failed. When set, the owner decides whether to retry or call `showError`.
    @ObservationIgnored var onError: ((String) -> Void)?
    /// The first frame of a file (or after a seek) is on screen.
    @ObservationIgnored var onPlaybackStarted: (() -> Void)?
    @ObservationIgnored private(set) var handle: OpaquePointer?

    private static let volumeDefaultsKey = "player.volume"

    private struct LoadRequest {
        let url: URL
        let profile: StreamProfile
        let startAt: Double?
    }

    /// mpv gives up on video for the whole file if it opens before the render context exists, leaving
    /// sound over a black picture. The context only appears once the layer is on screen, which a fast
    /// stream can beat, so a load waits here for it.
    @ObservationIgnored private var loadGate = PendingUntilReady<LoadRequest>()

    init() {
        handle = mpv_create()
        guard let handle else { return }

        let storedVolume = VolumeLevel.clamped(UserDefaults.standard.object(forKey: Self.volumeDefaultsKey) as? Double ?? VolumeLevel.maximum)
        let options: [(String, String)] = [
            ("vo", "libmpv"),
            ("hwdec", "auto-safe"),
            // Live TV is often interlaced, and showing that as-is looks soft with striped motion.
            // `auto` only acts on frames flagged as interlaced, so everything else is left alone.
            ("deinterlace", "auto"),
            ("keep-open", "yes"),
            ("idle", "yes"),
            ("input-default-bindings", "no"),
            ("input-vo-keyboard", "no"),
            ("osd-level", "0"),
            // Stream URLs are untrusted: no script runner, no yt-dlp lookups, no playlist escalation.
            ("load-scripts", "no"),
            ("ytdl", "no"),
            ("load-unsafe-playlists", "no"),
            ("volume", String(storedVolume)),
            ("volume-max", String(VolumeLevel.maximum)),
            // Network resilience for IPTV: generous cache; `StreamProfile` adds the per-stream settings.
            // Read ahead aggressively so fast connections fill the buffer and slow patches don't stall.
            ("cache", "yes"),
            ("demuxer-max-bytes", "512MiB"),
            ("demuxer-readahead-secs", "120"),
            ("network-timeout", "20"),
            // Start streams sooner: FFmpeg otherwise inspects up to ~5 s of a live stream before playing.
            // 2 s found the audio (AAC and E-AC-3) on every provider TS channel probed; 3 s leaves margin.
            ("demuxer-lavf-analyzeduration", "3"),
            ("user-agent", "Retune/1.0 (Macintosh; libmpv)"),
            // Subtitles and languages: follow the system language first.
            ("sub-auto", "fuzzy"),
            ("slang", Self.preferredLanguages),
            ("alang", Self.preferredLanguages),
            ("sub-font-size", "40"),
            ("sub-border-size", "2.5"),
        ]
        for (name, value) in options + subtitleStyle.mpvOptions { mpv_set_option_string(handle, name, value) }
        volume = storedVolume
        #if DEBUG
        // DevProbe runs unattended, so it must never reach the speakers.
        if CommandLine.arguments.contains("--probe") { mpv_set_option_string(handle, "ao", "null") }
        #endif

        guard mpv_initialize(handle) >= 0 else {
            errorMessage = "The video engine failed to start."
            return
        }

        observe("pause", MPV_FORMAT_FLAG)
        observe("time-pos", MPV_FORMAT_DOUBLE)
        observe("duration", MPV_FORMAT_DOUBLE)
        observe("demuxer-cache-duration", MPV_FORMAT_DOUBLE)
        observe("paused-for-cache", MPV_FORMAT_FLAG)
        observe("seeking", MPV_FORMAT_FLAG)
        observe("eof-reached", MPV_FORMAT_FLAG)
        observe("volume", MPV_FORMAT_DOUBLE)
        observe("mute", MPV_FORMAT_FLAG)
        observe("speed", MPV_FORMAT_DOUBLE)
        observe("track-list", MPV_FORMAT_NONE)
        observe("sid", MPV_FORMAT_NONE)
        observe("aid", MPV_FORMAT_NONE)
        observe("video-params/w", MPV_FORMAT_INT64)
        observe("video-params/h", MPV_FORMAT_INT64)

        mpv_set_wakeup_callback(handle, { context in
            guard let context else { return }
            let player = Unmanaged<MPVPlayer>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { MainActor.assumeIsolated { player.drainEvents() } }
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    private static var preferredLanguages: String {
        let codes = Locale.preferredLanguages.compactMap { Locale(identifier: $0).language.languageCode?.identifier }
        return (codes + ["en", "eng"]).joined(separator: ",")
    }

    // MARK: Commands

    func load(_ url: URL, profile: StreamProfile, startAt: Double? = nil) {
        // Catalogs cached by older builds skipped today's parser checks, so this is the real gate.
        guard StreamURLPolicy.isAllowed(url) else {
            stop()
            showError("This stream uses an address type Retune doesn't play.")
            return
        }
        hasVideoFrame = false
        errorMessage = nil
        reachedEnd = false
        isLoaded = false
        isBuffering = true
        position = 0
        duration = 0
        bufferedAhead = 0
        tracks = []
        videoSize = nil
        setSubtitleDelay(0)
        if let request = loadGate.submit(LoadRequest(url: url, profile: profile, startAt: startAt)) { start(request) }
    }

    private func start(_ request: LoadRequest) {
        for (name, value) in request.profile.mpvProperties { setProperty(name, value) }
        if let speed = request.profile.forcedSpeed { setSpeed(speed) }
        setProperty("start", request.startAt.map { String(format: "%.0f", $0) } ?? "none")
        command("loadfile", request.url.absoluteString, "replace")
        setProperty("pause", "no")
    }

    /// Called by the video layer as its render context comes and goes.
    func renderContextChanged(isReady: Bool) {
        if let request = loadGate.setReady(isReady) { start(request) }
    }

    func stop() {
        loadGate.cancel()
        command("stop")
        hasVideoFrame = false
        isLoaded = false
        isBuffering = false
        position = 0
        duration = 0
        tracks = []
    }

    /// Stops the current stream right away (freeing the provider connection) and shows the tuning state
    /// while the next load is pending.
    func prepareForTuning() {
        stop()
        errorMessage = nil
        isBuffering = true
    }

    func showError(_ message: String) {
        errorMessage = message
        isBuffering = false
    }

    func togglePause() { setPaused(!isPaused) }

    func setPaused(_ paused: Bool) {
        if !paused, reachedEnd { seek(to: 0) }
        setProperty("pause", paused ? "yes" : "no")
    }

    func seek(by seconds: Double) { command("seek", String(seconds), "relative+exact") }

    func seek(to seconds: Double) {
        position = seconds
        command("seek", String(max(seconds, 0)), "absolute+keyframes")
    }

    func setVolume(_ value: Double) {
        let clamped = VolumeLevel.clamped(value)
        volume = clamped
        setProperty("volume", String(clamped))
        if isMuted, clamped > 0 { setMuted(false) }
        UserDefaults.standard.set(clamped, forKey: Self.volumeDefaultsKey)
    }

    func setMuted(_ muted: Bool) { setProperty("mute", muted ? "yes" : "no") }

    func setSpeed(_ value: Double) { setProperty("speed", String(value)) }

    func selectAudio(_ track: MediaTrack) { setProperty("aid", String(track.id)) }

    func selectSubtitle(_ track: MediaTrack?) { setProperty("sid", track.map { String($0.id) } ?? "no") }


    // MARK: Subtitles

    var subtitlesOn: Bool { subtitleTracks.contains(where: \.isSelected) }

    /// Turns subtitles off, or back on with the last used (else first) track. Returns the new state, or nil if there are none.
    @discardableResult
    func toggleSubtitles() -> Bool? {
        if let selected = subtitleTracks.first(where: \.isSelected) {
            lastSubtitleTrackID = selected.id
            selectSubtitle(nil)
            return false
        }
        guard let track = subtitleTracks.first(where: { $0.id == lastSubtitleTrackID }) ?? subtitleTracks.first else { return nil }
        selectSubtitle(track)
        return true
    }

    func setSubtitleDelay(_ seconds: Double) {
        subtitleDelay = (seconds * 10).rounded() / 10
        setProperty("sub-delay", String(subtitleDelay))
    }

    func updateSubtitleStyle(_ change: (inout SubtitleStyle) -> Void) {
        change(&subtitleStyle)
        subtitleStyle.clamp()
        subtitleStyle.save()
        for (name, value) in subtitleStyle.mpvOptions { setProperty(name, value) }
    }

    func resetSubtitles() {
        updateSubtitleStyle { $0 = SubtitleStyle() }
        setSubtitleDelay(0)
    }

    /// Frees mpv; must run after the render context has been released.
    func shutdown() {
        guard let handle else { return }
        mpv_set_wakeup_callback(handle, nil, nil)
        self.handle = nil
        mpv_terminate_destroy(handle)
    }

    /// Reads current stats synchronously; cheap enough to poll once a second while the overlay is open.
    #if DEBUG
    var audioOutput: String? { string("current-ao") }
    #endif

    func readStats() -> PlaybackStats {
        var stats = PlaybackStats()
        stats.width = int("video-params/w") ?? 0
        stats.height = int("video-params/h") ?? 0
        stats.videoCodec = string("video-codec")
        stats.pixelFormat = string("video-params/pixelformat")
        stats.isHDR = ["pq", "hlg"].contains(string("video-params/gamma") ?? "")
        stats.hardwareDecoder = string("hwdec-current")
        stats.sourceFPS = double("container-fps")
        stats.outputFPS = double("estimated-vf-fps")
        stats.droppedFrames = int("frame-drop-count") ?? 0
        stats.decoderDroppedFrames = int("decoder-frame-drop-count") ?? 0
        stats.videoBitrate = double("video-bitrate")
        stats.audioCodec = string("audio-codec-name")
        stats.audioChannels = string("audio-params/hr-channels")
        stats.audioSampleRate = int("audio-params/samplerate")
        stats.audioBitrate = double("audio-bitrate")
        stats.cacheSeconds = double("demuxer-cache-duration")
        stats.networkSpeed = double("cache-speed")
        stats.avSync = double("avsync")
        return stats
    }

    private func updateDisplayActivity() {
        let shouldHold = isLoaded && !isPaused
        if shouldHold, displayActivity == nil {
            displayActivity = ProcessInfo.processInfo.beginActivity(options: [.idleDisplaySleepDisabled, .userInitiated],
                                                                    reason: "Playing video")
        } else if !shouldHold, let activity = displayActivity {
            ProcessInfo.processInfo.endActivity(activity)
            displayActivity = nil
        }
    }

    // MARK: libmpv plumbing

    private func string(_ name: String) -> String? {
        guard let handle, let raw = mpv_get_property_string(handle, name) else { return nil }
        defer { mpv_free(raw) }
        let value = String(cString: raw)
        return value.isEmpty ? nil : value
    }

    private func double(_ name: String) -> Double? {
        guard let handle else { return nil }
        var value = 0.0
        return mpv_get_property(handle, name, MPV_FORMAT_DOUBLE, &value) >= 0 ? value : nil
    }

    private func int(_ name: String) -> Int? {
        guard let handle else { return nil }
        var value: Int64 = 0
        return mpv_get_property(handle, name, MPV_FORMAT_INT64, &value) >= 0 ? Int(value) : nil
    }

    private func observe(_ name: String, _ format: mpv_format) {
        mpv_observe_property(handle, 0, name, format)
    }

    private func setProperty(_ name: String, _ value: String) {
        guard let handle else { return }
        mpv_set_property_string(handle, name, value)
    }

    private func command(_ args: String...) {
        guard let handle else { return }
        var cArgs: [UnsafePointer<CChar>?] = args.map { UnsafePointer(strdup($0)) }
        cArgs.append(nil)
        defer { cArgs.forEach { free(UnsafeMutablePointer(mutating: $0)) } }
        cArgs.withUnsafeMutableBufferPointer { buffer in
            _ = mpv_command_async(handle, 0, buffer.baseAddress)
        }
    }

    private func drainEvents() {
        while let handle, let event = mpv_wait_event(handle, 0)?.pointee {
            switch event.event_id {
            case MPV_EVENT_NONE, MPV_EVENT_SHUTDOWN:
                return
            case MPV_EVENT_PROPERTY_CHANGE:
                if let data = event.data { handlePropertyChange(data.assumingMemoryBound(to: mpv_event_property.self).pointee) }
            case MPV_EVENT_START_FILE:
                isBuffering = true
            case MPV_EVENT_PLAYBACK_RESTART:
                hasVideoFrame = true
                isBuffering = false
                onPlaybackStarted?()
            case MPV_EVENT_FILE_LOADED:
                isLoaded = true
                isBuffering = false
                refreshTracks()
            case MPV_EVENT_END_FILE:
                if let data = event.data { handleEndFile(data.assumingMemoryBound(to: mpv_event_end_file.self).pointee) }
            default:
                break
            }
        }
    }

    private func handleEndFile(_ end: mpv_event_end_file) {
        isBuffering = false
        guard end.reason == MPV_END_FILE_REASON_ERROR else { return }
        isLoaded = false
        let reason = String(cString: mpv_error_string(end.error))
        let message = "This stream couldn't be played (\(reason)). The channel may be offline or your connection limit reached."
        if let onError { onError(message) } else { showError(message) }
    }

    private func handlePropertyChange(_ property: mpv_event_property) {
        let name = String(cString: property.name)
        let data = property.data
        func flag() -> Bool { data?.assumingMemoryBound(to: Int32.self).pointee ?? 0 != 0 }
        func double() -> Double { data?.assumingMemoryBound(to: Double.self).pointee ?? 0 }
        func int() -> Int { Int(data?.assumingMemoryBound(to: Int64.self).pointee ?? 0) }

        switch name {
        case "pause": isPaused = flag()
        case "time-pos": position = double()
        case "duration": duration = double()
        case "demuxer-cache-duration": bufferedAhead = double()
        case "paused-for-cache", "seeking": isBuffering = flag()
        case "volume": volume = double()
        case "mute": isMuted = flag()
        case "speed": speed = double()
        case "track-list", "sid", "aid": refreshTracks()
        case "video-params/w", "video-params/h": updateVideoSize(name: name, value: int())
        case "eof-reached":
            let ended = flag()
            if ended, !reachedEnd {
                reachedEnd = true
                onEndOfFile?()
            } else if !ended, reachedEnd {
                reachedEnd = false
                onLeftEnd?()
            }
        default: break
        }
    }

    private func updateVideoSize(name: String, value: Int) {
        var size = videoSize ?? .zero
        if name.hasSuffix("w") { size.width = CGFloat(value) } else { size.height = CGFloat(value) }
        videoSize = size.width > 0 && size.height > 0 ? size : nil
    }

    private func refreshTracks() {
        guard let handle else { return }
        var node = mpv_node()
        guard mpv_get_property(handle, "track-list", MPV_FORMAT_NODE, &node) >= 0 else { return }
        defer { mpv_free_node_contents(&node) }
        guard let list = MPVNode.value(of: node) as? [[String: Any]] else { tracks = []; return }
        tracks = list.compactMap { entry in
            guard let id = entry["id"] as? Int64, let type = entry["type"] as? String, let kind = MediaTrack.Kind(rawValue: type) else { return nil }
            return MediaTrack(
                id: Int(id), kind: kind,
                title: entry["title"] as? String,
                language: entry["lang"] as? String,
                codec: entry["codec"] as? String,
                channels: (entry["demux-channel-count"] as? Int64).map(Int.init),
                isSelected: entry["selected"] as? Bool ?? false,
                isExternal: entry["external"] as? Bool ?? false
            )
        }
    }
}

/// Converts an `mpv_node` tree into Foundation values.
enum MPVNode {
    static func value(of node: mpv_node) -> Any? {
        switch node.format {
        case MPV_FORMAT_STRING: return node.u.string.map { String(cString: $0) }
        case MPV_FORMAT_FLAG: return node.u.flag != 0
        case MPV_FORMAT_INT64: return node.u.int64
        case MPV_FORMAT_DOUBLE: return node.u.double_
        case MPV_FORMAT_NODE_ARRAY:
            guard let list = node.u.list?.pointee else { return [Any]() }
            return (0..<Int(list.num)).compactMap { value(of: list.values[$0]) }
        case MPV_FORMAT_NODE_MAP:
            guard let list = node.u.list?.pointee else { return [String: Any]() }
            var map: [String: Any] = [:]
            for index in 0..<Int(list.num) {
                guard let key = list.keys?[index] else { continue }
                map[String(cString: key)] = value(of: list.values[index])
            }
            return map
        default:
            return nil
        }
    }
}
