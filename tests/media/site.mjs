// Opens a real site in Fiber over the DevTools protocol and reports what its
// media stack did: decoders chosen, codecs, playback progress, errors.
//   node site.mjs <url> [--h264] [--secs 25] [--click <selector>] [--shot name] [--out Default | --binary path]
// --h264 hides VP9 and AV1 from the page (as the h264ify extension does), so
// sites that prefer them fall back to H.264.
import {spawn} from 'node:child_process';
import {mkdtempSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';

const args = process.argv.slice(2);
const url = args[0];
const flag = n => args.includes(n);
const opt = (n, d) => (args.includes(n) ? args[args.indexOf(n) + 1] : d);
const secs = +opt('--secs', 25);
const port = 9300 + Math.floor(Math.random() * 500);
const profile = mkdtempSync(join(tmpdir(), 'fiber-site-'));
const binary = opt('--binary', fileURLToPath(new URL(`../../chromium/src/out/${opt('--out', 'Default')}/Fiber.app/Contents/MacOS/Fiber`, import.meta.url)));
const proc = spawn(binary, [`--user-data-dir=${profile}`, '--no-first-run', '--no-default-browser-check', '--use-mock-keychain',
  '--autoplay-policy=no-user-gesture-required', `--remote-debugging-port=${port}`, 'about:blank'], {stdio: 'ignore'});
const sleep = ms => new Promise(r => setTimeout(r, ms));

let version;
for (let i = 0; i < 60 && !version; i++) {
  try { version = await (await fetch(`http://127.0.0.1:${port}/json/version`)).json(); } catch { await sleep(250); }
}
const ws = new WebSocket(version.webSocketDebuggerUrl);
ws.addEventListener('close', () => { console.log(JSON.stringify({url, browserGone: true, players: [...players.values()].map(p => ({video: p.props.kVideoDecoderName, errors: p.errors.slice(0, 4)}))})); process.exit(0); });
proc.on('exit', code => { console.log(JSON.stringify({url, browserExited: code})); });
await new Promise(r => ws.addEventListener('open', r, {once: true}));
let nextId = 1;
const pending = new Map(), players = new Map(), consoleErrors = [];
ws.addEventListener('message', e => {
  const m = JSON.parse(e.data);
  if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); return; }
  const p = m.params || {};
  if (m.method == 'Media.playerPropertiesChanged') {
    const s = players.get(p.playerId) || {props: {}, events: [], errors: []};
    for (const {name, value} of p.properties) s.props[name] = value;
    players.set(p.playerId, s);
  } else if (m.method == 'Media.playerErrorsRaised') {
    const s = players.get(p.playerId) || {props: {}, events: [], errors: []};
    for (const err of p.errors) s.errors.push(`${err.errorType} ${err.code}`);
    players.set(p.playerId, s);
  } else if (m.method == 'Media.playerMessagesLogged') {
    const s = players.get(p.playerId) || {props: {}, events: [], errors: []};
    for (const msg of p.messages) if (msg.level == 'error') s.errors.push(msg.message.slice(0, 200));
    players.set(p.playerId, s);
  } else if (m.method == 'Runtime.exceptionThrown') {
    consoleErrors.push(p.exceptionDetails?.exception?.description?.slice(0, 160));
  }
});
const send = (method, params = {}, sessionId) => new Promise(r => {
  const id = nextId++;
  pending.set(id, r);
  ws.send(JSON.stringify({id, method, params, sessionId}));
});

const {result: {targetId}} = await send('Target.createTarget', {url: 'about:blank'});
const {result: {sessionId}} = await send('Target.attachToTarget', {targetId, flatten: true});
const s = (m, p) => send(m, p, sessionId);
await s('Page.enable');
await s('Runtime.enable');
await s('Media.enable');
if (flag('--h264')) {
  await s('Page.addScriptToEvaluateOnNewDocument', {source: `(() => {
    const bad = t => /vp9|vp09|av01|av1|webm/i.test(t || '');
    const its = MediaSource.isTypeSupported.bind(MediaSource);
    MediaSource.isTypeSupported = t => !bad(t) && its(t);
    if (window.ManagedMediaSource) { const m = ManagedMediaSource.isTypeSupported.bind(ManagedMediaSource); ManagedMediaSource.isTypeSupported = t => !bad(t) && m(t); }
    const cpt = HTMLMediaElement.prototype.canPlayType;
    HTMLMediaElement.prototype.canPlayType = function (t) { return bad(t) ? '' : cpt.call(this, t); };
    if (navigator.mediaCapabilities) { const di = navigator.mediaCapabilities.decodingInfo.bind(navigator.mediaCapabilities);
      navigator.mediaCapabilities.decodingInfo = c => bad(c?.video?.contentType) ? Promise.resolve({supported: false, smooth: false, powerEfficient: false}) : di(c); }
  })();`});
}
await s('Page.navigate', {url});

const probe = `(() => { const all = []; const walk = r => { for (const e of r.querySelectorAll('*')) { if (e.tagName == 'VIDEO' || e.tagName == 'AUDIO') all.push(e); if (e.shadowRoot) walk(e.shadowRoot); } }; walk(document); return all.map(v => {
  const q = v.getVideoPlaybackQuality ? v.getVideoPlaybackQuality() : {};
  return {tag: v.tagName, t: +v.currentTime.toFixed(2), paused: v.paused, rs: v.readyState, w: v.videoWidth, h: v.videoHeight,
          decoded: q.totalVideoFrames, dropped: q.droppedVideoFrames, err: v.error && v.error.message, src: (v.currentSrc || '').slice(0, 60)};
}); })()`;
const nudge = `(() => { const c = ${JSON.stringify(opt('--click', ''))}; if (c) document.querySelector(c)?.click();
  const all = []; const walk = r => { for (const e of r.querySelectorAll('*')) { if (e.tagName == 'VIDEO') all.push(e); if (e.shadowRoot) walk(e.shadowRoot); } }; walk(document);
  for (const v of all.slice(0, 2)) { v.muted = true; if (v.paused) v.play().catch(() => {}); } })()`;
let samples = [];
for (let i = 0; i < secs; i += 2) {
  await sleep(2000);
  if (i >= 4 && i % 6 == 4) await s('Runtime.evaluate', {expression: nudge});
  const r = await s('Runtime.evaluate', {expression: probe, returnByValue: true});
  samples.push(r.result?.result?.value || []);
}
const shot = opt('--shot', '');
if (shot) {
  const r = await s('Page.captureScreenshot', {format: 'png'});
  writeFileSync(shot, Buffer.from(r.result.data, 'base64'));
}
const last = samples.at(-1) || [], first = samples.find(x => x.length) || [];
const summary = {
  url,
  media: last.filter(v => v.tag == 'VIDEO' && (v.t > 0 || v.decoded)).slice(0, 4),
  progressed: last.some((v, i) => v.t > 1),
  players: [...players.values()].map(p => ({
    video: p.props.kVideoDecoderName, audio: p.props.kAudioDecoderName,
    videoPlatform: p.props.kIsPlatformVideoDecoder, tracks: (p.props.kVideoTracks || '').slice(0, 160) || undefined,
    audioTracks: (p.props.kAudioTracks || '').slice(0, 160) || undefined,
    errors: p.errors.slice(0, 4),
  })).filter(p => p.video || p.audio || p.errors.length),
  exceptions: consoleErrors.slice(0, 3),
};
console.log(JSON.stringify(summary, null, 1));
ws.close();
proc.kill('SIGTERM');
await sleep(1500);
try { proc.kill('SIGKILL'); } catch {}
rmSync(profile, {recursive: true, force: true});
process.exit(0);
