#!/usr/bin/env bash
# Encodes a render as AV1 in WebM at the best quality that fits in `limit`
# bytes (GitHub takes video uploads up to 10 MB on a free plan): the lowest
# CRF whose file fits, found by bisection.
# Usage: encode.sh render.mp4 out.webm [limit]
set -euo pipefail
in="$1"
out="$2"
limit="${3:-10000000}"

if ! ffmpeg -hide_banner -encoders 2>/dev/null | grep -q libsvtav1; then
  echo "error: needs ffmpeg with SVT-AV1 (brew install ffmpeg)" >&2
  exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

encode() {
  SVT_LOG=1 ffmpeg -v error -y -i "$in" -c:v libsvtav1 -preset 4 -crf "$1" -pix_fmt yuv420p -an \
    "$tmp/$1.webm"
  stat -f %z "$tmp/$1.webm"
}

low=10
high=55
best=
while ((low <= high)); do
  crf=$(((low + high) / 2))
  size=$(encode "$crf")
  echo "CRF $crf: $size bytes"
  if ((size <= limit)); then
    best=$crf
    high=$((crf - 1))
  else
    low=$((crf + 1))
  fi
done
if [[ -z $best ]]; then
  echo "error: nothing fits in $limit bytes" >&2
  exit 1
fi
mv "$tmp/$best.webm" "$out"
echo "$out: CRF $best, $(stat -f %z "$out") bytes"
