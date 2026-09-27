# Audio track index for WebCodecs: sample offsets/sizes/pts (us) and the AudioSpecificConfig.
import struct, json
def boxes(d, s, e):
    i = s
    while i + 8 <= e:
        size, k = struct.unpack('>I4s', d[i:i + 8])
        if size == 1: size = struct.unpack('>Q', d[i + 8:i + 16])[0]
        yield k.decode('latin1'), i + 8, i + size
        i += size
def find(d, s, e, path):
    for k, a, b in boxes(d, s, e):
        if k == path[0]:
            if len(path) == 1: return a, b
            r = find(d, a, b, path[1:])
            if r: return r
def full(d, s): return d[s], s + 4
def audio_trak(d, moov):
    for k, s, e in boxes(d, *moov):
        if k == 'trak':
            h = find(d, s, e, ['mdia', 'hdlr'])
            if d[h[0] + 8:h[0] + 12] == b'soun': return s, e
def asc_from_esds(e):
    for i in range(len(e) - 2):
        if e[i] == 0x05:
            j = i + 1; n = 0
            for _ in range(4):
                b = e[j]; j += 1; n = (n << 7) | (b & 0x7f)
                if not b & 0x80: break
            if 0 < n <= 16: return e[j:j + n]
out = {}
for name in ['lc2', 'he2', 'hev2', 'lc6']:
    d = open(name + '.m4a', 'rb').read()
    moov = find(d, 0, len(d), ['moov']); trak = audio_trak(d, moov)
    v, p = full(d, find(d, *trak, ['mdia', 'mdhd'])[0])
    ts = struct.unpack('>I', d[p + (16 if v else 8):p + (20 if v else 12)])[0]
    stbl = find(d, *trak, ['mdia', 'minf', 'stbl'])
    stsd = find(d, *stbl, ['stsd']); entry = next(boxes(d, stsd[0] + 8, stsd[1]))
    esds = find(d, entry[1] + 28, entry[2], ['esds'])
    asc = asc_from_esds(d[esds[0] + 4:esds[1]])
    v, p = full(d, find(d, *stbl, ['stsz'])[0]); fixed, count = struct.unpack('>II', d[p:p + 8])
    sizes = [fixed] * count if fixed else list(struct.unpack(f'>{count}I', d[p + 8:p + 8 + 4 * count]))
    v, p = full(d, find(d, *stbl, ['stco'])[0]); n = struct.unpack('>I', d[p:p + 4])[0]
    chunks = list(struct.unpack(f'>{n}I', d[p + 4:p + 4 + 4 * n]))
    v, p = full(d, find(d, *stbl, ['stsc'])[0]); n = struct.unpack('>I', d[p:p + 4])[0]
    stsc = [struct.unpack('>III', d[p + 4 + 12 * i:p + 16 + 12 * i]) for i in range(n)]
    offs = []
    for ci, co in enumerate(chunks):
        per = next(spc for first, spc, _ in reversed(stsc) if first <= ci + 1)
        o = co
        for _ in range(per): offs.append(o); o += sizes[len(offs) - 1]
    v, p = full(d, find(d, *stbl, ['stts'])[0]); n = struct.unpack('>I', d[p:p + 4])[0]; t = 0; pts = []
    for i in range(n):
        c, du = struct.unpack('>II', d[p + 4 + 8 * i:p + 12 + 8 * i])
        for _ in range(c): pts.append(t); t += du
    out[name] = {'file': name + '.m4a', 'asc': asc.hex(), 'samples': [{'off': offs[i], 'size': sizes[i], 'pts': round(pts[i] * 1e6 / ts)} for i in range(count)]}
json.dump(out, open('aindex.json', 'w'))
print({k: (len(v['samples']), v['asc']) for k, v in out.items()})
