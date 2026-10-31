import Foundation
import Testing
@testable import RetuneCore

// Fixtures mirror real panel responses, including their type inconsistencies.
struct XtreamDecodingTests {
    private func decodeList<T: Decodable>(_ type: T.Type, _ json: String) throws -> [T] {
        try JSONDecoder().decode([Failable<T>].self, from: Data(json.utf8)).compactMap(\.value)
    }

    @Test func liveStreamsDecodeWithNullsAndMixedTypes() throws {
        let json = """
        [{"num":2,"name":"|UK| SKY SPORTS GOLF FHD","stream_type":"live","stream_id":244976,
          "stream_icon":"http:\\/\\/logo.example\\/golf.png","epg_channel_id":null,"category_id":"417","tv_archive":0},
         {"num":"3","name":"News","stream_id":"9","stream_icon":"","epg_channel_id":"news.uk","category_id":5,"tv_archive":"1"},
         {"name":"Broken row without id"}]
        """
        let channels = try decodeList(XtreamLiveDTO.self, json).compactMap(\.channel)
        #expect(channels.count == 2)
        #expect(channels[0].id == "244976")
        #expect(channels[0].logo?.absoluteString == "http://logo.example/golf.png")
        #expect(channels[0].epgChannelID == nil)
        #expect(channels[1].number == 3)
        #expect(channels[1].categoryID == "5")
        #expect(channels[1].logo == nil)
        #expect(channels[1].hasArchive)
    }

    @Test func vodRatingAcceptsStringIntAndFloat() throws {
        let json = """
        [{"name":"A","stream_id":1,"rating":"","rating_5based":"3.5","container_extension":"mkv","added":"1758959206","category_id":"1"},
         {"name":"B","stream_id":2,"rating":"7.2","rating_5based":0,"container_extension":"mp4","category_id":"1"},
         {"name":"C","stream_id":3,"rating":"0","rating_5based":4.1,"category_id":"1"},
         {"name":"D","stream_id":4,"rating":"0","rating_5based":"0","category_id":"1"}]
        """
        let movies = try decodeList(XtreamVODDTO.self, json).compactMap(\.movie)
        #expect(movies.map(\.rating) == [7.0, 7.2, 8.2, nil])
        #expect(movies[0].added == Date(timeIntervalSince1970: 1_758_959_206))
        #expect(movies[0].containerExtension == "mkv")
    }

    @Test func seriesTakesFirstBackdropFromArray() throws {
        let json = """
        [{"name":"Show","series_id":4598,"cover":"https://img/c.jpg","backdrop_path":["https://img/b1.jpg","https://img/b2.jpg"],
          "releaseDate":"2025-06-20","rating":"0","rating_5based":"0","category_id":"215","last_modified":"1750605329"}]
        """
        let series = try decodeList(XtreamSeriesDTO.self, json).compactMap(\.series)
        #expect(series.first?.backdrop?.absoluteString == "https://img/b1.jpg")
        #expect(series.first?.rating == nil)
        #expect(series.first?.releaseDate == "2025-06-20")
    }

    @Test func seriesInfoGroupsEpisodesBySeasonKey() throws {
        let json = """
        {"seasons":[{"name":"Season 1","season_number":1,"cover_tmdb":"https://img/s1.jpg"}],
         "info":{"name":"Show","plot":"Plot","cast":"A, B","genre":"Drama","releaseDate":"2025-06-20","episode_run_time":"45","backdrop_path":["https://img/bd.jpg"]},
         "episodes":{"2":[{"id":"11","episode_num":"1","title":"S2E1","container_extension":"mkv","info":{"duration_secs":2700}}],
                     "1":[{"id":"2","episode_num":2,"title":"S1E2","container_extension":"mkv","info":[]},
                          {"id":"1","episode_num":1,"title":"S1E1","container_extension":"mp4","info":{"movie_image":"https://img/e1.jpg","plot":"First"}}]}}
        """
        let detail = try JSONDecoder().decode(XtreamSeriesInfoResponse.self, from: Data(json.utf8)).detail
        #expect(detail.seasons.map(\.number) == [1, 2])
        #expect(detail.seasons[0].name == "Season 1")
        #expect(detail.seasons[0].cover?.absoluteString == "https://img/s1.jpg")
        #expect(detail.seasons[0].episodes.map(\.id) == ["1", "2"])
        #expect(detail.seasons[0].episodes[0].image?.absoluteString == "https://img/e1.jpg")
        #expect(detail.seasons[1].name == "Season 2")
        #expect(detail.seasons[1].episodes[0].season == 2)
        #expect(detail.info.durationSeconds == 45 * 60)
        #expect(detail.info.year == "2025")
        #expect(detail.info.backdrop?.absoluteString == "https://img/bd.jpg")
    }

