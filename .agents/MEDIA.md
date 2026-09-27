# Fiber: media

How Fiber plays H.264, HEVC and AAC with macOS doing the codec work. The code
is in `core/media/` (`//fiber/media`); the hooks it needs are in
`patches/chromium/media-*`, `content-renderer-*`,
`third_party-blink-renderer-*` and `third_party-ffmpeg-*`.

## The rule

Fiber ships no code of its own that implements a patent-pool codec's decoding
or encoding process. macOS decodes and encodes H.264, HEVC and AAC
(VideoToolbox and AudioToolbox); Fiber's code parses containers, parameter
sets and headers, and passes data through, as Firefox does on macOS.

That means, against a plain `proprietary_codecs` Chromium build:

| Chromium's | In Fiber |
|---|---|
| ffmpeg's H.264 and AAC decoders (the Chrome build of ffmpeg) | Chromium's build of ffmpeg (`args.gni`), plus its ADTS demuxer and AAC header parser (below) |
| OpenH264, WebRTC's software H.264 (`rtc_use_h264`) | off (`media_use_openh264 = false`) |
| `H264Decoder` and `H265Decoder` (`media/gpu/`), which run each standard's decoded picture buffer (reference marking, reference lists, picture order counts) before VideoToolbox decodes | `video/`'s passthrough decoders |
| AudioToolbox for xHE-AAC only | AudioToolbox for all AAC, in playback, WebCodecs and Web Audio |

What's left of those in the binary is unreachable, and the linker drops it:
in `make size`'s linker map for `out/Release`, `H264Decoder`, `H265Decoder`,
their DPBs and POC code and the two accelerators are all dead-stripped, and
ffmpeg compiles no H.264, HEVC or AAC decoding. Check it again after a rebase.

Everything else is Chromium's: VP8, VP9, AV1, Opus, Vorbis, FLAC and MP3
(royalty-free, or expired) decode as in Chrome; Symphonia has no AAC.

## Video: `video/`

`VideoToolboxVideoDecoder` (GPU process) keeps its decompression session,
frame converter and output queue; what it drives for H.264 and HEVC is
`fiber::CreateVideoToolboxDecoder()` instead of `H264Decoder`/`H265Decoder`
(`patches/chromium/media-gpu-mac-video_toolbox_video_decoder.cc.patch`).

`PassthroughDecoder` takes one frame per input buffer (as Chromium's demuxers,
WebCodecs and WebRTC deliver them), in Annex B:

1. The codec's parser (`H264Parser`, `H265Parser`) records parameter sets and
   the ones the frame's slices use, and reads the SPS for size, visible rect,
   profile, bit depth, chroma sampling and color space (from the VUI, or the
   container). A new size, profile, bit depth or chroma sampling returns
   `kConfigChange`.
2. A new VPS or SPS, or a parameter set change at a keyframe, makes a new
   `CMVideoFormatDescription`; a PPS change elsewhere goes in-band, as
   Chromium's accelerators did.
