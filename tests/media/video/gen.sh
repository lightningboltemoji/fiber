#!/usr/bin/env bash
# Generates the video test streams (tests/media/README.md) and indexes them:
# each NAME.mp4 (progressive) gets NAME.frag.mp4 for MSE and NAME.json for the
# page (index.py), with ffmpeg's and VideoToolbox's decodes as references.
# Needs ffmpeg with libx264, libx265 and VideoToolbox, and Xcode's swiftc.
set -euo pipefail
cd "$(dirname "$0")"
q=(-hide_banner -loglevel error -y)
src() { echo "testsrc2=size=${1}:rate=30:duration=${2}"; }
frag=(-movflags frag_keyframe+empty_moov+default_base_moof)

x264() {  # name size secs x264-params [extra ffmpeg args...]
  local name=$1 size=$2 secs=$3 params=$4; shift 4
  ffmpeg "${q[@]}" -f lavfi -i "$(src $size $secs)" -c:v libx264 -pix_fmt yuv420p \
    -x264-params "$params" "$@" "$name.mp4"
}
x265() {
  local name=$1 size=$2 secs=$3 params=$4; shift 4
  ffmpeg "${q[@]}" -f lavfi -i "$(src $size $secs)" -c:v libx265 -tag:v hvc1 \
    -x265-params "log-level=error:$params" "$@" "$name.mp4"
}

# H.264: B-pyramid, deep B runs, Baseline (POC type 2), open GOP (recovery
# point SEI), intra refresh (recovery points with a frame count), 1080p (a
# cropped SPS), interlaced (MBAFF) and 32x32 (which only VideoToolbox's
# software decoder takes), High 10, 4:2:2 and 4:4:4, VideoToolbox's encoder,
# and three sizes for resolution changes.
x264 h264_bpyr 640x360 3 "keyint=30:min-keyint=30:scenecut=0:bframes=3:b-pyramid=normal:ref=4" -profile:v high
x264 h264_b5 640x360 3 "keyint=45:min-keyint=45:scenecut=0:bframes=5:b-adapt=0:b-pyramid=normal:ref=6" -profile:v high
x264 h264_base 640x360 3 "keyint=30:min-keyint=30:scenecut=0" -profile:v baseline
x264 h264_open 640x360 3 "keyint=30:min-keyint=30:scenecut=0:bframes=3:b-pyramid=normal:open-gop=1" -profile:v high
x264 h264_gdr 640x360 3 "keyint=30:bframes=0:intra-refresh=1:ref=1" -profile:v high
x264 h264_1080 1920x1080 1 "keyint=30:bframes=3:b-pyramid=normal" -profile:v high
x264 h264_mbaff 640x360 3 "keyint=30:min-keyint=30:scenecut=0:bframes=3:b-pyramid=normal:interlaced=1:tff=1" -profile:v high -flags +ildct+ilme
x264 h264_hi10 640x360 2 "keyint=30:bframes=3:b-pyramid=normal" -pix_fmt yuv420p10le -profile:v high10
x264 h264_422 640x360 2 "keyint=30:bframes=3:b-pyramid=normal" -pix_fmt yuv422p -profile:v high422
x264 h264_444 640x360 2 "keyint=30:bframes=3:b-pyramid=normal" -pix_fmt yuv444p -profile:v high444
# testsrc2 at 32x32 is mostly still; every frame differs here, so the page
# can tell them apart.
ffmpeg "${q[@]}" -f lavfi -i "$(src 32x32 2),geq=lum='mod(8*X+4*Y+5*N,256)':cb=128:cr=128" -c:v libx264 \
  -pix_fmt yuv420p -x264-params "keyint=30:bframes=3:b-pyramid=normal" -profile:v high h264_small.mp4
ffmpeg "${q[@]}" -f lavfi -i "$(src 640x360 3)" -c:v h264_videotoolbox -profile:v high -bf 2 -g 30 h264_vt.mp4
x264 h264_res_a 640x360 2 "keyint=30:bframes=3:b-pyramid=normal" -profile:v high
x264 h264_res_b 320x180 2 "keyint=30:bframes=3:b-pyramid=normal" -profile:v high -output_ts_offset 2
x264 h264_res_c 1280x720 2 "keyint=30:bframes=3:b-pyramid=normal" -profile:v high -output_ts_offset 4

