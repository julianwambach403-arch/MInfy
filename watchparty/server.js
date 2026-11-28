#!/usr/bin/env node
// MInfy Lounge – Server
// Liefert die Web-App aus (HTTPS, nötig für WebXR, Mikrofon und Bildschirm teilen),
// verbindet die Teilnehmer per WebSocket (Räume, Avatare, Chat, Synchronisierung)
// und vermittelt die WebRTC-Verbindungen (Sprache und geteilte Bildschirme laufen direkt
// zwischen den Teilnehmern, nicht über den Server).
'use strict';

const http = require('http');
const https = require('https');
const fs = require('fs');
const path = require('path');
const os = require('os');
const crypto = require('crypto');
const { WebSocketServer } = require('ws');

// ---------- Einstellungen ----------
const args = process.argv.slice(2);
const arg = (name, def) => {
  const hit = args.find((a) => a === `--${name}` || a.startsWith(`--${name}=`));
  if (!hit) return def;
  return hit.includes('=') ? hit.split('=').slice(1).join('=') : true;
};
const USE_HTTPS = !(arg('http', false) || process.env.HTTPS === '0');
const PORT = Number(arg('port', process.env.PORT || (USE_HTTPS ? 8443 : 8080)));
const MAX_ROOM = Number(process.env.MAX_PEERS || 8);
const ALLOW_PROXY = process.env.PROXY !== '0';

// STUN/TURN für WebRTC. Für Freunde hinter strengen Routern ggf. eigenen TURN-Server eintragen.
const ICE_SERVERS = [{ urls: (process.env.STUN_URLS || 'stun:stun.l.google.com:19302,stun:stun1.l.google.com:19302').split(',') }];
if (process.env.TURN_URL) {
  ICE_SERVERS.push({
    urls: process.env.TURN_URL.split(','),
    username: process.env.TURN_USER || '',
    credential: process.env.TURN_PASS || '',
  });
}

const ROOT = __dirname;
const PUBLIC = path.join(ROOT, 'public');
const MOUNTS = [
  ['/vendor/three/', path.join(ROOT, 'node_modules', 'three')],
  ['/vendor/hls/', path.join(ROOT, 'node_modules', 'hls.js', 'dist')],
  ['/', PUBLIC],
];
const MIME = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8', '.json': 'application/json', '.png': 'image/png', '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon', '.webmanifest': 'application/manifest+json', '.map': 'application/json',
};

// ---------- Zertifikat ----------
function localIPs() {
  const ips = [];
  for (const list of Object.values(os.networkInterfaces())) {
    for (const i of list || []) if (i.family === 'IPv4' && !i.internal) ips.push(i.address);
  }
  return ips;
}

function loadCert() {
  const dir = path.join(ROOT, 'certs');
  const certFile = process.env.CERT || path.join(dir, 'cert.pem');
  const keyFile = process.env.KEY || path.join(dir, 'key.pem');
  if (fs.existsSync(certFile) && fs.existsSync(keyFile)) {
    return { cert: fs.readFileSync(certFile), key: fs.readFileSync(keyFile) };
  }
  console.log('[Lounge] Erzeuge selbstsigniertes Zertifikat (einmalig) …');
  const selfsigned = require('selfsigned');
  const altNames = [{ type: 2, value: 'localhost' }, { type: 7, ip: '127.0.0.1' }]
    .concat(localIPs().map((ip) => ({ type: 7, ip })));
  const pems = selfsigned.generate([{ name: 'commonName', value: 'MInfy Lounge' }], {
    days: 3650, keySize: 2048, algorithm: 'sha256',
    extensions: [{ name: 'subjectAltName', altNames }],
  });
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(certFile, pems.cert);
  fs.writeFileSync(keyFile, pems.private);
  return { cert: pems.cert, key: pems.private };
}

// ---------- Räume ----------
/** @type {Map<string, {code:string, peers:Map<string, any>, media:any, focus:string|null}>} */
const rooms = new Map();
const tokens = new Map(); // token -> peer (für den Video-Proxy)

