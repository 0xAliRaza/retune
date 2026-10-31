# Changelog

## Unreleased

### Fixed

- Interlaced channels are now deinterlaced, which removes striped motion and plays them at their full field rate.
- The first stream after launch could play sound over a black picture if it opened before the video layer was ready.

## 1.0.1 - 2026-10-31

### Fixed

- The `S` shortcut saves a screenshot with hardware-decoded video. It used to fail silently while reporting success, and it now shows an error if the file can't be written.
- On-demand video that loses its connection now reconnects and resumes. It used to look like the end of the file, which saved it as stopped and could start the next episode.
- Live channels always play at normal speed, even after watching something faster.
- Deleting a playlist that isn't open no longer interrupts a refresh of the one that is.
- Saving changes to the open playlist now replaces a refresh that was still using the old details.
- A playlist whose saved password is missing now says so, instead of showing a cached list that can't play.
- Switching or deleting a playlist now stops playback, so its final position can't land in the wrong place.
- The packaging script no longer stops on a library with no search paths.

### Security

- A stream address that can't be reduced to a credential-free reference is no longer written to watch history.
- A catalog save still running in the background can't bring back a deleted playlist's cache.
- A very long line in an M3U playlist can no longer hang the app.

## 1.0.0 - 2026-10-31

First public version. Earlier private builds were called Lumen.

### Security

- Only network streaming addresses can reach the player. Malicious playlists could previously use mpv's special protocols to read or overwrite local files.
- Xtream passwords moved from a local file to the macOS Keychain, with automatic migration.
- API requests are no longer stored in a disk cache, which kept passwords in plain text. Existing caches are deleted at launch.
- Stream URLs and M3U entry ids no longer end up in watch history, and app data is now private to the user.
- mpv's script and yt-dlp support are turned off.
- Catalog, playlist and artwork downloads are size-limited.
- The parental PIN now uses salted PBKDF2. Existing PINs upgrade on next use.

### Fixed

- Live channels no longer jump back into earlier video after a dropped connection. FFmpeg was reconnecting inside the running stream, which hid the failure and spliced in whatever the server sent next. Retune now reconnects cleanly itself.
- Unseekable on-demand files can no longer restart from the beginning after a connection drop.
- The display no longer sleeps during playback.
- A failed start, or leaving before the first frame, no longer overwrites a saved resume point.
- Continue Watching works for M3U playlists.
- Passwords containing `+` or `/` work correctly.
- Absurd EPG times or media durations from a provider can no longer crash the app.
- The buffer indicator shows the real amount buffered.
- The Refresh button no longer disappears after switching playlists mid-refresh, and a deleted playlist's catalog can no longer be saved back to disk.

### Changed

- Packaged builds declare their true minimum macOS version.
- Source builds work with Apple Silicon and Intel Homebrew.
- Developer flags are removed from release builds.
- The Add Playlist form warns when an Xtream server or M3U link uses plain HTTP.