    @Test func seriesInfoAcceptsEpisodesAsNestedArrays() throws {
        let json = """
        {"seasons":[],"info":[],"episodes":[[{"id":"5","episode_num":1,"season":3,"title":"Only"}]]}
        """
        let detail = try JSONDecoder().decode(XtreamSeriesInfoResponse.self, from: Data(json.utf8)).detail
        #expect(detail.seasons.map(\.number) == [3])
        #expect(detail.info.plot == nil)
    }

    @Test func vodInfoToleratesEmptyInfoArray() throws {
        let empty = try JSONDecoder().decode(XtreamVODInfoResponse.self, from: Data(#"{"info":[],"movie_data":{}}"#.utf8))
        #expect(empty.info == MediaInfo())

        let full = try JSONDecoder().decode(XtreamVODInfoResponse.self, from: Data("""
        {"info":{"movie_image":"https://img/p.jpg","duration_secs":6163,"plot":"Story","rating":"6.5"},"movie_data":{"stream_id":1}}
        """.utf8))
        #expect(full.info.durationSeconds == 6163)
        #expect(full.info.rating == 6.5)
        #expect(full.info.poster?.absoluteString == "https://img/p.jpg")
    }

    @Test func epgDecodesBase64AndSorts() throws {
        let later = Data("Evening News".utf8).base64EncodedString()
        let earlier = Data("Morning Show".utf8).base64EncodedString()
        let json = """
        {"epg_listings":[
          {"title":"\(later)","description":"","start_timestamp":"2000","stop_timestamp":"3000"},
          {"title":"\(earlier)","description":"\(Data("Desc".utf8).base64EncodedString())","start_timestamp":1000,"stop_timestamp":2000}]}
        """
        let entries = try JSONDecoder().decode(XtreamEPGResponse.self, from: Data(json.utf8)).entries
        #expect(entries.map(\.title) == ["Morning Show", "Evening News"])
        #expect(entries[0].summary == "Desc")
        #expect(entries[0].isLive(at: Date(timeIntervalSince1970: 1500)))
        #expect(entries[0].progress(at: Date(timeIntervalSince1970: 1500)) == 0.5)
    }

    @Test func authParsesAccountAndRejectsBadLogin() throws {
        let ok = """
        {"user_info":{"username":"u","password":"p","auth":1,"status":"Active","exp_date":"1810382592","is_trial":"0",
          "active_cons":"0","max_connections":"1","allowed_output_formats":["m3u8","ts"]},
         "server_info":{"url":"example.com","port":"8080","timezone":"Asia/Karachi"}}
        """
        let account = try #require(try JSONDecoder().decode(XtreamAuthResponse.self, from: Data(ok.utf8)).account)
        #expect(account.isActive)
        #expect(account.maxConnections == 1)
        #expect(account.allowedFormats == ["m3u8", "ts"])
        #expect(account.expiresAt == Date(timeIntervalSince1970: 1_810_382_592))
        #expect(!account.isTrial)

        let rejected = try JSONDecoder().decode(XtreamAuthResponse.self, from: Data(#"{"user_info":{"auth":0}}"#.utf8))
        #expect(rejected.account == nil)
    }
}
