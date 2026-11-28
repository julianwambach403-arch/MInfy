// Gemeinsam schauen: YouTube, Twitch und direkte Video-Links (mp4, webm, m3u8).
// Der Server speichert, was läuft und an welcher Stelle. Jeder Teilnehmer spielt es selbst ab
// und gleicht sich laufend mit der Serverzeit ab.
import { Emitter } from './util.js';

export function parseMediaUrl(input) {
  const raw = String(input || '').trim();
  if (!raw) return null;
  let u;
  try { u = new URL(/^https?:\/\//i.test(raw) ? raw : `https://${raw}`); } catch { return null; }
  const host = u.hostname.replace(/^(www\.|m\.|music\.)/, '');
  const startParam = u.searchParams.get('t') || u.searchParams.get('start') || '';
  const start = parseTimeParam(startParam);

  if (host === 'youtu.be') {
    const id = u.pathname.slice(1).split('/')[0];
    if (id) return { kind: 'youtube', src: id, url: raw, time: start, title: 'YouTube' };
  }
  if (host === 'youtube.com' || host === 'youtube-nocookie.com') {
    let id = u.searchParams.get('v');
    const m = u.pathname.match(/^\/(shorts|live|embed|v)\/([\w-]{6,})/);
    if (!id && m) id = m[2];
    if (id) return { kind: 'youtube', src: id, url: raw, time: start, title: 'YouTube', live: m?.[1] === 'live' };
  }
  if (host === 'twitch.tv' || host === 'player.twitch.tv') {
    const vod = u.pathname.match(/^\/videos\/(\d+)/) || (u.searchParams.get('video') && [0, u.searchParams.get('video').replace(/^v/, '')]);
    if (vod) return { kind: 'twitch', src: `video:${vod[1]}`, url: raw, time: start, title: `Twitch-Video ${vod[1]}` };
    const channel = u.searchParams.get('channel') || u.pathname.split('/').filter(Boolean)[0];
    if (channel && /^\w{2,40}$/.test(channel)) return { kind: 'twitch', src: `channel:${channel.toLowerCase()}`, url: raw, time: 0, live: true, title: `Twitch: ${channel}` };
  }
  if (/^https?:$/.test(u.protocol)) {
    const name = decodeURIComponent(u.pathname.split('/').pop() || u.hostname);
    return { kind: 'video', src: u.href, url: raw, time: start, title: name.slice(0, 80) };
  }
  return null;
}

function parseTimeParam(t) {
  if (!t) return 0;
  if (/^\d+$/.test(t)) return Number(t);
  const m = t.match(/(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?/);
  return m ? (Number(m[1] || 0) * 3600 + Number(m[2] || 0) * 60 + Number(m[3] || 0)) : 0;
}

const scripts = {};
function loadScript(src, check) {
  if (check()) return Promise.resolve();
  if (!scripts[src]) {
    scripts[src] = new Promise((resolve, reject) => {
      const s = document.createElement('script');
      s.src = src;
      s.onload = () => resolve();
      s.onerror = () => { delete scripts[src]; reject(new Error(`Konnte ${src} nicht laden`)); };
      document.head.appendChild(s);
    });
  }
  return scripts[src];
}

let ytReady;
function loadYouTube() {
  if (window.YT?.Player) return Promise.resolve(window.YT);
  if (!ytReady) {
    ytReady = new Promise((resolve, reject) => {
      const prev = window.onYouTubeIframeAPIReady;
      window.onYouTubeIframeAPIReady = () => { prev?.(); resolve(window.YT); };
      loadScript('https://www.youtube.com/iframe_api', () => false).catch((e) => { ytReady = null; reject(e); });
    });
  }
  return ytReady;
}

// ---------- Abspieler ----------
class YouTubeBackend extends Emitter {
  constructor(host) { super(); this.host = host; this.kind = 'youtube'; this.ready = false; this.state = -1; }
  async load(id, start, autoplay) {
    const YT = await loadYouTube();
    const div = document.createElement('div');
    this.host.appendChild(div);
    this.player = new YT.Player(div, {
      width: '100%', height: '100%', videoId: id,
      playerVars: { autoplay: autoplay ? 1 : 0, start: Math.floor(start), playsinline: 1, rel: 0, modestbranding: 1, origin: location.origin },
      events: {
        onReady: () => {
          this.ready = true;
          const d = this.player.getVideoData?.() || {};
          if (d.title) this.emit('title', d.title);
          this.live = !!d.isLive;
          this.emit('ready');
        },
        onStateChange: (e) => { this.state = e.data; this.emit('statechange'); },
        onError: (e) => this.emit('error', `YouTube-Fehler ${e.data} (Video evtl. nicht einbettbar)`),
      },
    });
  }
  play() { this.player?.playVideo?.(); }
  pause() { this.player?.pauseVideo?.(); }
  seek(t) { this.player?.seekTo?.(t, true); }
  getTime() { return this.player?.getCurrentTime?.() || 0; }
  getDuration() { return this.player?.getDuration?.() || 0; }
  isPaused() { return this.state !== 1 && this.state !== 3; }
  isStalled() { return this.state === -1 || this.state === 5; }
  setVolume(v) { this.player?.setVolume?.(Math.round(v * 100)); }
  setMuted(m) { if (m) this.player?.mute?.(); else this.player?.unMute?.(); }
  isMuted() { return !!this.player?.isMuted?.(); }
  destroy() { try { this.player?.destroy(); } catch { /* egal */ } this.host.innerHTML = ''; }
}

class TwitchBackend extends Emitter {
  constructor(host) { super(); this.host = host; this.kind = 'twitch'; this.ready = false; }
  async load(src, start, autoplay) {
    await loadScript('https://player.twitch.tv/js/embed/v1.js', () => !!window.Twitch?.Player);
    const id = `twitch-${Math.random().toString(36).slice(2)}`;
    const div = document.createElement('div');
    div.id = id;
    div.style.cssText = 'width:100%;height:100%';
    this.host.appendChild(div);
    const [type, value] = src.split(':');
    this.live = type === 'channel';
    const opts = { width: '100%', height: '100%', parent: [location.hostname], autoplay: !!autoplay, muted: false };
    if (this.live) opts.channel = value; else { opts.video = value; if (start > 1) opts.time = `${Math.floor(start)}s`; }
    this.player = new window.Twitch.Player(id, opts);
    this.player.addEventListener(window.Twitch.Player.READY, () => { this.ready = true; this.emit('ready'); });
    this.player.addEventListener(window.Twitch.Player.PLAYING, () => this.emit('statechange'));
    this.player.addEventListener(window.Twitch.Player.PAUSE, () => this.emit('statechange'));
  }
  play() { this.player?.play(); }
  pause() { this.player?.pause(); }
  seek(t) { if (!this.live) this.player?.seek(t); }
  getTime() { return this.player?.getCurrentTime?.() || 0; }
  getDuration() { return this.live ? 0 : this.player?.getDuration?.() || 0; }
  isPaused() { return !!this.player?.isPaused?.(); }
  isStalled() { return false; }
  setVolume(v) { this.player?.setVolume?.(v); }
  setMuted(m) { this.player?.setMuted?.(m); }
  isMuted() { return !!this.player?.getMuted?.(); }
  destroy() { this.host.innerHTML = ''; }
}

class VideoBackend extends Emitter {
  constructor(proxyUrl) {
    super();
    this.kind = 'video';
    this.proxyUrl = proxyUrl;
    this.ready = false;
    const v = document.createElement('video');
    v.playsInline = true;
    v.crossOrigin = 'anonymous';
    v.preload = 'auto';
    v.addEventListener('loadedmetadata', () => { this.ready = true; this.emit('ready'); });
    v.addEventListener('play', () => this.emit('statechange'));
    v.addEventListener('pause', () => this.emit('statechange'));
    v.addEventListener('error', () => this._fail());
    this.video = v;
  }
  async load(url, start) {
    this.url = url;
    this.start = start;
    this.viaProxy = false;
    await this._open(url);
  }
  async _open(url) {
    const v = this.video;
    this.hls?.destroy();
    this.hls = null;
    const isHls = /\.m3u8(\?|$)/i.test(this.url);
    if (isHls && !v.canPlayType('application/vnd.apple.mpegurl')) {
      const { default: Hls } = await import('/vendor/hls/hls.mjs');
      if (Hls.isSupported()) {
        const proxy = this.viaProxy ? this.proxyUrl : null;
        this.hls = new Hls({ xhrSetup: proxy ? (xhr, u) => xhr.open('GET', proxy(u), true) : undefined });
        this.hls.on(Hls.Events.ERROR, (_e, d) => { if (d.fatal) this._fail(); });
        this.hls.loadSource(this.url);
        this.hls.attachMedia(v);
        if (this.start) v.currentTime = this.start;
        return;
      }
    }
    v.src = this.viaProxy && !isHls ? this.proxyUrl(url) : url;
    if (this.start) v.currentTime = this.start;
  }
  _fail() {
    if (!this.viaProxy && this.proxyUrl) {
      this.viaProxy = true;
      console.info('Video ohne CORS, versuche es über den Server-Proxy');
      this._open(this.url);
      return;
    }
    this.emit('error', 'Das Video lässt sich nicht abspielen (Link prüfen, es muss eine direkte Video-Datei sein).');
  }
  play() {
    const v = this.video;
    return v.play().catch((e) => {
      if (e.name === 'NotAllowedError') {
        v.muted = true;
        this.emit('autoplay-muted');
        return v.play().catch(() => {});
      }
      return undefined;
    });
  }
  pause() { this.video.pause(); }
  seek(t) { try { this.video.currentTime = t; } catch { /* noch nicht bereit */ } }
  getTime() { return this.video.currentTime || 0; }
  getDuration() { return Number.isFinite(this.video.duration) ? this.video.duration : 0; }
  isPaused() { return this.video.paused; }
  isStalled() { return false; }
  setVolume(v) { this.video.volume = v; }
  setMuted(m) { this.video.muted = m; }
  isMuted() { return this.video.muted; }
  destroy() { this.hls?.destroy(); this.video.pause(); this.video.removeAttribute('src'); this.video.load(); }
}

// ---------- Steuerung + Synchronisierung ----------
export class MediaController extends Emitter {
  constructor({ host, net }) {
    super();
    this.host = host; // DOM-Element (1280×720) für YouTube/Twitch-Iframes
    this.net = net;
    this.state = null;
    this.backend = null;
    this.volume = 0.8;
    this.localMuted = false; // z. B. in VR, wenn das Relais den Ton liefert
    this.title = '';
    this._timer = setInterval(() => this.sync(), 1000);
  }

  proxyUrl = (u) => `/proxy?token=${encodeURIComponent(this.net.token)}&url=${encodeURIComponent(u)}`;

  expected() {
    const s = this.state;
    if (!s) return 0;
    return s.playing ? s.time + (this.net.serverNow() - s.updatedAt) / 1000 : s.time;
  }

  get live() { return !!(this.state?.live || this.backend?.live); }

  apply(media) {
    const prev = this.state;
    this.state = media;
    if (!media) {
      this._destroy();
      this.emit('change', null);
      return;
    }
    if (!prev || prev.rev !== media.rev || !this.backend) {
      this._destroy();
      this.title = media.title || '';
      const b = media.kind === 'youtube' ? new YouTubeBackend(this.host)
        : media.kind === 'twitch' ? new TwitchBackend(this.host)
          : new VideoBackend(this.proxyUrl);
      this.backend = b;
      b.on('ready', () => { this._applyVolume(); this.sync(true); this.emit('update'); });
      b.on('statechange', () => this.emit('update'));
      b.on('title', (t) => { this.title = t; this.emit('update'); });
      b.on('error', (msg) => this.emit('error', msg));
      b.on('autoplay-muted', () => this.emit('autoplay-muted'));
      b.load(media.src, this.expected(), media.playing).catch((e) => this.emit('error', e.message));
      this._stallSince = 0;
      this.emit('change', b);
    }
    this.sync(true);
    this.emit('update');
  }

  sync(force = false) {
    const b = this.backend;
    const s = this.state;
    if (!b || !s || !b.ready) return;
    if (s.playing && b.isPaused()) {
      b.play();
      // YouTube/Twitch ohne Benutzer-Klick: stumm starten, Hinweis zeigen
      if (b.kind !== 'video' && b.isStalled()) {
        this._stallSince ||= performance.now();
        if (performance.now() - this._stallSince > 2500 && !b.isMuted()) {
          b.setMuted(true);
          b.play();
          this.emit('autoplay-muted');
        }
      }
    } else if (!s.playing && !b.isPaused()) {
      b.pause();
    } else {
      this._stallSince = 0;
    }
    if (this.live) return;
    const exp = this.expected();
    const diff = b.getTime() - exp;
    const limit = force ? 0.75 : 1.5;
    if (Math.abs(diff) > limit && (!b.getDuration() || exp < b.getDuration())) b.seek(exp);
  }

  // Aktionen (gehen an alle)
  load(url) {
    const info = parseMediaUrl(url);
    if (!info) return false;
    this.net.send({ t: 'media', action: 'load', ...info });
    return info;
  }
  togglePlay() {
    if (!this.state) return;
    this.net.send({ t: 'media', action: this.state.playing ? 'pause' : 'play', time: this.live ? undefined : this.currentTime() });
  }
  seekBy(d) {
    if (!this.state || this.live) return;
    this.net.send({ t: 'media', action: 'seek', time: Math.max(0, this.currentTime() + d) });
  }
  seekTo(t) {
    if (!this.state || this.live) return;
    this.net.send({ t: 'media', action: 'seek', time: Math.max(0, t) });
  }
  stop() { this.net.send({ t: 'media', action: 'stop' }); }

  currentTime() { return this.backend?.ready ? this.backend.getTime() : this.expected(); }
  duration() { return this.backend?.getDuration?.() || 0; }

  setVolume(v) { this.volume = Math.max(0, Math.min(1, v)); this._applyVolume(); this.emit('update'); }
  setLocalMuted(m) { this.localMuted = m; this._applyVolume(); }
  unmute() { this.backend?.setMuted(false); this._applyVolume(); this.emit('update'); }
  _applyVolume() {
    const b = this.backend;
    if (!b?.ready) return;
    b.setVolume(this.localMuted ? 0 : this.volume);
  }

  _destroy() {
    this.backend?.destroy();
    this.backend = null;
  }
}
