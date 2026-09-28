#!/usr/bin/env bash
# Generates the audio test files (tests/media/README.md): AAC encoded by Apple
# and ffmpeg, and Apple's decodes of it as references (ref_NAME.f32, refs.json).
# Needs macOS's afconvert, and ffmpeg with libx264, libmp3lame and libopus.
set -euo pipefail
cd "$(dirname "$0")"
q=(-hide_banner -loglevel error -y)
sine() { echo "sine=frequency=$1:sample_rate=$2:duration=$3"; }

# Sources: tones, one a channel, so a swapped channel shows.
ffmpeg "${q[@]}" -f lavfi -i "$(sine 440 44100 3)" src1.wav
ffmpeg "${q[@]}" -f lavfi -i "$(sine 440 44100 3)" -f lavfi -i "$(sine 660 44100 3)" \
  -filter_complex "[0][1]amerge=inputs=2" -ac 2 src2.wav
six=()
for f in 440 550 660 110 770 880; do six+=(-f lavfi -i "$(sine $f 48000 3)"); done
ffmpeg "${q[@]}" "${six[@]}" \
  -filter_complex "[0][1][2][3][4][5]amerge=inputs=6,aformat=channel_layouts=5.1" src6.wav
ffmpeg "${q[@]}" -f lavfi -i "$(sine 440 44100 180)" -f lavfi -i "$(sine 660 44100 180)" \
  -filter_complex "[0][1]amerge=inputs=2" -ac 2 long.wav
# A 15 kHz tone, which HE-AAC at 64 kb/s carries only in its SBR band.
ffmpeg "${q[@]}" -f lavfi -i "$(sine 15000 44100 3)" -f lavfi -i "$(sine 15000 44100 3)" \
  -filter_complex "[0][1]amerge=inputs=2" -ac 2 hf.wav

# AAC in MP4: LC mono, stereo and 5.1, HE-AAC mono and stereo, HE-AAC v2,
# AAC-LD and AAC-ELD by Apple; LC stereo and 5.1 by ffmpeg; 3 minutes of LC.
for spec in "lc1 aac src1" "lc2 aac src2" "he1 aach src1" "he2 aach src2" \
            "hev2 aacp src2" "ld2 aacl src2" "eld2 aace src2" "long aac long"; do
  set -- $spec
  afconvert -f m4af -d "$2" "$3.wav" "$1.m4a"
done
afconvert -f m4af -d aac -l MPEG_5_1_D src6.wav lc6.m4a
ffmpeg "${q[@]}" -i src2.wav -c:a aac -b:a 128k ff_lc2.m4a
ffmpeg "${q[@]}" -i src6.wav -c:a aac -b:a 256k ff_lc6.m4a
afconvert -f m4af -d aach -b 64000 hf.wav hf_he.m4a
ffmpeg "${q[@]}" -i hf_he.m4a -c copy -movflags frag_keyframe+empty_moov+default_base_moof hf_he.frag.mp4

# AAC with video; ADTS (lc2.aac remuxed by ffmpeg, the rest written by
# Apple, whose headers say AAC-LC for HE-AAC as all ADTS does); HLS in
# MPEG-2 TS, with the playlist's codecs saying HE-AAC.
ffmpeg "${q[@]}" -f lavfi -i testsrc2=size=320x180:rate=30:duration=3 -i lc2.m4a \
  -map 0:v -map 1:a -c:v libx264 -c:a copy av.mp4
ffmpeg "${q[@]}" -i lc2.m4a -c:a copy -f adts lc2.aac
afconvert -f adts -d aac src2.wav lc2b.aac
afconvert -f adts -d aach src2.wav he2.aac
afconvert -f adts -d aacp src2.wav hev2.aac
afconvert -f adts -d aach -b 64000 hf.wav hf_he.aac
for spec in "hls_he he2.aac" "hls_hf hf_he.aac"; do
  set -- $spec
  mkdir -p "$1"
  ffmpeg "${q[@]}" -i "$2" -c copy -f hls -hls_time 1 -hls_list_size 0 -hls_segment_type mpegts "$1/media.m3u8"
  printf '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=64000,CODECS="mp4a.40.5"\nmedia.m3u8\n' > "$1/master.m3u8"
done

# Other codecs, which should be as in Chromium.
ffmpeg "${q[@]}" -i src2.wav -c:a libmp3lame -b:a 128k s.mp3
ffmpeg "${q[@]}" -i src2.wav -c:a libopus -b:a 96k s.opus
ffmpeg "${q[@]}" -i src2.wav -c:a flac s.flac

# References: Apple's decodes, as raw float32 in Chromium's channel order
# (AAC's 5.1 is C L R Ls Rs LFE; Chromium's L R C LFE Ls Rs).
refs=(lc1 lc2 lc6 he1 he2 hev2 ld2 eld2 ff_lc2 ff_lc6 long)
for f in "${refs[@]}"; do afconvert -f WAVE -d LEF32 "$f.m4a" "ref_$f.wav"; done
python3 - "${refs[@]}" <<'EOF'
import array, json, struct, sys
info = {}
for name in sys.argv[1:]:
    d = open(f'ref_{name}.wav', 'rb').read()
    i = 12
    while i < len(d):
        kind, size = d[i:i + 4], struct.unpack('<I', d[i + 4:i + 8])[0]
        if kind == b'fmt ': channels, rate = struct.unpack('<HI', d[i + 10:i + 16])
        if kind == b'data': data = array.array('f', d[i + 8:i + 8 + size])
        i += 8 + size + (size & 1)
    if channels == 6:
        order = [1, 2, 0, 5, 3, 4]
        data = array.array('f', (data[f + order[c]] for f in range(0, len(data), 6) for c in range(6)))
    open(f'ref_{name}.f32', 'wb').write(data.tobytes())
    info[name] = {'channels': channels, 'rate': rate, 'frames': len(data) // channels}
json.dump(info, open('refs.json', 'w'), indent=1)

# hf_he.aac's ADTS frames, with the AudioSpecificConfig its headers imply.
d = open('hf_he.aac', 'rb').read()
frames, i, header = [], 0, None
while i + 7 < len(d):
    if d[i] != 0xff or (d[i + 1] & 0xf6) != 0xf0:
        i += 1
        continue
    n = ((d[i + 3] & 3) << 11) | (d[i + 4] << 3) | (d[i + 5] >> 5)
    h = 7 if d[i + 1] & 1 else 9
    header = header or d[i:i + 7]
    frames.append((i + h, n - h))
    i += n
profile, sfi = (header[2] >> 6) + 1, (header[2] >> 2) & 15
channels = ((header[2] & 1) << 2) | (header[3] >> 6)
rates = [96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050, 16000, 12000, 11025, 8000]
json.dump({'file': 'hf_he.aac', 'asc': ((profile << 11) | (sfi << 7) | (channels << 3)).to_bytes(2, 'big').hex(),
           'rate': rates[sfi], 'channels': channels, 'frames': frames}, open('hf_adts.json', 'w'))
EOF
rm -f ref_*.wav
python3 aindex.py