3. The frame's slices go to VideoToolbox as one sample, with a `CodecPicture`.
4. Frames come out in presentation order, which is timestamp order: frames
   are held back until more are pending than the SPS says can be reordered
   (H.264: `max_num_reorder_frames`, or 0 for POC type 2 and the intra
   profiles, or the level's DPB size; HEVC: `sps_max_num_reorder_pics`). A
   new coded video sequence (IDR, or an IRAP with NoRaslOutputFlag) lets all
   earlier frames out. Flush lets everything out; reset drops it.
5. Where decoding can start is as before: H.264 waits for an IDR or a recovery
   point SEI (frames before the recovery point are decoded but not shown, and
   leading frames after it are skipped), and flags the first sample to reset
   VideoToolbox; HEVC waits for an IRAP and skips the RASL frames of one it
   starts at.

HEVC with alpha (the auxiliary layer Apple's encoder writes) is passed through
with the base layer; HDR metadata from SEI (mastering display, content light
level, T.35) and the color space reach the frame as before.

**What VideoToolbox takes.** Chromium sends the H.264 its hardware path
can't decode (interlaced, High 10, 4:2:2 and 4:4:4, and on Apple silicon
frames under 64×64) to ffmpeg. With no software H.264 in Fiber, H.264 is as
Chromium has HEVC: VideoToolbox's own software decoder takes what the
hardware refuses, and the decoder offers what VideoToolbox decodes, Baseline
to High 4:4:4 from 16×16 (the `media-gpu-mac-video_toolbox_video_decoder.cc`
patch). WebCodecs, which routes interlaced and 4:4:4 H.264 to a software
decoder, doesn't where the build has none
(`third_party-blink-renderer-modules-webcodecs-video_decoder_helper.cc`).

**Trusting timestamps.** Ordering by timestamp, not by picture order count, is
what keeps the decoded picture buffer process out. A stream whose timestamps
are wrong (duplicated, or in decoding order) comes out in their order; H264Decoder
would have fixed it. Firefox has the same limitation. ffmpeg's HLS fMP4 muxer,
stream-copying B-frames, writes such timestamps; real packagers don't.

## AAC: `hooks/audio_toolbox_aac`, `aac/`

Chromium's `AudioToolboxAudioDecoder` (GPU process) takes all AAC
(`patches/chromium/media-filters-mac-audio_toolbox_audio_decoder.*`):

- **The format.** AudioToolbox is given the stream's AudioSpecificConfig as
  `AudioToolboxAudioSpecificConfig()` rewrites it, and decodes the richest
  layer it lists: HE-AAC's SBR at twice the core rate, HE-AAC v2's PS in
  stereo, AAC-LD and AAC-ELD under their own format IDs. Where an AAC-LC
  config doesn't signal SBR and its core runs at 24 kHz or less (ADTS never
  signals it, so HE-AAC in MPEG-2 TS, HLS and radio streams arrives that way),
  the rewrite signals SBR, and PS for mono, as Chromium does for an
  `mp4a.40.5` codec string: AudioToolbox decodes those layers if they're
  there and upsamples the core if they're not.
- **ADTS** headers are stripped before AudioToolbox sees a frame. AAC that
  comes with no AudioSpecificConfig is ADTS (WebCodecs' `AudioDecoder`
  without a description), which says what it is in each frame's header, as
  ffmpeg's decoder reads it: the converter is made for the first frame's
  (`AdtsHeaderAudioSpecificConfig()`).
- **The decoder's delay.** AudioToolbox leaves the SBR decoder's delay (962
  frames) out of a stream's first output, while the stream's trims, per
  packet, assume it's there; the decoder puts it back as silence and has
  `AudioDiscardHelper` drop it, as it does for MP3. At the end of the stream
  it tells AudioToolbox so, which puts out the frames it held back.
- **Channel order** (5.1 and up) is AudioToolbox's, mapped to Chromium's by the
  output layout Chromium's decoder sets.

The renderer describes what will come out: `ffmpeg_common.cc` corrects the
config ffmpeg reads (HE-AAC v2's mono, ADTS's core rate) with
`AudioToolboxOutputFormat()`, as Chromium's MP4 parser does for MSE. Without
that, `src=` playback of HE-AAC in ADTS fails (it doesn't allow a mid-stream
rate change) and Web Audio can't size its buffer.

**ADTS demuxing.** Chromium's build of ffmpeg leaves out the ADTS (`.aac`)
demuxer and the AAC header parser, which only frame the stream; Chrome's has
them. Fiber adds them (`patches/chromium/third_party-ffmpeg-*`, patches to the
nested `third_party/ffmpeg` repository), without the decoder; the demuxer
reads the stream's parameters from its first header, since there's no decoder
to find them, and `ffmpeg_common.cc` makes the AudioSpecificConfig the header
implies. That covers `<audio src="….aac">` (internet radio, too) and Web
Audio's `.aac`.

