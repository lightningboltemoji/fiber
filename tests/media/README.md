# Media tests

Checks that H.264, HEVC and AAC play through macOS's decoders as they did
through Chromium's (see [`.agents/MEDIA.md`](../../.agents/MEDIA.md)). Run them
after changing `core/media/` or its patches, and after each Chromium rebase.

Needs ffmpeg with libx264, libx265, libmp3lame and libopus (Homebrew's has
them), Xcode's `swiftc`, Python 3, and Node 22 or later for `site.mjs`.

```sh
video/gen.sh    # the video streams, and ffmpeg's and VideoToolbox's decodes of each (seconds)
audio/gen.sh    # the audio files, and Apple's decode of each

./runner.py video/video.html    # WebCodecs, <video>, MSE and HLS: every frame's luma, in order
./runner.py video/webrtc.html   # WebRTC calls: H.264 (three profiles), H.265, VP8
./runner.py audio/webaudio.html # decodeAudioData and WebCodecs against afconvert, sample by sample; <audio>, MSE, HLS
```

`runner.py` serves this directory, opens the page in
`chromium/src/out/Default`'s Fiber (`--out Release` for the other) with a
fresh profile, and prints each test as it finishes, then a summary. It exits
1 if a test failed. `?only=<regex>` after the page runs some of it:
`./runner.py 'video/video.html?only=^mse_'`. Fiber's log goes to `fiber.log`.

A page's `known` tests are limitations `.agents/MEDIA.md` describes: they
run, show as `KNOWN`, and don't fail the page. One that starts passing is
listed under `fixed`.

## Real sites

```sh
node site.mjs https://www.youtube.com/watch?v=… --h264 --secs 30
```

opens a page in Fiber over the DevTools protocol and reports the decoders each
player chose, how far playback got, and dropped frames and errors. `--h264`
hides VP9 and AV1 from the page, so sites that prefer them use H.264.
`--shot file.png` saves a screenshot at the end. Compare against Google
Chrome with `--binary "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"`.

Sites that have been checked: YouTube (`--h264`); live HLS from CBS News
(`https://www.cbsnews.com/live/`) and DW; Apple's HLS examples (H.264, and
HEVC Main 10 in fMP4); Mux's test stream
(`https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8`). Reddit and X ask an
automated browser to log in.
