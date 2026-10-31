# Security policy

## Reporting a vulnerability

Please don't open a public issue. Use GitHub's **Report a vulnerability** button on the [Security tab](../../security/advisories/new), which reaches the maintainer privately.

Include the affected version, steps to reproduce and what an attacker gains. This is a solo project, so I aim to reply within a week. Fixes go to the latest release only.

## Threat model

Retune's main risk is **untrusted input**. Playlists, provider responses, artwork and video streams all come from third parties, so a hostile playlist or server must not be able to reach the user's files or credentials.

| Area | Protection |
| --- | --- |
| Stream URLs | Only `http`, `https`, `rtmp(s)`, `rtsp(s)`, `rtp` and `udp` reach mpv, checked both when parsing and at load. This blocks mpv's special protocols, such as `av://`, `edl://` and `file://`, which can read or overwrite local files. |
| mpv | No scripts, no yt-dlp integration, and unsafe playlist references disabled. |
| Xtream passwords | Stored in the macOS Keychain. Keychain access isn't shared with other apps without the user's approval. |
| Network caching | API requests use no URL cache and no cookies, because Xtream puts the password in the URL. Any leftover app network cache is deleted at launch. |
| Local data | `~/Library/Application Support/Retune` is `0700` and its files are `0600`. Files are written atomically. |
| Watch history | Stores credential-free locators and hashed M3U ids instead of stream URLs. |
| Hostile responses | Catalog and playlist downloads are capped at 256 MiB and artwork at 32 MiB, with timeouts. Dates, durations and numbers are bounds-checked before use. |
| Logging | Retune doesn't log credentials or stream URLs, and release builds have no developer hooks. |

## Known limitations

- **Plain HTTP.** Xtream Codes puts the username and password in request and stream URLs, and most providers only offer HTTP. Anyone on the network path can read them. App Transport Security is relaxed for this reason. Retune warns when you add an HTTP address, and HTTPS is used whenever the server address is HTTPS.
- **M3U links.** A provider M3U link often contains your password. It's stored in `playlists.json`, and stream URLs are stored in the catalog cache. Both are private to your user account, but not encrypted, so they're included in unencrypted backups. The Keychain only protects Xtream logins.
- **No App Sandbox or notarization yet.** Retune runs with your user's permissions, so a memory-safety bug in mpv or FFmpeg could reach your files. Keep Homebrew's `mpv` updated if you build from source, and use the latest release otherwise.
- **Keychain prompts after updates.** Builds without a stable signature can't keep Keychain access across updates, so macOS asks the user to approve each new build. The prompt is a macOS system dialog, and Retune never receives the Mac password.
- **The parental PIN is a deterrent, not a security boundary.** It's stored as a salted PBKDF2 hash, but a short numeric PIN can be guessed offline, and the library file can be edited by anyone using your macOS account.
- **Local access.** Retune doesn't defend against malware already running as your user, or anyone with an unlocked session.
