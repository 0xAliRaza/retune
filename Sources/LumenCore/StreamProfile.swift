import Foundation

/// mpv settings that differ between live channels and on-demand files.
public enum StreamProfile: Sendable {
    case live, onDemand

    public init(isLive: Bool) {
        self = isLive ? .live : .onDemand
    }

    /// Applied before every load, because mpv keeps them across files.
    ///
    /// Live streams must not reconnect inside FFmpeg. A reconnect there splices the new connection into
    /// the running demuxer, so whatever the server sends next plays as a seamless continuation: a server
    /// that resumes behind the live edge replays minutes of video with no sign that anything happened,
    /// and the timestamps jump. Ending the file instead lets `PlaybackSession` reload it from scratch.
    public var mpvProperties: [(name: String, value: String)] {
        switch self {
        case .live:
            [("stream-lavf-o", ""),
             ("demuxer-max-back-bytes", "0"),
             ("demuxer-seekable-cache", "no")]
        case .onDemand:
            // No `reconnect_streamed`: a server without range support would restart the file from byte 0
            // mid-playback. Seekable files resume at the exact offset.
            [("stream-lavf-o", "reconnect=1,reconnect_delay_max=5"),
             ("demuxer-max-back-bytes", "128MiB"),
             ("demuxer-seekable-cache", "auto")]
        }
    }
}

/// Decides which URLs may reach the player. Playlists come from strangers, and mpv's special protocols
/// (`av://`, `edl://`, `file://`, …) can read and even overwrite local files, so only plain network
/// streaming protocols are accepted.
public enum StreamURLPolicy {
    public static let allowedSchemes: Set<String> = ["http", "https", "rtmp", "rtmps", "rtsp", "rtsps", "rtp", "udp"]

    public static func isAllowed(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), let host = url.host(), !host.isEmpty else { return false }
        return allowedSchemes.contains(scheme)
    }

    public static func isHTTP(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased())
    }
}
