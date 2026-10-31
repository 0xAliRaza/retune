import Foundation

// Wire formats for the Xtream Codes `player_api.php` endpoints. Every DTO decodes
// leniently and maps into the clean domain models in Models.swift.

struct XtreamCategoryDTO: Decodable {
    let category: MediaCategory?

    private enum CodingKeys: String, CodingKey { case category_id, category_name }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = c.lenientText(.category_id) else { category = nil; return }
        category = MediaCategory(id: id, name: c.lenientText(.category_name) ?? "Untitled")
    }
}

struct XtreamLiveDTO: Decodable {
    let channel: Channel?

    private enum CodingKeys: String, CodingKey {
        case num, name, stream_id, stream_icon, category_id, epg_channel_id, tv_archive
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = c.lenientText(.stream_id) else { channel = nil; return }
        channel = Channel(
            id: id,
            number: c.lenientInt(.num),
            name: c.lenientText(.name) ?? "Channel \(id)",
            logo: c.lenientURL(.stream_icon),
            categoryID: c.lenientText(.category_id),
            epgChannelID: c.lenientText(.epg_channel_id),
            directURL: nil,
            hasArchive: c.lenientBool(.tv_archive)
        )
    }
}

struct XtreamVODDTO: Decodable {
    let movie: Movie?

    private enum CodingKeys: String, CodingKey {
        case name, stream_id, stream_icon, category_id, rating, rating_5based, added, container_extension
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = c.lenientText(.stream_id) else { movie = nil; return }
        movie = Movie(
            id: id,
            name: c.lenientText(.name) ?? "Untitled",
            poster: c.lenientURL(.stream_icon),
            categoryID: c.lenientText(.category_id),
            rating: XtreamRating.tenPoint(rating: c.lenientDouble(.rating), fiveBased: c.lenientDouble(.rating_5based)),
            added: c.lenientDate(.added),
            containerExtension: c.lenientText(.container_extension),
            directURL: nil
        )
    }
}

struct XtreamSeriesDTO: Decodable {
    let series: Series?

    private enum CodingKeys: String, CodingKey {
        case series_id, name, cover, backdrop_path, category_id, plot, genre, releaseDate, release_date
        case rating, rating_5based, last_modified
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = c.lenientText(.series_id) else { series = nil; return }
        series = Series(
            id: id,
            name: c.lenientText(.name) ?? "Untitled",
            cover: c.lenientURL(.cover),
            backdrop: c.lenientFirstURL(.backdrop_path),
            categoryID: c.lenientText(.category_id),
            plot: c.lenientText(.plot),
            genre: c.lenientText(.genre),
            releaseDate: c.lenientText(.releaseDate) ?? c.lenientText(.release_date),
            rating: XtreamRating.tenPoint(rating: c.lenientDouble(.rating), fiveBased: c.lenientDouble(.rating_5based)),
            lastModified: c.lenientDate(.last_modified)
        )
    }
}

enum XtreamRating {
    /// Normalises to a 0–10 scale, treating 0 as "no rating".
    static func tenPoint(rating: Double?, fiveBased: Double?) -> Double? {
        if let rating, rating > 0, rating <= 10 { return rating }
        if let fiveBased, fiveBased > 0, fiveBased <= 5 { return fiveBased * 2 }
        return nil
    }
}

/// The `info` object shared by `get_vod_info` and `get_series_info`.
struct XtreamInfoDTO: Decodable {
    let info: MediaInfo

    private enum CodingKeys: String, CodingKey {
        case plot, description, cast, actors, director, genre, releasedate, releaseDate, release_date
        case duration_secs, episode_run_time, rating, rating_5based
        case movie_image, cover_big, cover, backdrop_path, youtube_trailer
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let runtimeMinutes = c.lenientInt(.episode_run_time)
        info = MediaInfo(
            plot: c.lenientText(.plot) ?? c.lenientText(.description),
            cast: c.lenientText(.cast) ?? c.lenientText(.actors),
            director: c.lenientText(.director),
            genre: c.lenientText(.genre),
            releaseDate: c.lenientText(.releasedate) ?? c.lenientText(.releaseDate) ?? c.lenientText(.release_date),
            durationSeconds: c.lenientInt(.duration_secs) ?? runtimeMinutes.flatMap { minutes in
                let (seconds, overflow) = minutes.multipliedReportingOverflow(by: 60)
                return overflow ? nil : seconds
            },
            rating: XtreamRating.tenPoint(rating: c.lenientDouble(.rating), fiveBased: c.lenientDouble(.rating_5based)),
            poster: c.lenientURL(.movie_image) ?? c.lenientURL(.cover_big) ?? c.lenientURL(.cover),
            backdrop: c.lenientFirstURL(.backdrop_path),
            youtubeTrailer: c.lenientText(.youtube_trailer)
        )
    }
}

struct XtreamVODInfoResponse: Decodable {
    let info: MediaInfo

    private enum CodingKeys: String, CodingKey { case info }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Some panels return `"info": []` when metadata is missing.
        info = (try? c.decode(XtreamInfoDTO.self, forKey: .info))?.info ?? MediaInfo()
    }
}

struct XtreamSeriesInfoResponse: Decodable {
    let detail: SeriesDetail

    private enum CodingKeys: String, CodingKey { case info, seasons, episodes }

    private struct SeasonDTO: Decodable {
        let number: Int?
        let name: String?
        let cover: URL?