## Web Audio: `web_audio/`

`decodeAudioData` decodes in the renderer, on a thread pool task, with
`media::AudioFileReader`, which expects each decoder call to finish before it
returns. AudioToolbox can't run in the renderer's sandbox, so for AAC the
reader gets `GpuAudioDecoder` (`fiber::CreateWebAudioDecoder()`, passed in by
`content/renderer/media/audio_decoder.cc`): a `MojoAudioDecoder`, reached
through the process's `InterfaceFactory` as WebCodecs' is, on a sequence of its
own. Initialization and the final flush wait for the GPU process; other
packets are queued and return at once, so the round trips overlap demuxing
(a 3-minute track decodes in about a second). The decode task may block
(`patches/chromium/third_party-blink-renderer-modules-webaudio-base_audio_context.cc.patch`);
threads with a task runner of their own, like the main thread, never do.

## WebRTC

With no software H.264, Chromium wouldn't offer VideoToolbox's H.264 encoder
to WebRTC (it assumes a software fallback), and its decoder adapter would try
to fall back to software for small streams when many are open. Fiber treats
H.264 as Chromium treats HEVC, and Android without OpenH264: hardware only,
no fallback (`patches/chromium/third_party-blink-renderer-platform-peerconnection-*`).
VideoToolbox's Baseline is its Constrained Baseline, which is what WebRTC
endpoints ask for (`42e01f`), so Fiber offers that too.

## Testing

What's been checked, frame by frame or sample by sample against ffmpeg's and
Apple's own decodes (`tests/media/`, which says how to run it):

- WebCodecs `VideoDecoder`, AVCC and Annex B: H.264 (B-pyramid, 5 B-frames,
  Baseline, open GOP, intra refresh, 1080p crop, interlaced, High 10, 4:2:2,
  4:4:4, 32×32, VideoToolbox's encoder) and HEVC (closed and open GOP with
  RASL, Main 10, PQ, HLG, alpha, VideoToolbox's encoder); starting at the
  second keyframe; flush and go on; resolution changes in-band and by
  reconfiguring; parameter sets after a frame's slices. Every frame's luma
  matches ffmpeg's, or where they differ VideoToolbox's own, in order.
- `<video>`: progressive MP4; MSE whole, seeking, appended out of order (closed
  GOPs), resolution changes; HLS in MPEG-2 TS and fMP4; HEVC with alpha over
  a background.
- WebRTC calls between two peer connections: H.264 Constrained Baseline,
  Baseline and High, H.265, VP8, with frames in order and ~30 ms delay.
- `decodeAudioData`: AAC-LC mono, stereo and 5.1, HE-AAC mono and stereo,
  HE-AAC v2, AAC-LD, AAC-ELD, ffmpeg's encoder, AAC in an MP4 with video, raw
  ADTS (LC and HE-AAC), six at once, a frame removed mid-decode; sample-exact
  against `afconvert`. WebCodecs `AudioDecoder` the same, after a seek, and
  ADTS without a description.
- `<audio src>` of `.aac`, MSE `audio/aac`, HLS HE-AAC.
- Real sites: YouTube with VP9 and AV1 hidden (H.264), live HLS (CBS News,
  DW), Apple's H.264 and HEVC Main 10 examples, Mux's test stream. Reddit and X
  want a login from an automated browser.

Not tested, for want of an encoder: field-coded (PAFF) interlaced H.264.

Known differences from Chrome:

- Wrong timestamps order frames wrongly (above).
- Interlaced H.264 is VideoToolbox's decode, not ffmpeg's, and the two
  differ on the odd frame.
- Routed into Web Audio, an `<audio>` or `<video>` plays at the stream's
  configured rate, which for HE-AAC in ADTS over MSE or HLS is the core's: the
  SBR band is lost there, in Chrome too.
- HE-AAC decoded from a seek point matches a decode from the start to about
  -80 dB, not exactly: SBR's noise depends on where decoding started, in any
  decoder.
