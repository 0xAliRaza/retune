<div align="center">

<img src="docs/icon.png" width="112" alt="Retune app icon">

# Retune

**A small, private, keyboard-driven IPTV player for the Mac.**

Free and open source. No paid tier, no accounts, no ads, no tracking.

[![CI](https://github.com/0xAliRaza/retune/actions/workflows/ci.yml/badge.svg)](https://github.com/0xAliRaza/retune/actions/workflows/ci.yml)
[![License: GPL-3.0-or-later](https://img.shields.io/badge/license-GPL--3.0--or--later-blue)](LICENSE)
![macOS](https://img.shields.io/badge/macOS-native-lightgrey)

[Download](#download) · [Run it locally](#run-it-locally) · [Security](#security-and-privacy) · [Shortcuts](#keyboard-shortcuts)

<img src="docs/screenshots/movies.png" width="860" alt="Retune browsing a demo movie library">

<sub>Screenshots use made-up demo data.</sub>

</div>

> [!IMPORTANT]
> **Retune is only a player.** It comes with no channels, playlists, subscriptions or media, and it isn't affiliated with any provider. You bring your own legal source, and you're responsible for having the rights to what you watch.

## Why Retune

You already pay your IPTV provider. Paying again every month just for an app to open that service felt wrong, so I built the player I wanted. When my own subscription was about to end, I cleaned it up and gave it away.

- **A real Mac app.** SwiftUI with hardware decoding through [mpv](https://mpv.io), not a web page in a wrapper.
- **Keeps up with big catalogs.** Tested against a real provider with over 88,000 channels, movies and series.
- **Keyboard first.** Every action has a shortcut, and channels flip like a TV remote.
- **Yours.** No Retune server, account or analytics. Your login only goes to your provider.
- **Readable.** About 7,000 lines of GPL-licensed Swift.

## What you get

| | |
| --- | --- |
| **Sources** | Xtream Codes, M3U links and local M3U files, with several playlists side by side |
| **Live TV** | Now and Next guide on Xtream, recent channels, last-channel jump, automatic reconnection |
| **Movies and series** | Posters, plots, seasons, resume points, Continue Watching, next-episode autoplay |
| **Library** | Favorites, instant accent-insensitive search, and hide, pin or lock categories |
| **Playback** | Audio and subtitle tracks, subtitle styling and timing, speed control, screenshots, stats overlay |
| **Family** | PIN-protected categories |
| **Layouts** | Grid, list and compact views for each section |

<table>
  <tr>
    <td><img src="docs/screenshots/live.png" alt="Live TV channel list with demo channels"></td>
    <td><img src="docs/screenshots/series.png" alt="Series grid with demo posters"></td>
  </tr>
</table>

Series and the Now and Next guide need an Xtream Codes login, because M3U playlists don't carry that data.

**Not here yet:** iPhone, iPad, Apple TV and Windows versions, recording, Picture in Picture, media keys, and full VoiceOver labels.

## Install

### Download

1. Get the DMG from the [latest release](https://github.com/0xAliRaza/retune/releases/latest).
2. Open it and drag **Retune** to **Applications**.
3. Open Retune. macOS blocks it the first time, because the app isn't notarized by Apple yet.
4. Go to **System Settings → Privacy & Security**, scroll down and click **Open Anyway**.

Each download needs **Apple Silicon** and the macOS version listed on its release. If your Mac doesn't match, [run it locally](#run-it-locally).

Notarization costs $99 a year, and this is a free project for now. If you'd rather not trust a downloaded binary, building it yourself takes a few minutes.

### Run it locally

You need macOS 14 or newer (Apple Silicon or Intel), about 2 GB of free disk space and [Homebrew](https://brew.sh). You don't need the full Xcode app.

**1. Install Apple's command line tools.** If they're already installed, that's fine.

```bash
xcode-select --install
```

**2. Install libmpv, the playback engine.** It pulls in FFmpeg, so it can take several minutes.

```bash
brew install mpv
```

**3. Get the code.**

```bash
git clone https://github.com/0xAliRaza/retune.git
```

```bash
cd retune
```

**4. Build it and install it to `/Applications`.** Leave off `--install` to build to `build/Retune.app` instead.

```bash
./scripts/build-app.sh --install
```

| Task | Command |
| --- | --- |
| Update | `git pull && ./scripts/build-app.sh --install` |
| Run for development | `swift run Retune` |
| Run the tests | `./scripts/test.sh` (not `swift test`, so it also works with only the command line tools) |
| Make your own DMG | `brew install dylibbundler`, then `./scripts/package.sh`. The app and DMG land in `build/`. |

A local build links your Homebrew libmpv, so keep `mpv` installed.

If the build fails:

| Message | Fix |
| --- | --- |
| `mpv/client.h file not found` | Run `brew install mpv`, then try again. |
| `no such module 'Testing'` | Use `./scripts/test.sh` instead of `swift test`. |
| Odd errors after moving the folder | Run `swift package clean`, then rebuild. |
| `xcrun: error: invalid active developer path` | Run `xcode-select --install`. |
| The app opens, then quits immediately | Run `brew upgrade mpv`, then rebuild. |

## Getting started

1. Open Retune and click **Add Playlist**.
2. Choose how you connect:
   - **Xtream Codes:** enter your server, username and password. Pasting a full `get.php` link into the server field fills in all three.
   - **M3U URL:** paste your playlist link.
   - **M3U File:** choose a `.m3u` or `.m3u8` file.
3. Wait for the first catalog download. After that, Retune opens instantly and refreshes in the background.

## The Mac password popup

A fresh install doesn't ask for anything. After an update or a rebuild, macOS may show one or two popups before Retune can read your saved provider password:

1. *Retune wants to use your confidential information stored in "io.github.0xaliraza.retune.playlist" in your keychain*
2. *Retune wants to access key "io.github.0xaliraza.retune.playlist" in your keychain*

**Type your Mac password and click Always Allow with the mouse, each time.** That keeps it quiet until Retune next changes. Pressing Return picks **Allow**, which only lasts for that launch.

- Both popups are about the same saved password. macOS checks two separate permissions, and each one asks.
- **Retune never sees your Mac password.** You're typing into a macOS dialog, and the app only gets a yes or no.
- "Login keychain password" means your Mac password, unless you've deliberately changed it.
- **Deny** is safe too, but Retune can't log in until you allow it or enter your provider password again.

Apps signed with a paid Apple Developer ID rarely show this, because every version has the same identity. Retune doesn't have one yet, so macOS ties the permission to the exact build, and each update looks like a new app.

Only type your Mac password into this kind of system dialog. If something inside the Retune window asks for it, don't enter it, and please [report it](SECURITY.md).

## Security and privacy

You're giving an app your login, so here are straight answers, including the parts that aren't perfect. [SECURITY.md](SECURITY.md) has the full threat model, known limitations and how to report a vulnerability privately.

**Your password.** It goes into the macOS Keychain, the same place Safari keeps passwords. It's never written to a Retune file, never logged, and only sent to the server you entered.

**M3U links are different.** A provider's M3U link often has your password inside it. Retune keeps that link in a local file readable only by your macOS user, but that file isn't encrypted.

**Plain HTTP.** Xtream Codes puts your username and password in web addresses, and most providers only offer plain HTTP. Anyone on the network path, such as a shared Wi-Fi network, could read your login and see what you're watching. Retune can't fix that, but it warns you when you enter a plain HTTP address.

<img src="docs/screenshots/plain-http-warning.png" width="420" alt="The playlist form warning that an address uses plain HTTP">

- An address with no `https://` in front is treated as plain HTTP, and Retune doesn't test whether your provider offers HTTPS, so type it in full if they support it.
- A VPN you trust protects the part between you and the VPN.
- Don't reuse your IPTV password anywhere else.

**Tracking.** There's no analytics, crash reporting, ads, account or update check. Retune only contacts your provider and the artwork hosts your playlist points to, and those hosts can see your IP address when posters load. You can check this by searching the code or watching the app's traffic in a tool like [Little Snitch](https://www.obdev.at/products/littlesnitch/).

**Hostile playlists.** Retune treats every playlist, server response, image and stream as hostile:

- Only network streaming addresses reach the player, which blocks mpv's special addresses that could read or overwrite local files. A real version of this bug was found and fixed before release.
- mpv's scripting and yt-dlp support are off.
- Downloads have size limits and timeouts, and odd dates and durations are bounds-checked.

No software can promise perfection. Retune doesn't use the App Sandbox yet, so a serious bug in mpv or FFmpeg could reach your files. Stay on the latest release, and keep `mpv` updated if you built from source.

**Notarization.** It means Apple scanned a build, not that it had a security review. You can compare the DMG with the SHA-256 checksum on its release page, or better, [build it yourself](#run-it-locally).

**Parental PIN.** It's enough to stop a child, not a determined adult. It's stored as a salted PBKDF2 hash, but a short PIN can be guessed by anyone with access to your macOS account.

**Legality.** The player is legal. IPTV is just a way of delivering video, and plenty of it is legitimate. What you stream is your responsibility. Retune doesn't provide or recommend sources, and issues asking for them will be closed.

### What's stored on your Mac

Your data is in `~/Library/Application Support/Retune`, private to your macOS user:

| File | Contents |
| --- | --- |
| `playlists.json` | Playlist names and server addresses, and M3U links |
| `Catalogs/` | Cached channel, movie and series lists |
| `library.json` | Favorites, watch progress and hidden categories |

Watch history stores anonymous references rather than stream addresses, so your password doesn't end up there. M3U links are the exception again: `playlists.json` keeps the link and `Catalogs/` keeps its stream addresses. These files aren't encrypted, so they're included in unencrypted backups.

Posters and channel logos are cached separately in `~/Library/Caches/Retune/Artwork`.

### Delete everything

1. Quit Retune and drag it from Applications to the Trash.
2. Remove its data:

```bash
rm -rf ~/Library/Application\ Support/Retune ~/Library/Caches/Retune ~/Library/Caches/io.github.0xaliraza.retune ~/Library/HTTPStorages/io.github.0xaliraza.retune
```

```bash
defaults delete io.github.0xaliraza.retune
```

3. Open **Keychain Access**, search for `retune`, and delete its entries.

## Keyboard shortcuts

Press `?` in the app to see these anytime.

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

## Troubleshooting

| Problem | What to try |
| --- | --- |
| A channel won't start | Your plan may be at its connection limit. Stop playback on other devices and retry. |
| Audio or video stutters | In **Settings**, change the live stream format to HLS, which copes better with weak connections. |
| A channel has no sound | Retune shows a notice when the stream has no audio track. That's a provider issue. |
| A live channel jumps back after a dropout | Retune reconnects when a stream drops. If your provider's backup server is behind, it sends older video, and no player can avoid that. |
| "Saved password is missing" | Keychain access was denied. Edit the playlist and enter your password again. |
| macOS asks for your password after an update | [That's expected](#the-mac-password-popup). Enter your Mac password and click **Always Allow**. |

Retune can't help with provider accounts or find you a source, so please keep issues about the app itself.

## How this was built

Retune began as a tool for one person, and it was written with heavy use of AI, chiefly [Claude Code](https://claude.com/claude-code). Before release, it went through:

- A security review of passwords, playlists and network data, which fixed real problems, including the file overwrite bug above and passwords sitting in a network cache
- Fault-injection testing of the live player, with connections cut on purpose, which found the root cause of a replay glitch
- Testing against a real provider's live TV, movies and series
- Automated tests for the core logic, with bug-fix tests proven to fail without their fix
- Secret scanning of the full git history in CI

It has **not** had an independent security audit. If you find a problem, please [report it](SECURITY.md), and I'll fix it.

## Contributing

Bug reports and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md). If you're using an AI coding tool, point it at [AGENTS.md](AGENTS.md), which has the architecture and project rules.

```text
Sources/CMPV        libmpv bindings
Sources/RetuneCore  Provider API, parsing, library state and storage (no UI, fully testable)
Sources/Retune      SwiftUI app and the mpv player
Tests               Unit tests for RetuneCore
scripts             Build, test and packaging
```

## License

Retune is free software under the [GNU General Public License v3.0 or later](LICENSE). See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for the libraries bundled in the packaged app.

Retune stands on [mpv](https://mpv.io) and [FFmpeg](https://ffmpeg.org), which do the hard work.