        private enum CodingKeys: String, CodingKey { case season_number, name, cover_big, cover, cover_tmdb }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            number = c.lenientInt(.season_number)
            name = c.lenientText(.name)
            cover = c.lenientURL(.cover_tmdb) ?? c.lenientURL(.cover_big) ?? c.lenientURL(.cover)
        }
    }

    private struct EpisodeDTO: Decodable {
        let episode: Episode?

        private enum CodingKeys: String, CodingKey { case id, episode_num, season, title, container_extension, info }
        private enum InfoKeys: String, CodingKey { case plot, movie_image, duration_secs }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            guard let id = c.lenientText(.id) else { episode = nil; return }
            let info = try? c.nestedContainer(keyedBy: InfoKeys.self, forKey: .info)
            let number = c.lenientInt(.episode_num) ?? 0
            episode = Episode(
                id: id,
                season: c.lenientInt(.season) ?? 0,
                number: number,
                title: c.lenientText(.title) ?? "Episode \(number)",
                containerExtension: c.lenientText(.container_extension),
                plot: info?.lenientText(.plot),
                image: info?.lenientURL(.movie_image),
                durationSeconds: info?.lenientInt(.duration_secs)
            )
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let info = (try? c.decode(XtreamInfoDTO.self, forKey: .info))?.info ?? MediaInfo()
        let seasonMeta = ((try? c.decode([Failable<SeasonDTO>].self, forKey: .seasons)) ?? []).compactMap(\.value)

        // `episodes` is usually `{"1": [...], "2": [...]}` but some panels send `[[...], [...]]`.
        var grouped: [Int: [Episode]] = [:]
        if let byKey = try? c.nestedContainer(keyedBy: AnyKey.self, forKey: .episodes) {
            for key in byKey.allKeys {
                let list = ((try? byKey.decode([Failable<EpisodeDTO>].self, forKey: key)) ?? []).compactMap(\.value?.episode)
                let seasonNumber = Int(key.stringValue) ?? list.first?.season ?? 0
                grouped[seasonNumber, default: []] += list
            }
        } else if let nested = try? c.decode([[Failable<EpisodeDTO>]].self, forKey: .episodes) {
            for (index, list) in nested.enumerated() {
                let episodes = list.compactMap(\.value?.episode)
                grouped[episodes.first?.season ?? index + 1, default: []] += episodes
            }
        }

        let seasons = grouped.keys.sorted().map { number -> Season in
            let meta = seasonMeta.first { $0.number == number }
            let episodes = grouped[number, default: []]
                .map { $0.season == number ? $0 : $0.withSeason(number) }
                .sorted { $0.number < $1.number }
            return Season(number: number, name: meta?.name ?? "Season \(number)", cover: meta?.cover, episodes: episodes)
        }
        detail = SeriesDetail(info: info, seasons: seasons)
    }
}

private extension Episode {
    func withSeason(_ season: Int) -> Episode {
        Episode(id: id, season: season, number: number, title: title, containerExtension: containerExtension,
                plot: plot, image: image, durationSeconds: durationSeconds, directURL: directURL)
    }
}

struct XtreamEPGResponse: Decodable {
    let entries: [EPGEntry]

    private enum CodingKeys: String, CodingKey { case epg_listings }

    private struct ListingDTO: Decodable {
        let entry: EPGEntry?

        private enum CodingKeys: String, CodingKey { case title, description, start_timestamp, stop_timestamp }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            guard let start = c.lenientDate(.start_timestamp), let end = c.lenientDate(.stop_timestamp),
                  let title = c.lenientText(.title).map(XtreamText.decodeBase64) else { entry = nil; return }
            entry = EPGEntry(title: title, summary: c.lenientText(.description).map(XtreamText.decodeBase64),
                             start: start, end: end)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        entries = ((try? c.decode([Failable<ListingDTO>].self, forKey: .epg_listings)) ?? [])
            .compactMap(\.value?.entry)
            .sorted { $0.start < $1.start }
    }
}

enum XtreamText {
    /// EPG titles/descriptions are base64 encoded; fall back to the raw text if they are not.
    static func decodeBase64(_ text: String) -> String {
        guard let data = Data(base64Encoded: text), let decoded = String(data: data, encoding: .utf8) else { return text }
        return decoded.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct XtreamAuthResponse: Decodable {
    let account: AccountInfo?

    private enum CodingKeys: String, CodingKey { case user_info, server_info }
    private enum UserKeys: String, CodingKey {
        case auth, status, message, exp_date, is_trial, active_cons, max_connections, allowed_output_formats
    }
    private enum ServerKeys: String, CodingKey { case timezone }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let user = try? c.nestedContainer(keyedBy: UserKeys.self, forKey: .user_info),
              user.lenientInt(.auth) == 1 else { account = nil; return }
        let server = try? c.nestedContainer(keyedBy: ServerKeys.self, forKey: .server_info)
        account = AccountInfo(
            status: user.lenientText(.status) ?? "Unknown",
            message: user.lenientText(.message),
            expiresAt: user.lenientDate(.exp_date),
            isTrial: user.lenientBool(.is_trial),
            activeConnections: user.lenientInt(.active_cons),
            maxConnections: user.lenientInt(.max_connections),
            allowedFormats: (try? user.decodeIfPresent([String].self, forKey: .allowed_output_formats)) ?? [],
            serverTimezone: server?.lenientText(.timezone)
        )
    }
}
