#!/usr/bin/env python3
"""Serves this directory, opens a page in Fiber with a fresh profile, and waits
for the page to POST its results to /report (prints them, and exits 1 if they
list failures). POST /log lines are printed as they come.

    runner.py video/video.html [--timeout 120] [--out Default] [--keep-profile] [-- flags...]
"""
import argparse, http.server, json, os, re, shutil, signal, subprocess, sys, tempfile, threading, time

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.normpath(os.path.join(HERE, '..', '..', 'chromium', 'src'))
TYPES = {'.m3u8': 'application/vnd.apple.mpegurl', '.ts': 'video/mp2t',
         '.aac': 'audio/aac', '.m4a': 'audio/mp4', '.mp4': 'video/mp4',
         '.264': 'application/octet-stream', '.265': 'application/octet-stream',
         '.json': 'application/json', '.js': 'text/javascript'}
done = threading.Event()
result = {}


class H(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **k):
        super().__init__(*a, directory=HERE, **k)

    def guess_type(self, path):
        return TYPES.get(os.path.splitext(path)[1]) or super().guess_type(path)

    def end_headers(self):
        self.send_header('Cache-Control', 'no-store')
        super().end_headers()

    def do_POST(self):
        body = self.rfile.read(int(self.headers['Content-Length']))
        self.send_response(204)
        self.end_headers()
        if self.path == '/log':
            print('  page:', body.decode(), flush=True)
        elif self.path == '/report':
            result['body'] = body.decode()
            done.set()

    def send_head(self):
        rng = self.headers.get('Range')
        path = self.translate_path(self.path.split('?')[0])
        if not rng or not os.path.isfile(path):
            return super().send_head()
        size = os.path.getsize(path)
        m = re.match(r'bytes=(\d*)-(\d*)', rng)
        start = int(m.group(1) or 0)
        end = min(int(m.group(2)) if m.group(2) else size - 1, size - 1)
        f = open(path, 'rb')
        f.seek(start)
        self.send_response(206)
        self.send_header('Content-Type', self.guess_type(path))
        self.send_header('Content-Range', f'bytes {start}-{end}/{size}')
        self.send_header('Content-Length', str(end - start + 1))
        self.send_header('Accept-Ranges', 'bytes')
        self.end_headers()
        return _Limited(f, end - start + 1)

    def log_message(self, *a):
        pass


class _Limited:
    def __init__(self, f, n):
        self.f, self.n = f, n

    def read(self, k=-1):
        k = self.n if k < 0 else min(k, self.n)
        data = self.f.read(k)
        self.n -= len(data)
        return data

    def close(self):
        self.f.close()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('page')
    ap.add_argument('--timeout', type=float, default=120)
    ap.add_argument('--out', default='Default')
    ap.add_argument('--keep-profile', action='store_true')
    ap.add_argument('--log', default=os.path.join(HERE, 'fiber.log'))
    ap.add_argument('flags', nargs='*')
    args = ap.parse_args()

    srv = http.server.ThreadingHTTPServer(('127.0.0.1', 0), H)
    port = srv.server_address[1]
    threading.Thread(target=srv.serve_forever, daemon=True).start()

    profile = os.path.join(HERE, 'profile') if args.keep_profile else tempfile.mkdtemp(prefix='fiber-profile-')
    binary = os.path.join(SRC, 'out', args.out, 'Fiber.app', 'Contents', 'MacOS', 'Fiber')
    url = f'http://127.0.0.1:{port}/{args.page}'
    cmd = [binary, f'--user-data-dir={profile}', '--no-first-run', '--no-default-browser-check',
           '--use-mock-keychain', '--autoplay-policy=no-user-gesture-required',
           '--enable-logging=stderr', *args.flags, url]
    log = open(args.log, 'w')
    proc = subprocess.Popen(cmd, stdout=log, stderr=subprocess.STDOUT)
    t0 = time.time()
    ok = done.wait(args.timeout)
    crashed = proc.poll()
    if proc.poll() is None:
        proc.send_signal(signal.SIGTERM)
        try:
            proc.wait(10)
        except subprocess.TimeoutExpired:
            proc.kill()
    if not args.keep_profile:
        shutil.rmtree(profile, ignore_errors=True)
    if ok:
        print(result['body'])
        if json.loads(result['body']).get('failed'):
            sys.exit(1)
    else:
        print(json.dumps({'runner': 'timeout' if crashed is None else f'browser exited {crashed}',
                          'seconds': round(time.time() - t0)}))
        sys.exit(1)


main()