const str = (v, max) => (typeof v === 'string' ? v.slice(0, max) : '');
const num = (v, def = 0) => (typeof v === 'number' && Number.isFinite(v) ? v : def);
const cleanRoom = (v) => str(v, 24).toUpperCase().replace(/[^A-Z0-9-]/g, '');
const cleanColor = (v) => (/^#[0-9a-fA-F]{6}$/.test(v) ? v : '#4fc3f7');

function publicPeer(p) {
  return { id: p.id, name: p.name, color: p.color, micId: p.micId, screenId: p.screenId, screenName: p.screenName,
    relay: p.relay, muted: p.muted, inVR: p.inVR, pose: p.pose };
}

function broadcast(room, msg, except) {
  const data = JSON.stringify(msg);
  for (const p of room.peers.values()) {
    if (p !== except && p.ws.readyState === 1) p.ws.send(data);
  }
}

function sharers(room) {
  return [...room.peers.values()].filter((p) => p.screenId && !p.relay);
}

// Wählt automatisch, was auf der großen Leinwand läuft, wenn die bisherige Quelle verschwindet.
function fixFocus(room) {
  const f = room.focus;
  const valid = (f === 'media' && room.media) || (f && f !== 'media' && room.peers.get(f)?.screenId && !room.peers.get(f).relay);
  if (valid) return false;
  const next = sharers(room)[0];
  room.focus = room.media ? 'media' : next ? next.id : null;
  return room.focus !== f;
}

function setFocus(room, focus) {
  room.focus = focus;
  fixFocus(room);
  broadcast(room, { t: 'focus', focus: room.focus });
}

function handleMedia(room, peer, m) {
  const now = Date.now();
  const cur = room.media;
  const pos = cur ? (cur.playing ? cur.time + (now - cur.updatedAt) / 1000 : cur.time) : 0;
  switch (m.action) {
    case 'load': {
      const kind = ['youtube', 'twitch', 'video'].includes(m.kind) ? m.kind : null;
      const src = str(m.src, 2000);
      if (!kind || !src) return;
      room.media = { kind, src, url: str(m.url, 2000), title: str(m.title, 200), live: !!m.live,
        playing: true, time: Math.max(0, num(m.time)), updatedAt: now, by: peer.name, rev: (cur?.rev || 0) + 1 };
      room.focus = 'media';
      broadcast(room, { t: 'focus', focus: room.focus });
      break;
    }
    case 'play': if (!cur) return; Object.assign(cur, { playing: true, time: m.time != null ? Math.max(0, num(m.time)) : pos, updatedAt: now }); break;
    case 'pause': if (!cur) return; Object.assign(cur, { playing: false, time: m.time != null ? Math.max(0, num(m.time)) : pos, updatedAt: now }); break;
    case 'seek': if (!cur) return; Object.assign(cur, { time: Math.max(0, num(m.time)), updatedAt: now }); break;
    case 'stop': room.media = null; break;
    default: return;
  }
  broadcast(room, { t: 'media', media: room.media, by: peer.name, action: m.action });
  if (fixFocus(room)) broadcast(room, { t: 'focus', focus: room.focus });
}

function onMessage(ws, state, raw) {
  let m;
  try { m = JSON.parse(raw); } catch { return; }
  if (!m || typeof m.t !== 'string') return;
  const peer = state.peer;

  if (m.t === 'ping') { ws.send(JSON.stringify({ t: 'pong', c: m.c, s: Date.now() })); return; }

  if (m.t === 'join') {
    if (peer) return;
    const code = cleanRoom(m.room);
    if (!code) { ws.send(JSON.stringify({ t: 'error', message: 'Ungültiger Raumcode.' })); return; }
    let room = rooms.get(code);
    if (!room) { room = { code, peers: new Map(), media: null, focus: null }; rooms.set(code, room); }
    const humans = [...room.peers.values()].filter((p) => !p.relay).length;
    if (!m.relay && humans >= MAX_ROOM) { ws.send(JSON.stringify({ t: 'error', message: `Der Raum ist voll (max. ${MAX_ROOM}).` })); return; }
    const p = {
      id: crypto.randomBytes(6).toString('hex'), token: crypto.randomBytes(18).toString('hex'), ws, room,
      name: str(m.name, 24).trim() || 'Gast', color: cleanColor(m.color), relay: !!m.relay,
      micId: null, screenId: null, screenName: '', muted: false, inVR: false, pose: null,
    };
    state.peer = p;
    tokens.set(p.token, p);
    ws.send(JSON.stringify({
      t: 'welcome', id: p.id, token: p.token, room: code, iceServers: ICE_SERVERS, proxy: ALLOW_PROXY,
      peers: [...room.peers.values()].map(publicPeer), media: room.media, focus: room.focus, serverTime: Date.now(),
    }));
    room.peers.set(p.id, p);
    broadcast(room, { t: 'peer-join', peer: publicPeer(p) }, p);
    console.log(`[Lounge] ${p.relay ? 'Relais von ' : ''}${p.name} betritt Raum ${code} (${room.peers.size} verbunden)`);
    return;
  }

  if (!peer) return;
  const room = peer.room;

  switch (m.t) {
    case 'pose':
      if (Array.isArray(m.p) && m.p.length <= 32) {
        peer.pose = m.p.map((v) => num(v));
        broadcast(room, { t: 'pose', id: peer.id, p: peer.pose }, peer);
      }
      break;
    case 'signal': {
      const to = room.peers.get(str(m.to, 32));
      if (to && to.ws.readyState === 1) to.ws.send(JSON.stringify({ t: 'signal', from: peer.id, data: m.data }));
      break;
    }
    case 'state': {
      const before = peer.screenId;
      if ('micId' in m) peer.micId = str(m.micId, 100) || null;
      if ('screenId' in m) peer.screenId = str(m.screenId, 100) || null;
      if ('screenName' in m) peer.screenName = str(m.screenName, 60);
      if ('muted' in m) peer.muted = !!m.muted;
      if ('inVR' in m) peer.inVR = !!m.inVR;
      if ('name' in m) peer.name = str(m.name, 24).trim() || peer.name;
      broadcast(room, { t: 'peer-update', peer: publicPeer(peer) }, peer);
      if (!before && peer.screenId && !peer.relay && !room.focus) setFocus(room, peer.id);
      else if (fixFocus(room)) broadcast(room, { t: 'focus', focus: room.focus });
      break;
    }
    case 'focus': {
      const f = m.focus === 'media' ? 'media' : str(m.focus, 32) || null;
      setFocus(room, f);
      break;
    }
    case 'media': handleMedia(room, peer, m); break;
    case 'chat': {
      const text = str(m.text, 300).trim();
      if (text) broadcast(room, { t: 'chat', id: peer.id, name: peer.name, color: peer.color, text });
      break;
    }
    case 'react': {
      const e = str(m.e, 8);
      if (e) broadcast(room, { t: 'react', id: peer.id, e });
      break;
    }
    default: break;
  }
}

function onClose(state) {
  const p = state.peer;
  if (!p) return;
  tokens.delete(p.token);
  const room = p.room;
  room.peers.delete(p.id);
  broadcast(room, { t: 'peer-leave', id: p.id });
  if (fixFocus(room)) broadcast(room, { t: 'focus', focus: room.focus });
  console.log(`[Lounge] ${p.name} verlässt Raum ${room.code} (${room.peers.size} verbunden)`);
  if (room.peers.size === 0) rooms.delete(room.code);
}

// ---------- Video-Proxy ----------
// Manche direkte Video-Links erlauben kein CORS. Dann kann die 3D-Leinwand sie nicht als Textur
// anzeigen. Der Proxy holt das Video über den Server. Nur für Teilnehmer eines Raums.
function isPrivateHost(host) {
  const h = host.replace(/^\[|\]$/g, '').toLowerCase();
  if (h === 'localhost' || h.endsWith('.localhost') || h.endsWith('.local') || h === '0.0.0.0' || h === '::1') return true;
  const m = h.match(/^(\d+)\.(\d+)\.(\d+)\.(\d+)$/);
  if (m) {
    const [a, b] = [Number(m[1]), Number(m[2])];
    return a === 10 || a === 127 || a === 0 || (a === 169 && b === 254) || (a === 172 && b >= 16 && b <= 31) || (a === 192 && b === 168) || (a === 100 && b >= 64 && b <= 127);
  }
  return h.startsWith('fc') || h.startsWith('fd') || h.startsWith('fe80');
}

function proxy(req, res, u) {
  if (!ALLOW_PROXY) { res.writeHead(403).end('Proxy aus'); return; }
  if (!tokens.has(u.searchParams.get('token') || '')) { res.writeHead(403).end('Kein Zugriff'); return; }
  let target;
  try { target = new URL(u.searchParams.get('url') || ''); } catch { res.writeHead(400).end('Ungültige URL'); return; }
  const go = (url, hops) => {
    if (!/^https?:$/.test(url.protocol) || isPrivateHost(url.hostname)) { res.writeHead(400).end('URL nicht erlaubt'); return; }
    const lib = url.protocol === 'https:' ? https : http;
    const headers = { 'user-agent': 'Mozilla/5.0 (MInfy Lounge)', accept: '*/*' };
    if (req.headers.range) headers.range = req.headers.range;
    const up = lib.get(url, { headers, timeout: 15000 }, (r) => {
      if ([301, 302, 303, 307, 308].includes(r.statusCode) && r.headers.location && hops < 4) {
        r.resume();
        go(new URL(r.headers.location, url), hops + 1);
        return;
      }
      const out = { 'access-control-allow-origin': '*', 'cache-control': 'no-store' };
      for (const k of ['content-type', 'content-length', 'content-range', 'accept-ranges']) if (r.headers[k]) out[k] = r.headers[k];
      res.writeHead(r.statusCode || 502, out);
      r.pipe(res);
    });
    up.on('timeout', () => up.destroy(new Error('timeout')));
    up.on('error', () => { if (!res.headersSent) res.writeHead(502); res.end(); });
    req.on('close', () => up.destroy());
  };
  go(target, 0);
}

// ---------- HTTP ----------
function serveStatic(req, res, pathname) {
  for (const [prefix, dir] of MOUNTS) {
    if (!pathname.startsWith(prefix)) continue;
    let rel = decodeURIComponent(pathname.slice(prefix.length));
    if (rel === '' || rel.endsWith('/')) rel += 'index.html';
    const file = path.normalize(path.join(dir, rel));
    if (!file.startsWith(dir + path.sep) && file !== dir) break;
    fs.stat(file, (err, st) => {
      if (err || !st.isFile()) { res.writeHead(404, { 'content-type': 'text/plain; charset=utf-8' }).end('Nicht gefunden'); return; }
      res.writeHead(200, {
        'content-type': MIME[path.extname(file)] || 'application/octet-stream',
        'content-length': st.size,
        'cache-control': prefix === '/' ? 'no-cache' : 'public, max-age=86400',
      });
      if (req.method === 'HEAD') { res.end(); return; }
      fs.createReadStream(file).pipe(res);
    });
    return;
  }
  res.writeHead(404).end();
}

function onRequest(req, res) {
  let u;
  try { u = new URL(req.url, 'http://x'); } catch { res.writeHead(400).end(); return; }
  if (u.pathname === '/proxy') { proxy(req, res, u); return; }
  if (u.pathname === '/health') { res.writeHead(200, { 'content-type': 'application/json' }).end(JSON.stringify({ ok: true, rooms: rooms.size })); return; }
  if (req.method !== 'GET' && req.method !== 'HEAD') { res.writeHead(405).end(); return; }
  serveStatic(req, res, u.pathname);
}

const server = USE_HTTPS ? https.createServer(loadCert(), onRequest) : http.createServer(onRequest);
const wss = new WebSocketServer({ server, path: '/ws', maxPayload: 256 * 1024 });

wss.on('connection', (ws) => {
  const state = { peer: null, alive: true };
  ws.on('pong', () => { state.alive = true; });
  ws.on('message', (data) => onMessage(ws, state, data.toString()));
  ws.on('close', () => onClose(state));
  ws.on('error', () => {});
  ws._state = state;
});

// Tote Verbindungen aufräumen
setInterval(() => {
  for (const ws of wss.clients) {
    if (!ws._state.alive) { ws.terminate(); continue; }
    ws._state.alive = false;
    ws.ping();
  }
}, 15000).unref();

server.listen(PORT, () => {
  const proto = USE_HTTPS ? 'https' : 'http';
  console.log(`\n[Lounge] MInfy Lounge läuft auf Port ${PORT} (${proto.toUpperCase()})`);
  console.log(`  Auf diesem PC:   ${proto}://localhost:${PORT}`);
  for (const ip of localIPs()) console.log(`  Im WLAN (Quest): ${proto}://${ip}:${PORT}`);
  if (USE_HTTPS) console.log('  Hinweis: Das Zertifikat ist selbst erstellt. Beim ersten Öffnen die Warnung mit\n  „Erweitert“ → „Weiter zu …“ bestätigen.');
  console.log('');
});
