# AGENTS.md

Instructions for AI coding agents working on this repository, and for assistants helping someone install or use Retune. Read [llms.txt](llms.txt) for a short summary. Human documentation is in [README.md](README.md).

## What this is

Retune is a native macOS IPTV player: Swift 6 tools, SwiftUI, libmpv through the render API. It's a Swift Package, not an Xcode project. It plays the user's own Xtream Codes or M3U source and includes no content. It has no backend, accounts, telemetry or update check.

## Commands

| Task | Command |
| --- | --- |
| Debug build | `swift build` |
| Run | `swift run Retune` |
| Test | `./scripts/test.sh` (never bare `swift test`, which fails on Command Line Tools only setups) |
| Release app, install to `/Applications` | `./scripts/build-app.sh --install` |
| Self-contained app and DMG | `./scripts/package.sh` (needs `brew install dylibbundler`) |

Requires macOS 14+, Command Line Tools and `brew install mpv`. `Package.swift` finds libmpv under `/opt/homebrew` or `/usr/local`.

## Layout

| Path | Purpose |
| --- | --- |
| `Sources/CMPV` | System library target exposing libmpv headers |
| `Sources/RetuneCore` | Provider API, parsers, catalog, library state, Keychain, PIN hashing. No UI or mpv. Put logic here. |
| `Sources/Retune/Player` | `MPVPlayer` (engine), `MPVVideoView` (rendering), `PlaybackSession` (queue, reconnect, progress) |
| `Sources/Retune/AppModel.swift` | App state and orchestration |
| `Sources/Retune/Views` | SwiftUI screens |
| `Sources/Retune/Support/DevPlayback.swift`, `DevProbe.swift` | Debug-only hooks, compiled out of release builds |
| `Tests/RetuneCoreTests` | swift-testing suites |

## Rules that must hold

**Security**

- Everything from a playlist, provider, artwork host or stream is hostile.
- Every stream must pass `StreamURLPolicy.isAllowed`, at parse time and again in `MPVPlayer.load`. Never widen the scheme allowlist to include `file`, `av`, `edl`, `lavf` or anything local. Those can read or overwrite files.
- Network bodies must use `boundedData` with a size limit.
- API requests must use `URLSession.retuneAPI`. It's ephemeral because Xtream URLs contain the password, and any disk cache would store it.
- Passwords belong only in `SecretStore`. Watch history stores locators from `XtreamClient.locator` or `opaqueLocator`, never stream URLs.
- Never log URLs, usernames or passwords, including in debug hooks.
- Write files through `JSONFileStore` so they stay atomic and private (`0700` folders, `0600` files).
- Keep `load-scripts=no`, `ytdl=no` and `load-unsafe-playlists=no` in the mpv setup.

**Privacy and scope**

- No analytics, crash reporting, update checks, or any new network destination.
- Never add, link to or recommend channels, playlists or providers. Don't put real provider names or credentials anywhere, including tests and screenshots. Use `example.com`-style placeholders.

**Playback**

- Don't re-enable FFmpeg `reconnect_streamed` for live streams. It splices a new connection into the running demuxer, hides the failure and causes old video to replay. Live recovery belongs to `PlaybackSession`, using `StreamProfile.live`.
- mpv properties persist across files, so per-stream settings must go through `StreamProfile` before each load.
- Don't save resume progress unless `engine.hasVideoFrame` is true, or a failed start overwrites a real resume point.

**Code**

- Logic changes need tests. A bug fix needs a test that fails without the fix.
- Match the surrounding style, keep functions small, and don't leave comments about the current task.
- Licensed GPL-3.0-or-later because the packaged app bundles GPL libmpv and FFmpeg builds. Update `THIRD_PARTY_NOTICES.md` when bundled libraries change.

## Debug hooks

Debug builds only:

```text
Retune --play <URL> [--live]
Retune --probe refresh|live|movie|episode|resume [--probe-index 0] [--probe-seconds 30]
Retune --screens <folder>
```

Read their logs with:

```bash
log stream --predicate 'subsystem == "io.github.0xaliraza.retune" AND category == "dev"'
```

Set `CFFIXED_USER_HOME` to a temporary folder to keep a test run away from real user data. It doesn't isolate the Keychain.

## Helping a user

- For install help, follow [Run it locally](README.md#run-it-locally).
- `mpv/client.h file not found` means libmpv isn't installed.
- "Open Anyway" in Privacy & Security is the expected first launch for unnotarized builds.
- Don't help users find IPTV sources or bypass provider limits. Retune is only a player.
- Don't tell anyone that plain HTTP logins are safe. They aren't, and the README explains why.