# HEVC: closed and open GOP (CRA with RASL), Main 10, PQ with mastering display
# and content light level SEI, HLG, alpha (Apple's auxiliary layer),
# VideoToolbox's encoder, and two sizes.
x265 hevc_closed 640x360 3 "keyint=30:min-keyint=30:scenecut=0:open-gop=0:bframes=4:b-pyramid=1"
x265 hevc_open 640x360 3 "keyint=30:min-keyint=30:scenecut=0:open-gop=1:bframes=4:b-pyramid=1:radl=0"
x265 hevc_main10 640x360 3 "keyint=30:bframes=4" -pix_fmt yuv420p10le -profile:v main10
x265 hevc_pq 640x360 2 "keyint=30:bframes=4:colorprim=bt2020:transfer=smpte2084:colormatrix=bt2020nc:master-display=G(13250,34500)B(7500,3000)R(34000,16000)WP(15635,16450)L(10000000,1):max-cll=1000,400:hdr10=1:repeat-headers=1" -pix_fmt yuv420p10le -profile:v main10
x265 hevc_hlg 640x360 2 "keyint=30:bframes=4:colorprim=bt2020:transfer=arib-std-b67:colormatrix=bt2020nc" -pix_fmt yuv420p10le -profile:v main10
alpha=(-f lavfi -i "$(src 640x360 3)" -vf "format=rgba,geq=r='r(X,Y)':g='g(X,Y)':b='b(X,Y)':a='if(lt(hypot(X-320,Y-180),80+60*sin(N/5)),0,255)',format=bgra" -c:v hevc_videotoolbox -alpha_quality 0.75 -tag:v hvc1 -g 30)
ffmpeg "${q[@]}" "${alpha[@]}" hevc_alpha.mp4
ffmpeg "${q[@]}" -f lavfi -i "$(src 640x360 3)" -c:v hevc_videotoolbox -tag:v hvc1 -g 30 -bf 2 hevc_vt.mp4
x265 hevc_res_a 640x360 2 "keyint=30:bframes=4"
x265 hevc_res_b 320x180 2 "keyint=30:bframes=4" -output_ts_offset 2

# Fragmented copies for MSE. Remuxing drops the alpha layer's parameter sets
# from hvcC, so that one's encoded fragmented.
for f in *.mp4; do
  case $f in *.frag.mp4 | hevc_alpha.mp4) continue ;; esac
  ffmpeg "${q[@]}" -i "$f" -c copy "${frag[@]}" "${f%.mp4}.frag.mp4"
done
ffmpeg "${q[@]}" "${alpha[@]}" "${frag[@]}" hevc_alpha.frag.mp4

# HLS: H.264 in MPEG-2 TS; HEVC in fMP4, split from the fragmented MP4 one GOP
# a segment; and HEVC as ffmpeg's HLS muxer writes it, whose stream-copied
# B-frames get wrong timestamps (a known limit of ordering by timestamp).
mkdir -p hls_h264 hls_hevc hls_hevc2
ffmpeg "${q[@]}" -i h264_bpyr.mp4 -c copy -bsf:v h264_mp4toannexb -f hls -hls_time 1 \
  -hls_list_size 0 -hls_segment_type mpegts hls_h264/index.m3u8
ffmpeg "${q[@]}" -i hevc_open.mp4 -c copy -tag:v hvc1 -f hls -hls_time 1 -hls_list_size 0 \
  -hls_segment_type fmp4 hls_hevc/index.m3u8
python3 - <<'EOF'
import struct
d = open('hevc_open.frag.mp4', 'rb').read()
boxes, i = [], 0
while i < len(d):
    size, kind = struct.unpack('>I4s', d[i:i + 8])
    boxes.append((kind, i, i + size))
    i += size
first = next(j for j, b in enumerate(boxes) if b[0] == b'moof')
open('hls_hevc2/init.mp4', 'wb').write(d[:boxes[first][1]])
playlist = ['#EXTM3U', '#EXT-X-VERSION:7', '#EXT-X-TARGETDURATION:1', '#EXT-X-MEDIA-SEQUENCE:0',
            '#EXT-X-MAP:URI="init.mp4"']
n = 0
for j in range(first, len(boxes) - 1):
    if boxes[j][0] == b'moof':
        open(f'hls_hevc2/seg{n}.m4s', 'wb').write(d[boxes[j][1]:boxes[j + 1][2]])
        playlist += ['#EXTINF:1.000000,', f'seg{n}.m4s']
        n += 1
open('hls_hevc2/index.m3u8', 'w').write('\n'.join(playlist + ['#EXT-X-ENDLIST']) + '\n')
EOF

swiftc -O -o vtref vtref.swift
python3 index.py
