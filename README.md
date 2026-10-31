# Lumen

A free, open-source, native macOS player for your own IPTV subscription. Log in with Xtream Codes or an M3U playlist, and get live TV, movies and series in a fast, keyboard-first Mac app.

No ads, no account, no telemetry. Built with SwiftUI and [libmpv](https://mpv.io).

> [!IMPORTANT]
> **Lumen is only a player. It includes no channels, playlists, subscriptions or media, and it isn't affiliated with any provider.** You bring your own legally obtained source, and you're responsible for having the rights to whatever you watch through it.

## Why Lumen

Most Mac IPTV apps are subscriptions, iPad ports or Electron wrappers. I wanted a player that felt like a proper Mac app, so I built one for myself and published it for anyone with the same problem.

- **Native and fast.** SwiftUI interface, hardware decoding through mpv, and instant browsing across catalogs of 80,000+ titles.
- **Keyboard first.** Everything has a shortcut, and channel surfing works like a TV remote.
- **Yours.** Free and open source, with no servers of its own. Your login goes only to your provider.

## Features

- **Sources:** Xtream Codes, M3U links and local M3U files, with several playlists side by side
- **Live TV:** Now/Next guide on Xtream, recently watched, last-channel jump, and automatic reconnection when a stream drops
- **Movies and series:** posters, plots, seasons, resume points, Continue Watching and next-episode autoplay
- **Library:** favorites, instant accent-insensitive search, and hide, pin or lock categories
- **Parental lock:** PIN-protected categories
- **Playback:** audio and subtitle tracks, subtitle styling and timing, playback speed, screenshots and a stats overlay
- **Layouts:** grid, list and compact views per section

Series and the Now/Next guide need an Xtream Codes login, because M3U playlists don't carry that data.

## Install

### Download

Get the DMG from the [Releases](../../releases) page, open it and drag Lumen to Applications.

Each download needs **Apple Silicon** and at least the macOS version shown on its release, because it bundles libraries built for that system. On an older Mac, build from source instead.

Releases aren't notarized by Apple yet, so macOS blocks the first launch. To open Lumen anyway:

1. Try to open Lumen, then dismiss the warning.
2. Open **System Settings → Privacy & Security**.
3. Scroll down and click **Open Anyway**.

### Build from source

You need macOS 14 or newer, the Xcode Command Line Tools and [Homebrew](https://brew.sh). Apple Silicon and Intel both build.

```bash
brew install mpv
```

```bash
git clone https://github.com/0xAliRaza/Lumen.git
```

```bash
cd Lumen && ./scripts/build-app.sh --install
```

This installs Lumen into `/Applications`. A source build uses your Homebrew libmpv, so keep `mpv` installed. Run `./scripts/package.sh` for a self-contained app and DMG, which also needs `brew install dylibbundler`.

## Getting started

1. Open Lumen and click **Add Playlist**.
2. Pick a source type:
   - **Xtream Codes:** enter your server, username and password. Pasting a full `get.php` link into the server field fills in all three.
   - **M3U URL:** paste your playlist link.
   - **M3U File:** choose a `.m3u` or `.m3u8` file.
3. Lumen downloads the catalog, then opens it instantly on later launches and refreshes it in the background.

macOS may ask to let Lumen use your Keychain. Choose **Always Allow**. Unsigned builds ask again after each update.

## Keyboard shortcuts

Press `?` in the app to see this list.

### Player

| Keys | Action |
| --- | --- |
| `Space` | Play or pause |
| `←` `→` | Back or forward 10 seconds |
| `⇧←` `⇧→` | Back or forward 60 seconds |
| `↑` `↓`, `Page Up` `Page Down` | Previous or next channel, movie or episode |
| `N` `⇧N` | Next or previous |
| `⌫` | Last watched channel |
| `L` | Channel or up-next list |
| `[` `]` `\` | Slower, faster, normal speed |
| `-` `=` | Volume down or up |
| `M` | Mute |
| `C` | Subtitles on or off |
| `F` | Full screen (or double-click) |
| `I` | Stats |
| `S` | Screenshot to Desktop |
| `Esc` | Close panel, back to browsing |

### Browsing

| Keys | Action |
| --- | --- |
| `⌘1` `⌘2` `⌘3` | Live TV, Movies, Series |
| `⌃⌘1` `⌃⌘2` `⌃⌘3` | Grid, list, compact layout |
| `⇥` `⇧⇥` | Next or previous column |
| Arrow keys, `Return` | Move around, open or play |
| `⌘[` | Back |
| `⌘F` | Search |
| `⌘R` | Refresh playlist |
| `⇧⌘N` | Add playlist |
| `⌘L` | Lock categories again |

## Privacy and security

- Lumen talks only to your provider and the artwork hosts your playlist points to. There's no analytics, telemetry or update check.
- Xtream passwords live in the macOS Keychain. Playlists, catalogs and history stay in `~/Library/Application Support/Lumen`, readable only by your user.
- Playlists are treated as untrusted input: only network streaming addresses reach the player, and responses are size-limited.
- Many IPTV providers only offer plain HTTP. On those servers your login and streams travel unencrypted, and Lumen warns you when you add one.

[SECURITY.md](SECURITY.md) covers the threat model, known limitations and how to report a vulnerability.

## Troubleshooting

| Problem | What to try |
| --- | --- |
| A channel won't start | Your plan may be at its connection limit. Stop playback on other devices, then retry. |
| Audio or video stutters | In **Settings**, switch the live format to HLS, which copes better with weak connections. |
| A channel has no sound | Lumen shows a notice when the stream itself carries no audio track. That's a provider issue. |
| A live channel jumps back after a dropout | Lumen reconnects when a stream drops. If your provider's backup server runs behind, it resends older video, and no player can avoid that. |
| "Saved password is missing" | Keychain access was denied. Edit the playlist and re-enter the password. |

Lumen can't help with provider accounts or find you a source, so please keep issues about the app itself.

## Development

```text
Sources/CMPV       libmpv bindings
Sources/LumenCore  Provider API, parsing, library state, persistence (no UI, fully testable)
Sources/Lumen      SwiftUI app and the mpv player
Tests              Unit tests for LumenCore
scripts            Build, test and packaging
```

Run the tests with `./scripts/test.sh`. It also works with only the Command Line Tools installed. See [CONTRIBUTING.md](CONTRIBUTING.md) to get involved.

## How this was built

Lumen started as a personal tool to replace a paid IPTV app, and it was written with heavy use of AI coding tools, chiefly [Claude Code](https://claude.com/claude-code). Before release it went through a security review, fault-injection testing of the live player, and regression tests for every fix. If you spot something wrong, please open an issue.

## License

Lumen is free software under the [GNU General Public License v3.0 or later](LICENSE). The GPL fits because the packaged app bundles libmpv and FFmpeg builds that are themselves GPL-licensed. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

Lumen is built on [mpv](https://mpv.io) and [FFmpeg](https://ffmpeg.org), which do the hard work.
