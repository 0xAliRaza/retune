# Third-party notices

Lumen's source code is licensed under GPL-3.0-or-later. Source builds link your own copy of libmpv and bundle nothing.

The packaged app and DMG also contain third-party libraries from [Homebrew](https://brew.sh), which keep their own licenses. Together they make the distributed package subject to the GPL.

| Component | License | Source |
| --- | --- | --- |
| [mpv](https://mpv.io) (libmpv) | GPL-2.0-or-later, parts LGPL-2.1-or-later | https://github.com/mpv-player/mpv |
| [FFmpeg](https://ffmpeg.org), built with GPL components | GPL-3.0-or-later | https://git.ffmpeg.org/ffmpeg.git |
| [x264](https://www.videolan.org/developers/x264.html) | GPL-2.0-or-later | https://code.videolan.org/videolan/x264 |
| [x265](https://www.x265.org) | GPL-2.0-or-later | https://bitbucket.org/multicoreware/x265_git |
| [Rubber Band](https://breakfastquay.com/rubberband/) | GPL-2.0-or-later | https://github.com/breakfastquay/rubberband |

Other bundled libraries are listed below. Their licenses and exact sources are recorded in the [Homebrew formula](https://formulae.brew.sh) of the same name, for the versions current when the release was built.

`SvtAv1Enc`, `archive`, `ass`, `avcodec`, `avdevice`, `avfilter`, `avformat`, `avutil`, `b2`, `bluray`, `crypto`, `dav1d`, `fontconfig`, `freetype`, `fribidi`, `glib-2`, `graphite2`, `harfbuzz`, `intl`, `jpeg`, `lcms2`, `luajit-5`, `lz4`, `lzma`, `mp3lame`, `mpg123`, `mpv`, `mujs`, `opus`, `pcre2-8`, `placebo`, `png16`, `rubberband`, `samplerate`, `shaderc_shared`, `ssl`, `swresample`, `swscale`, `uchardet`, `udfread`, `unibreak`, `vmaf`, `vpx`, `vulkan`, `x264`, `x265`, `zimg`, `zstd`

To get the exact source for a release, install the same formula versions with Homebrew and run `brew fetch --build-from-source <formula>`. If you can't, open an issue and it will be provided, as the GPL requires.

Patent licensing for video and audio codecs varies by country and is your responsibility.
