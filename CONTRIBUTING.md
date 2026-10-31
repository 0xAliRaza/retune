# Contributing

Bug reports and pull requests are welcome. For a larger feature, please open an issue first so we can agree on the approach.

## Setup

```bash
brew install mpv
```

```bash
swift build
```

```bash
./scripts/test.sh
```

## Pull requests

- Logic changes need tests, and a bug fix needs a test that fails without the fix.
- Put logic in `RetuneCore` where you can, since it has no UI or mpv dependency and is easy to test.
- Follow the style of the surrounding code, and keep functions small.
- Run `./scripts/test.sh` before pushing. CI runs the same tests plus a secret scan.

## Rules for this project

- **Never commit real credentials, playlists or provider details**, including in tests, screenshots, logs and issues. Use `example.com`-style placeholders.
- Treat everything from a playlist or provider as hostile. New stream or artwork paths must go through `StreamURLPolicy` and `boundedData`.
- Nothing may send data anywhere except the user's provider and artwork hosts.
- Retune doesn't bundle, link to or recommend content or providers, and we won't accept changes that do.

## Reporting bugs

Include your macOS version, Mac model, Retune version and whether you use Xtream or M3U. The stats overlay (`I`) is helpful for playback problems. Remove your server address, username and password from anything you paste.

For security problems, follow [SECURITY.md](SECURITY.md) rather than opening an issue.

By contributing, you agree that your work is licensed under GPL-3.0-or-later.
