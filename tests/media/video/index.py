#!/usr/bin/env python3
"""Indexes each progressive NAME.mp4 here into NAME.json for the test page: its
video samples in decoding order (times in us) with their NAL unit types, its avcC/hvcC,
and each frame's luma SHA-256 from ffmpeg's decode, plus vtref's as 'alt' where it differs."""
import glob, hashlib, json, os, struct, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
VTREF = os.path.join(HERE, 'vtref')


def boxes(data, start, end):
    i = start
    while i + 8 <= end:
        size, kind = struct.unpack('>I4s', data[i:i + 8])
        hdr = 8
        if size == 1:
            size = struct.unpack('>Q', data[i + 8:i + 16])[0]
            hdr = 16
        elif size == 0:
            size = end - i
        yield kind.decode('latin1'), i + hdr, i + size
        i += size


def find(data, start, end, path):
    for kind, s, e in boxes(data, start, end):
        if kind == path[0]:
            if len(path) == 1:
                return s, e
            r = find(data, s, e, path[1:])
            if r:
                return r
    return None


def full(data, s):
    return data[s], s + 4  # version, payload start


def video_trak(data, moov):
    for kind, s, e in boxes(data, *moov):
        if kind != 'trak':
            continue
        hdlr = find(data, s, e, ['mdia', 'hdlr'])
        if data[hdlr[0] + 8:hdlr[0] + 12] == b'vide':
            return s, e


def index(path):
    data = open(path, 'rb').read()
    moov = find(data, 0, len(data), ['moov'])
    trak = video_trak(data, moov)
    mdhd = find(data, *trak, ['mdia', 'mdhd'])
    v, p = full(data, mdhd[0])
    timescale = struct.unpack('>I', data[p + (16 if v else 8):p + (20 if v else 12)])[0]
    stbl = find(data, *trak, ['mdia', 'minf', 'stbl'])

    stsd = find(data, *stbl, ['stsd'])
    entry = next(boxes(data, stsd[0] + 8, stsd[1]))
    fourcc = entry[0]
    width, height = struct.unpack('>HH', data[entry[1] + 24:entry[1] + 28])
    config = None
    for kind, s, e in boxes(data, entry[1] + 78, entry[2]):
        if kind in ('avcC', 'hvcC'):
            config = (kind, data[s:e])
    if fourcc == 'avc1':
        avcc = config[1]
        codec = 'avc1.%02X%02X%02X' % (avcc[1], avcc[2], avcc[3])
        length_size = (avcc[4] & 3) + 1
    else:
        hvcc = config[1]
        profile_idc = hvcc[1] & 0x1f
        tier = 'H' if hvcc[1] & 0x20 else 'L'
        level = hvcc[12]
        compat = struct.unpack('>I', hvcc[2:6])[0]
        compat_rev = int(f'{compat:032b}'[::-1], 2)
        codec = f'hvc1.{profile_idc}.{compat_rev:X}.{tier}{level}.B0'
        length_size = (hvcc[21] & 3) + 1

    sizes = []
    v, p = full(data, find(data, *stbl, ['stsz'])[0])
    fixed, count = struct.unpack('>II', data[p:p + 8])
    sizes = [fixed] * count if fixed else list(struct.unpack(f'>{count}I', data[p + 8:p + 8 + 4 * count]))
    co = find(data, *stbl, ['stco'])
    if co:
        v, p = full(data, co[0])
        n = struct.unpack('>I', data[p:p + 4])[0]
        chunks = list(struct.unpack(f'>{n}I', data[p + 4:p + 4 + 4 * n]))
    else:
        v, p = full(data, find(data, *stbl, ['co64'])[0])
        n = struct.unpack('>I', data[p:p + 4])[0]
        chunks = list(struct.unpack(f'>{n}Q', data[p + 4:p + 4 + 8 * n]))
    v, p = full(data, find(data, *stbl, ['stsc'])[0])
    n = struct.unpack('>I', data[p:p + 4])[0]
    stsc = [struct.unpack('>III', data[p + 4 + 12 * i:p + 16 + 12 * i]) for i in range(n)]
    offsets = []
    for ci, chunk_off in enumerate(chunks):
        per = next(spc for first, spc, _ in reversed(stsc) if first <= ci + 1)
        off = chunk_off
        for _ in range(per):
            offsets.append(off)
            off += sizes[len(offsets) - 1]
    v, p = full(data, find(data, *stbl, ['stts'])[0])
    n = struct.unpack('>I', data[p:p + 4])[0]
    dts, t = [], 0
    for i in range(n):
        c, d = struct.unpack('>II', data[p + 4 + 8 * i:p + 12 + 8 * i])
        for _ in range(c):
            dts.append(t)
            t += d
    ctts = [0] * count
    cb = find(data, *stbl, ['ctts'])
    if cb:
        v, p = full(data, cb[0])
        n = struct.unpack('>I', data[p:p + 4])[0]
        k = 0
        for i in range(n):
            c, o = struct.unpack('>I' + ('i' if v else 'I'), data[p + 4 + 8 * i:p + 12 + 8 * i])
            for _ in range(c):
                ctts[k] = o
                k += 1
    sb = find(data, *stbl, ['stss'])
    keys = set(range(count))
    if sb:
        v, p = full(data, sb[0])
        n = struct.unpack('>I', data[p:p + 4])[0]
        keys = {x - 1 for x in struct.unpack(f'>{n}I', data[p + 4:p + 4 + 4 * n])}
    # Edit list: the first entry's media_time shifts presentation back.
    shift = 0
    el = find(data, *trak, ['edts', 'elst'])
    if el:
        v, p = full(data, el[0])
        n = struct.unpack('>I', data[p:p + 4])[0]
        for i in range(n):
            if v:
                dur, mt = struct.unpack('>Qq', data[p + 4 + 20 * i:p + 20 + 20 * i])
            else:
                dur, mt = struct.unpack('>Ii', data[p + 4 + 12 * i:p + 12 + 12 * i])
            if mt >= 0:
                shift = mt
                break

    us = lambda x: round(x * 1_000_000 / timescale)
    samples = []
    for i in range(count):
        nals = []
        j, end = offsets[i], offsets[i] + sizes[i]
        while j + length_size <= end:
            n = int.from_bytes(data[j:j + length_size], 'big')
            h = data[j + length_size]
            if fourcc == 'avc1':
                t = h & 0x1f
                if t == 6 and data[j + length_size + 1] == 6:
                    t = 'sei-recovery'
            else:
                t = (h >> 1) & 0x3f
                layer = ((h & 1) << 5) | (data[j + length_size + 1] >> 3)
                if layer:
                    t = f'{t}@{layer}'
            nals.append(t)
            j += length_size + n
        samples.append({'off': offsets[i], 'size': sizes[i], 'dts': us(dts[i]),
                        'cts': us(dts[i] + ctts[i] - shift), 'key': i in keys, 'nals': nals})

    ref = reference(path)
    alternatives(path, ref)
    return {'file': os.path.basename(path), 'codec': codec, 'width': width, 'height': height,
            'lengthSize': length_size, 'description': config[1].hex(), 'samples': samples,
            'ref': ref}


def reference(path):
    """ffmpeg's decode: each frame's time and luma hash, in presentation order."""
    times = subprocess.run(['ffprobe', '-v', 'error', '-select_streams', 'v:0', '-show_entries',
                            'frame=pts_time', '-of', 'csv=p=0', path],
                           capture_output=True, text=True, check=True).stdout
    times = [l.split(',')[0] for l in times.splitlines() if l.strip()]
    info = subprocess.run(['ffprobe', '-v', 'error', '-select_streams', 'v:0', '-show_entries',
                           'stream=width,height,pix_fmt', '-of', 'json', path],
                          capture_output=True, text=True, check=True).stdout
    st = json.loads(info)['streams'][0]
    deep = '10' in st['pix_fmt']
    fmt = 'gray10le' if deep else 'gray'
    raw = subprocess.run(['ffmpeg', '-v', 'error', '-i', path, '-map', '0:v:0', '-fps_mode', 'passthrough', '-vf',
                          f'extractplanes=y,format={fmt}', '-f', 'rawvideo', '-'],
                         capture_output=True, check=True).stdout
    w, h = st['width'], st['height']
    size = w * h * (2 if deep else 1)
    n = len(raw) // size
    assert n == len(times), (path, n, len(times))
    return {'bitDepth': 10 if deep else 8,
            'frames': [{'t': round(float(times[i]) * 1_000_000),
                        'h': hashlib.sha256(raw[i * size:(i + 1) * size]).hexdigest()}
                       for i in range(n)]}


def alternatives(path, ref):
    """Fiber's frames are VideoToolbox's, and it and ffmpeg don't agree bit for
    bit on everything (interlaced H.264): where they differ, VideoToolbox's
    hash too. 8-bit only; vtref doesn't read 10-bit frames."""
    if ref['bitDepth'] != 8 or not os.path.exists(VTREF):
        return
    hashes = subprocess.run([VTREF, path], capture_output=True, text=True, check=True).stdout.split()
    assert len(hashes) == len(ref['frames']), (path, len(hashes), len(ref['frames']))
    for frame, h in zip(ref['frames'], hashes):
        if h != frame['h']:
            frame['alt'] = h


for f in sorted(glob.glob(os.path.join(HERE, '*.mp4'))):
    if f.endswith('.frag.mp4'):
        continue
    j = index(f)
    json.dump(j, open(f[:-4] + '.json', 'w'))
    keys = sum(s['key'] for s in j['samples'])
    ts = sorted(s['cts'] for s in j['samples'])
    alts = sum('alt' in f for f in j['ref']['frames'])
    print(f"{j['file']:22} {j['codec']:24} {len(j['samples'])} samples, {keys} key, "
          f"ref {len(j['ref']['frames'])} frames, cts0 {ts[0]} ref0 {j['ref']['frames'][0]['t']}"
          f"{alts and f', VideoToolbox differs on {alts}' or ''}")
