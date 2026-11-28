// MInfy Lounge – Hauptprogramm
import * as THREE from 'three';
import { CSS3DRenderer, CSS3DObject } from 'three/addons/renderers/CSS3DRenderer.js';
import { Net, RTC } from './net.js';
import { MediaController } from './media.js';
import { buildWorld } from './world.js';
import { Avatar, encodePose } from './avatar.js';
import { Panel } from './vrui.js';
import { randomRoomCode, escapeHtml, formatTime, clamp, canShareScreen, isQuestBrowser } from './util.js';

const $ = (s) => document.querySelector(s);
const COLORS = ['#4fc3f7', '#ff4fd8', '#ffb74d', '#81c784', '#e57373', '#ba68c8', '#fff176', '#4db6ac', '#f06292', '#90a4ae'];
const REACTIONS = ['👍', '😂', '😮', '❤️', '🔥', '👏'];
const store = {
  get(k) { try { return localStorage.getItem(k); } catch { return null; } },
  set(k, v) { try { localStorage.setItem(k, v); } catch { /* privat */ } },
};

// =====================================================================
// Startseite
// =====================================================================
const params = new URLSearchParams(location.search);
let chosenColor = store.get('lounge.color') || COLORS[Math.floor(Math.random() * COLORS.length)];
$('#in-name').value = store.get('lounge.name') || '';
$('#in-room').value = (params.get('room') || store.get('lounge.room') || randomRoomCode()).toUpperCase();
$('#btn-newroom').onclick = () => { $('#in-room').value = randomRoomCode(); };
for (const c of COLORS) {
  const b = document.createElement('button');
  b.type = 'button';
  b.style.background = c;
  b.title = c;
  if (c === chosenColor) b.classList.add('sel');
  b.onclick = () => {
    chosenColor = c;
    document.querySelectorAll('#colors button').forEach((x) => x.classList.toggle('sel', x === b));
  };
  $('#colors').appendChild(b);
}
if (!$('#in-name').value) $('#in-name').focus();

$('#join-form').addEventListener('submit', async (e) => {
  e.preventDefault();
  const name = $('#in-name').value.trim() || 'Gast';
  const room = $('#in-room').value.trim().toUpperCase().replace(/[^A-Z0-9-]/g, '');
  if (!room) return;
  store.set('lounge.name', name);
  store.set('lounge.room', room);
  store.set('lounge.color', chosenColor);
  $('#btn-join').disabled = true;
  $('#btn-join').textContent = 'Verbinde …';
  $('#join-error').hidden = true;
  try {
    await start({ name, room, color: chosenColor });
  } catch (err) {
    $('#join-error').textContent = err.message || String(err);
    $('#join-error').hidden = false;
    $('#btn-join').disabled = false;
    $('#btn-join').textContent = 'Lounge betreten';
  }
});

// =====================================================================
// 3D-Szene
// =====================================================================
const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
renderer.setPixelRatio(Math.min(2, window.devicePixelRatio));
renderer.setSize(innerWidth, innerHeight);
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.xr.enabled = true;
renderer.xr.setReferenceSpaceType('local-floor');
renderer.xr.setFoveation(0.5);
$('#stage').appendChild(renderer.domElement);

const scene = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(70, innerWidth / innerHeight, 0.05, 100);
const rig = new THREE.Group();
rig.add(camera);
scene.add(rig);
const world = buildWorld(scene);

// YouTube/Twitch-Player als echtes Iframe, per CSS3D genau auf die Leinwand gelegt (nur außerhalb von VR)
const cssRenderer = new CSS3DRenderer();
cssRenderer.setSize(innerWidth, innerHeight);
$('#css3d').appendChild(cssRenderer.domElement);
const cssScene = new THREE.Scene();
const mediaHost = document.createElement('div');
mediaHost.className = 'media-host';
const cssObject = new CSS3DObject(mediaHost);
cssObject.visible = false;
cssScene.add(cssObject);

// Teleport-Ziel
const teleportMarker = new THREE.Mesh(new THREE.RingGeometry(0.22, 0.3, 32), new THREE.MeshBasicMaterial({ color: 0x8f7bff, transparent: true, opacity: 0.85 }));
teleportMarker.rotation.x = -Math.PI / 2;
teleportMarker.visible = false;
scene.add(teleportMarker);

const panel = new Panel();
rig.add(panel.mesh);

addEventListener('resize', () => {
  camera.aspect = innerWidth / innerHeight;
  camera.updateProjectionMatrix();
  renderer.setSize(innerWidth, innerHeight);
  cssRenderer.setSize(innerWidth, innerHeight);
});

// =====================================================================
// Zustand
// =====================================================================
const net = new Net();
let rtc = null;
let listener = null;
let media = null;
let me = null; // { id, name, color, micId, screenId, muted }
let roomCode = '';
const peers = new Map(); // id -> { info, avatar }
let focus = null;
let localMic = null;
let localScreen = null;
let contentVolume = 0.8;
const streamViews = new Map(); // stream.id -> { video, audio, stream }
const chatLines = [];
let seatIndex = 0;
let eyeHeight = 1.2;
let started = false;

function toast(msg) {
  const el = document.createElement('div');
  el.className = 'toast';
  el.textContent = msg;
  $('#toasts').appendChild(el);
  setTimeout(() => el.remove(), 4600);
}

const isXR = () => renderer.xr.isPresenting;
const humanPeers = () => [...peers.values()].filter((p) => !p.info.relay);
const relayPeer = () => [...peers.values()].find((p) => p.info.relay && p.info.screenId) || null;

// =====================================================================
// Start
// =====================================================================
async function start({ name, room, color }) {
  // Audio braucht einen Klick, daher erst jetzt
  listener = new THREE.AudioListener();
  camera.add(listener);
  THREE.AudioContext.getContext().resume?.();

  const welcome = await net.connect({ room, name, color });
  roomCode = welcome.room;
  me = { id: welcome.id, name, color, micId: null, screenId: null, muted: false };
  rtc = new RTC(net, welcome.iceServers);
  rtc.on('stream', (peerId) => resolvePeerStreams(peerId));
  media = new MediaController({ host: mediaHost, net });
  bindMedia();
  bindNet();

  for (const p of welcome.peers) addPeer(p);
  focus = welcome.focus;
  media.apply(welcome.media);

  history.replaceState(null, '', `?room=${encodeURIComponent(roomCode)}`);
  $('#lobby').hidden = true;
  $('#hud').hidden = false;
  $('#room-code').textContent = roomCode;
  started = true;
  sitDown(Math.floor(Math.random() * 6));
  setupHud();
  refreshAll();
  addChat({ sys: true, text: `Willkommen im Raum ${roomCode}! Teile den Link mit deinen Freunden.` });

  // Mikrofon
  try {
    localMic = await navigator.mediaDevices.getUserMedia({ audio: { echoCancellation: true, noiseSuppression: true, autoGainControl: true } });
    rtc.setMic(localMic);
    me.micId = localMic.id;
    net.send({ t: 'state', micId: localMic.id, muted: false });
    updatePeople();
  } catch {
    toast('Kein Mikrofon: Die anderen hören dich nicht (Zugriff im Browser erlauben).');
  }
  updateMicButton();
}

function addPeer(info) {
  if (peers.has(info.id)) return;
  const entry = { info, avatar: null };
  if (!info.relay) {
    entry.avatar = new Avatar(info);
    entry.avatar.setInfo(info);
    scene.add(entry.avatar.group);
    if (info.pose) entry.avatar.setPose(info.pose);
  }
  peers.set(info.id, entry);
  rtc.addPeer(info.id, { sendMic: !info.relay, sendScreen: !info.relay });
}

function removePeer(id) {
  const p = peers.get(id);
  if (!p) return;
  p.avatar?.dispose();
  rtc.removePeer(id);
  peers.delete(id);
}

function resolvePeerStreams(peerId) {
  const p = peers.get(peerId);
  if (!p) return;
  if (p.avatar && p.info.micId) {
    const s = rtc.getStream(peerId, p.info.micId);
    if (s && s.getAudioTracks().length) p.avatar.attachVoice(s, listener);
  }
  refreshScreens();
}

function bindNet() {
  net.on('peer-join', ({ peer }) => {
    addPeer(peer);
    if (!peer.relay) addChat({ sys: true, text: `${peer.name} ist da.` });
    else addChat({ sys: true, text: 'VR-Relais ist verbunden.' });
    refreshAll();
  });
  net.on('peer-leave', ({ id }) => {
    const p = peers.get(id);
    if (p && !p.info.relay) addChat({ sys: true, text: `${p.info.name} ist gegangen.` });
    removePeer(id);
    refreshAll();
  });
  net.on('peer-update', ({ peer }) => {
    const p = peers.get(peer.id);
    if (!p) return;
    const startedSharing = !p.info.screenId && peer.screenId && !peer.relay;
    p.info = peer;
    p.avatar?.setInfo(peer);
    if (startedSharing) toast(`${peer.name} teilt jetzt den Bildschirm.`);
    resolvePeerStreams(peer.id);
    refreshAll();
  });
  net.on('pose', ({ id, p }) => peers.get(id)?.avatar?.setPose(p));
  net.on('focus', (m) => { focus = m.focus; refreshAll(); });
  net.on('media', (m) => {
    media.apply(m.media);
    if (m.by && m.by !== me.name) {
      const what = { load: 'startet', play: 'spielt ab', pause: 'pausiert', seek: 'springt', stop: 'beendet das Video' }[m.action];
      if (what && m.action !== 'seek') addChat({ sys: true, text: `${m.by} ${what}${m.action === 'load' ? `: ${m.media?.title || ''}` : ''}` });
    }
    refreshAll();
  });
  net.on('chat', (m) => addChat({ name: m.name, color: m.color, text: m.text }));
  net.on('react', (m) => {
    if (m.id === me.id) return;
    peers.get(m.id)?.avatar?.react(m.e);
  });
  net.on('disconnected', () => {
    toast('Verbindung zum Server verloren. Seite neu laden, um wieder beizutreten.');
    addChat({ sys: true, text: 'Verbindung getrennt.' });
  });
}

function bindMedia() {
  media.on('change', () => refreshAll());
  media.on('update', () => { updateMediaBar(); markPanelDirty(); });
  media.on('error', (msg) => toast(msg));
  media.on('autoplay-muted', () => { $('#btn-unmute').hidden = false; });
}

// =====================================================================
// Quellen -> Leinwände
// =====================================================================
function sourceList() {
  const list = [];
  if (media?.state) list.push({ id: 'media', label: `${media.title || 'Video'}`, color: '#ffffff' });
  if (me?.screenId) list.push({ id: me.id, label: 'Dein Bildschirm', color: me.color });
  for (const p of humanPeers()) if (p.info.screenId) list.push({ id: p.info.id, label: `${p.info.name}: Bildschirm`, color: p.info.color });
  return list;
}

function videoFor(stream) {
  let v = streamViews.get(stream.id);
  if (!v) {
    const video = document.createElement('video');
    video.muted = true;
    video.playsInline = true;
    video.autoplay = true;
    video.srcObject = stream;
    video.play().catch(() => {});
    v = { stream, video, audio: null };
    streamViews.set(stream.id, v);
  }
  return v;
}

// Ton eines geteilten Bildschirms kommt räumlich aus der Leinwand
function screenAudio(view, screenObj, volume) {
  if (!view.stream.getAudioTracks().length) return;
  if (!view.audio) {
    view.audio = new THREE.PositionalAudio(listener);
    view.audio.setMediaStreamSource(view.stream);
    view.audio.setRefDistance(8);
    view.audio.setRolloffFactor(0.4);
  }
  if (screenObj && view.audio.parent !== screenObj.group) screenObj.group.add(view.audio);
  view.audio.setVolume(volume);
}

function refreshScreens() {
  if (!started) return;
  const sources = sourceList();
  const order = [];
  const f = sources.find((s) => s.id === focus);
  if (f) order.push(f);
  for (const s of sources) if (s !== f) order.push(s);
  const used = new Set();
  let holeScreen = null;

  world.screens.forEach((screen, i) => {
    const src = order[i];
    if (!src) {
      screen.setLabel('');
      if (i === 0) screen.showMessage(['MInfy Lounge', 'Link unten einfügen oder am PC „Teilen“ drücken', `Raum ${roomCode}`], { icon: '🍿' });
      else screen.showMessage(['Frei', 'Hier erscheinen geteilte Bildschirme'], { small: true });
      return;
    }
    screen.setLabel(src.label, src.color);
    if (src.id === 'media') {
      const b = media.backend;
      if (media.state.kind === 'video' && b?.video) {
        screen.showVideo(b.video, 'media');
      } else if (!isXR()) {
        screen.showHole('media');
        holeScreen = screen;
      } else {
        const relay = relayPeer();
        const rs = relay && rtc.getStream(relay.info.id, relay.info.screenId);
        if (rs && rs.getVideoTracks().length) {
          const view = videoFor(rs);
          screen.showVideo(view.video, rs.id);
          screenAudio(view, screen, i === 0 ? contentVolume : contentVolume * 0.4);
          used.add(rs.id);
        } else {
          screen.showMessage([media.state.kind === 'youtube' ? 'YouTube läuft' : 'Twitch läuft',
            'Im VR-Modus braucht es das VR-Relais:', 'Jemand am PC klickt unten auf „📡 VR-Relais“.', 'Den Ton hörst du trotzdem schon.'], { icon: '📡' });
        }
      }
      return;
    }
    // Geteilter Bildschirm
    let stream = null;
    if (src.id === me.id) stream = localScreen;
    else {
      const p = peers.get(src.id);
      stream = p && rtc.getStream(src.id, p.info.screenId);
    }
    if (stream && stream.getVideoTracks().length) {
      const view = videoFor(stream);
      screen.showVideo(view.video, stream.id);
      if (src.id !== me.id) screenAudio(view, screen, i === 0 ? contentVolume : contentVolume * 0.4);
      used.add(stream.id);
    } else {
      screen.showMessage(['Verbinde …', src.label], { small: true });
    }
  });

  // Nicht (mehr) angezeigte Streams stumm schalten bzw. aufräumen
  for (const [id, view] of streamViews) {
    const alive = view.stream.getTracks().some((t) => t.readyState === 'live');
    if (!used.has(id)) view.audio?.setVolume(0);
    if (!alive && !used.has(id)) {
      view.video.srcObject = null;
      if (view.audio) { try { view.audio.disconnect(); } catch { /* egal */ } view.audio.parent?.remove(view.audio); }
      streamViews.delete(id);
    }
  }

  // Iframe auf die richtige Leinwand
  cssObject.visible = !!holeScreen;
  cssObject.userData.screen = holeScreen;
  if (holeScreen) cssObject.scale.setScalar(holeScreen.width / 1280);

  // In VR mit Relais: Iframe-Ton aus, damit man nichts doppelt hört
  if (media) media.setLocalMuted(isXR() && !!relayPeer() && media.state && media.state.kind !== 'video');
}

function placeCssObject() {
  const s = cssObject.userData.screen;
  if (!s) return;
  s.surface.updateWorldMatrix(true, false);
  s.surface.getWorldPosition(cssObject.position);
  s.surface.getWorldQuaternion(cssObject.quaternion);
}

function setFocus(id) {
  if (id === focus) return;
  net.send({ t: 'focus', focus: id });
}

// =====================================================================
// 2D-Oberfläche
// =====================================================================
function setupHud() {
  $('#btn-copy').onclick = async () => {
    const link = `${location.origin}/?room=${encodeURIComponent(roomCode)}`;
    try { await navigator.clipboard.writeText(link); toast('Link kopiert!'); } catch { prompt('Einladungslink:', link); }
  };
  $('#btn-mic').onclick = toggleMute;
  if (!canShareScreen) {
    for (const id of ['#btn-share', '#btn-game']) {
      $(id).disabled = true;
      $(id).title = isQuestBrowser ? 'Auf der Quest kann man keinen Bildschirm teilen. Teile vom PC aus (Chrome oder Edge).' : 'Dein Browser kann keinen Bildschirm teilen (Chrome oder Edge am PC verwenden).';
    }
  }
  $('#btn-share').onclick = () => startShare(false);
  $('#btn-game').onclick = () => startShare(true);
  $('#btn-stopshare').onclick = stopShare;
  $('#btn-help').onclick = () => { $('#help').hidden = false; };
  $('#btn-help-close').onclick = () => { $('#help').hidden = true; };

  $('#media-form').addEventListener('submit', (e) => {
    e.preventDefault();
    const url = $('#in-url').value.trim();
    if (!url) return;
    $('#btn-unmute').hidden = true;
    const info = media.load(url);
    if (!info) { toast('Das ist kein gültiger Link.'); return; }
    $('#in-url').value = '';
    $('#in-url').blur();
  });
  $('#btn-play').onclick = () => media.togglePlay();
  $('#btn-back').onclick = () => media.seekBy(-10);
  $('#btn-fwd').onclick = () => media.seekBy(10);
  $('#btn-stop').onclick = () => media.stop();
  $('#seek').addEventListener('change', (e) => {
    const d = media.duration();
    if (d) media.seekTo((e.target.value / 1000) * d);
  });
  $('#volume').addEventListener('input', (e) => setContentVolume(e.target.value / 100));
  $('#btn-unmute').onclick = () => { media.unmute(); $('#btn-unmute').hidden = true; };
  $('#btn-relay').onclick = () => {
    const w = window.open(`relay.html?room=${encodeURIComponent(roomCode)}`, 'lounge-relay', 'width=1300,height=820');
    if (!w) toast('Popup blockiert: Bitte Popups für diese Seite erlauben.');
  };
  $('#btn-interact').onclick = () => {
    document.body.classList.toggle('interact');
    const on = document.body.classList.contains('interact');
    $('#btn-interact').classList.toggle('primary', on);
    toast(on ? 'Du kannst jetzt direkt in den Player klicken. Nochmal drücken zum Umschauen.' : 'Umschauen wieder aktiv.');
  };

  $('#chat-form').addEventListener('submit', (e) => {
    e.preventDefault();
    const text = $('#in-chat').value.trim();
    if (!text) return;
    net.send({ t: 'chat', text });
    $('#in-chat').value = '';
  });
  document.querySelectorAll('[data-react]').forEach((b) => { b.onclick = () => sendReaction(b.dataset.react); });

  // VR verfügbar?
  if (navigator.xr) {
    navigator.xr.isSessionSupported('immersive-vr').then((ok) => {
      if (ok) $('#btn-vr').hidden = false;
    }).catch(() => {});
  }
  $('#btn-vr').onclick = enterVR;
  if (!window.isSecureContext) toast('Achtung: Ohne HTTPS gehen VR, Mikrofon und Teilen nicht.');
}

function setContentVolume(v) {
  contentVolume = clamp(v, 0, 1);
  media.setVolume(contentVolume);
  $('#volume').value = Math.round(contentVolume * 100);
  refreshScreens();
}

function sendReaction(e) {
  net.send({ t: 'react', e });
  toast(`Du: ${e}`);
}

function addChat(line) {
  chatLines.push(line);
  if (chatLines.length > 60) chatLines.shift();
  const el = document.createElement('div');
  if (line.sys) { el.className = 'sys'; el.textContent = line.text; } else {
    el.innerHTML = `<b style="color:${escapeHtml(line.color || '#fff')}">${escapeHtml(line.name)}:</b> ${escapeHtml(line.text)}`;
  }
  const log = $('#chat-log');
  log.appendChild(el);
  while (log.children.length > 60) log.firstChild.remove();
  log.scrollTop = log.scrollHeight;
  markPanelDirty();
}

function refreshAll() {
  refreshScreens();
  updatePeople();
  updateSources();
  updateMediaBar();
  updateShareButtons();
  markPanelDirty();
}

function updatePeople() {
  const el = $('#people');
  const list = [{ info: { ...me, name: `${me.name} (du)` } }, ...humanPeers()];
  el.innerHTML = list.map(({ info }) => `<span class="person"><i style="background:${escapeHtml(info.color)}"></i>${escapeHtml(info.name)}${info.muted || (info.id === me.id && !localMic) ? ' 🔇' : ''}${info.inVR ? ' 🥽' : ''}${info.screenId ? ' 🖥️' : ''}</span>`).join('');
}

function updateSources() {
  const list = sourceList();
  const el = $('#sources');
  el.hidden = list.length < 2;
  el.innerHTML = '<span>Große Leinwand:</span>';
  for (const s of list) {
    const b = document.createElement('button');
    b.className = `small${s.id === focus ? ' on' : ''}`;
    b.textContent = s.id === 'media' ? `🎬 ${s.label}` : `🖥️ ${s.label}`;
    b.onclick = () => setFocus(s.id);
    el.appendChild(b);
  }
}

function updateMediaBar() {
  if (!media) return;
  const s = media.state;
  $('#media-now').hidden = !s;
  if (!s) { $('#btn-unmute').hidden = true; return; }
  $('#media-kind').textContent = { youtube: '▶️ YouTube', twitch: '🟣 Twitch', video: '🎬 Video' }[s.kind];
  $('#media-title').textContent = media.title || '';
  $('#media-by').textContent = s.by ? `von ${s.by}` : '';
  $('#btn-play').textContent = s.playing ? '⏸' : '▶️';
  const live = media.live;
  for (const id of ['#btn-back', '#btn-fwd', '#seek']) $(id).disabled = live;
  const iframeKind = s.kind !== 'video';
  const relay = relayPeer();
  $('#btn-relay').hidden = !iframeKind || !canShareScreen || !!relay;
  $('#btn-interact').hidden = !iframeKind;
  const vrFriends = humanPeers().filter((p) => p.info.inVR).length;
  const info = $('#relay-info');
  if (iframeKind && relay) { info.hidden = false; info.textContent = '📡 VR-Relais aktiv: Freunde in VR sehen das Video auf der Leinwand.'; } else if (iframeKind && vrFriends && canShareScreen) {
    info.hidden = false;
    info.textContent = `🥽 ${vrFriends} Freund(e) in VR sehen YouTube/Twitch erst mit dem VR-Relais.`;
  } else info.hidden = true;
  updateTime();
}

function updateTime() {
  if (!media?.state) return;
  const t = media.currentTime(), d = media.duration();
  $('#media-time').textContent = media.live ? '🔴 LIVE' : `${formatTime(t)} / ${formatTime(d)}`;
  if (d && document.activeElement !== $('#seek')) $('#seek').value = Math.round((t / d) * 1000);
}
setInterval(updateTime, 500);

function updateShareButtons() {
  const sharing = !!localScreen;
  $('#btn-share').hidden = sharing;
  $('#btn-game').hidden = sharing;
  $('#btn-stopshare').hidden = !sharing;
}

function updateMicButton() {
  const b = $('#btn-mic');
  if (!localMic) { b.textContent = '🎤✖'; b.classList.add('off'); b.title = 'Kein Mikrofon'; return; }
  b.textContent = me.muted ? '🔇' : '🎤';
  b.classList.toggle('off', me.muted);
}

function toggleMute() {
  if (!localMic) { toast('Kein Mikrofon verfügbar.'); return; }
  me.muted = !me.muted;
  localMic.getAudioTracks().forEach((t) => { t.enabled = !me.muted; });
  net.send({ t: 'state', muted: me.muted });
  updateMicButton();
  updatePeople();
  markPanelDirty();
}

// =====================================================================
// Bildschirm teilen
// =====================================================================
async function startShare(game) {
  if (!canShareScreen) return;
  try {
    const stream = await navigator.mediaDevices.getDisplayMedia({
      video: { frameRate: { ideal: game ? 60 : 30, max: 60 }, width: { max: 1920 }, height: { max: 1080 } },
      audio: { echoCancellation: false, noiseSuppression: false, autoGainControl: false },
      systemAudio: 'include', selfBrowserSurface: 'exclude', surfaceSwitching: 'include',
    });
    const vt = stream.getVideoTracks()[0];
    vt.contentHint = game ? 'motion' : 'detail';
    vt.addEventListener('ended', stopShare);
    localScreen = stream;
    rtc.screenBitrate = game ? 8_000_000 : 5_000_000;
    rtc.setScreen(stream);
    me.screenId = stream.id;
    net.send({ t: 'state', screenId: stream.id, screenName: vt.label || '' });
    if (!stream.getAudioTracks().length) toast('Hinweis: Ohne Ton geteilt. Für Ton „Tab-/Systemaudio teilen“ anhaken.');
    if (!focus) setFocus(me.id);
    refreshAll();
  } catch (e) {
    if (e.name !== 'NotAllowedError') toast(`Teilen fehlgeschlagen: ${e.message}`);
  }
}

function stopShare() {
  if (!localScreen) return;
  localScreen.getTracks().forEach((t) => t.stop());
  localScreen = null;
  rtc.setScreen(null);
  me.screenId = null;
  net.send({ t: 'state', screenId: null });
  refreshAll();
}

// =====================================================================
// Sitzen und Bewegen
// =====================================================================
function sitDown(i) {
  seatIndex = ((i % world.seats.length) + world.seats.length) % world.seats.length;
  const seat = world.seats[seatIndex];
  if (isXR()) {
    // Kopfposition auf den Platz setzen
    const head = camera.getWorldPosition(new THREE.Vector3());
    rig.position.x += seat.pos.x - head.x;
    rig.position.z += seat.pos.z - head.z;
    rig.position.y = seat.pos.y;
  } else {
    rig.position.copy(seat.pos);
    rig.rotation.set(0, seat.yaw, 0);
    camera.rotation.set(0.04, 0, 0, 'YXZ');
    eyeHeight = seatIndex === world.seats.length - 1 ? 1.6 : 1.2;
  }
}

const keys = new Set();
addEventListener('keydown', (e) => {
  if (!started || e.target.tagName === 'INPUT') {
    if (e.key === 'Escape') e.target.blur?.();
    return;
  }
  keys.add(e.code);
  if (e.code === 'KeyM') toggleMute();
  if (e.code === 'Enter') { e.preventDefault(); $('#in-chat').focus(); }
});
addEventListener('keyup', (e) => keys.delete(e.code));
addEventListener('blur', () => keys.clear());

// Umschauen per Ziehen (funktioniert mit Maus, Touch und Quest-Controller im Browserfenster)
let drag = null;
const canvas = renderer.domElement;
canvas.addEventListener('pointerdown', (e) => {
  drag = { x: e.clientX, y: e.clientY, sx: e.clientX, sy: e.clientY, moved: false };
  canvas.setPointerCapture(e.pointerId);
});
canvas.addEventListener('pointermove', (e) => {
  if (!drag || isXR()) return;
  const dx = e.clientX - drag.x, dy = e.clientY - drag.y;
  drag.x = e.clientX; drag.y = e.clientY;
  if (Math.abs(e.clientX - drag.sx) + Math.abs(e.clientY - drag.sy) > 6) drag.moved = true;
  rig.rotation.y += dx * 0.004;
  camera.rotation.x = clamp(camera.rotation.x + dy * 0.004, -1.3, 1.3);
});
canvas.addEventListener('pointerup', (e) => {
  if (drag && !drag.moved && started) clickScene(e);
  drag = null;
});

const raycaster = new THREE.Raycaster();
function clickScene(e) {
  const ndc = new THREE.Vector2((e.clientX / innerWidth) * 2 - 1, -(e.clientY / innerHeight) * 2 + 1);
  raycaster.setFromCamera(ndc, camera);
  const hit = raycaster.intersectObjects(world.screens.map((s) => s.hit), false)[0];
  if (hit) clickScreen(hit.object.userData.screen);
}

function clickScreen(screen) {
  if (screen === world.main) return;
  const idx = world.screens.indexOf(screen);
  const sources = sourceList();
  const order = [];
  const f = sources.find((s) => s.id === focus);
  if (f) order.push(f);
  for (const s of sources) if (s !== f) order.push(s);
  if (order[idx]) setFocus(order[idx].id);
}

const ROOM_BOUNDS = { x: 8.4, zMin: -7.6, zMax: 7.6 };
function clampRig() {
  rig.position.x = clamp(rig.position.x, -ROOM_BOUNDS.x, ROOM_BOUNDS.x);
  rig.position.z = clamp(rig.position.z, ROOM_BOUNDS.zMin, ROOM_BOUNDS.zMax);
}

function desktopMove(dt) {
  const f = (keys.has('KeyW') || keys.has('ArrowUp') ? 1 : 0) - (keys.has('KeyS') || keys.has('ArrowDown') ? 1 : 0);
  const s = (keys.has('KeyD') || keys.has('ArrowRight') ? 1 : 0) - (keys.has('KeyA') || keys.has('ArrowLeft') ? 1 : 0);
  if (f || s) {
    const yaw = rig.rotation.y;
    const speed = 2.6 * dt;
    rig.position.x += (-Math.sin(yaw) * f + Math.cos(yaw) * s) * speed;
    rig.position.z += (-Math.cos(yaw) * f - Math.sin(yaw) * s) * speed;
    rig.position.y += (0 - rig.position.y) * Math.min(1, dt * 8);
    eyeHeight += (1.6 - eyeHeight) * Math.min(1, dt * 6);
    clampRig();
  }
  camera.position.set(0, eyeHeight, 0);
  camera.rotation.order = 'YXZ';
}

// =====================================================================
// VR
// =====================================================================
async function enterVR() {
  try {
    const session = await navigator.xr.requestSession('immersive-vr', { optionalFeatures: ['local-floor', 'bounded-floor', 'hand-tracking'] });
    await renderer.xr.setSession(session);
  } catch (e) {
    toast(`VR konnte nicht starten: ${e.message}`);
  }
}

renderer.xr.addEventListener('sessionstart', () => {
  // Blickrichtung behalten, Kamera übernimmt jetzt die Brille
  camera.position.set(0, 0, 0);
  camera.rotation.set(0, 0, 0);
  net.send({ t: 'state', inVR: true });
  $('#css3d').style.visibility = 'hidden';
  setTimeout(() => sitDown(seatIndex), 300);
  refreshAll();
});
renderer.xr.addEventListener('sessionend', () => {
  panel.close();
  teleportMarker.visible = false;
  rig.rotation.x = rig.rotation.z = 0;
  net.send({ t: 'state', inVR: false });
  $('#css3d').style.visibility = '';
  sitDown(seatIndex);
  refreshAll();
});

const hands = [];
for (let i = 0; i < 2; i++) {
  const controller = renderer.xr.getController(i);
  const grip = renderer.xr.getControllerGrip(i);
  const laser = new THREE.Line(
    new THREE.BufferGeometry().setFromPoints([new THREE.Vector3(0, 0, 0), new THREE.Vector3(0, 0, -1)]),
    new THREE.LineBasicMaterial({ color: 0xbfb6ff, transparent: true, opacity: 0.8 }),
  );
  laser.scale.z = 3;
  controller.add(laser);
  const handMesh = new THREE.Mesh(new THREE.BoxGeometry(0.06, 0.035, 0.11), new THREE.MeshStandardMaterial({ color: 0xbfc4ff }));
  grip.add(handMesh);
  const h = { controller, grip, laser, handMesh, source: null, buttons: [], hit: null, turnReady: true };
  controller.addEventListener('connected', (e) => {
    h.source = e.data;
    handMesh.material.color.set(me?.color || '#bfc4ff');
    handMesh.visible = !e.data.hand;
  });
  controller.addEventListener('disconnected', () => { h.source = null; });
  controller.addEventListener('selectstart', () => onSelect(h));
  rig.add(controller, grip);
  hands.push(h);
}

const tmpMat = new THREE.Matrix4();
function updateLasers() {
  const targets = [...world.screens.map((s) => s.hit), world.floor];
  if (panel.visible) targets.unshift(panel.mesh);
  let panelHit = false;
  teleportMarker.visible = false;
  for (const h of hands) {
    if (!h.source || h.source.targetRayMode === 'gaze') { h.laser.visible = false; continue; }
    h.laser.visible = true;
    tmpMat.identity().extractRotation(h.controller.matrixWorld);
    raycaster.ray.origin.setFromMatrixPosition(h.controller.matrixWorld);
    raycaster.ray.direction.set(0, 0, -1).applyMatrix4(tmpMat);
    raycaster.far = 30;
    const hit = raycaster.intersectObjects(targets, false)[0] || null;
    h.hit = hit;
    h.laser.scale.z = hit ? hit.distance : 3;
    if (hit?.object === panel.mesh) {
      panel.pointAt(hit.uv);
      panelHit = true;
    } else if (hit?.object === world.floor) {
      teleportMarker.position.copy(hit.point).setY(0.01);
      teleportMarker.visible = true;
    }
  }
  if (!panelHit && panel.visible) panel.pointAt(null);
}

function onSelect(h) {
  const hit = h.hit;
  if (!hit) return;
  if (hit.object === panel.mesh) {
    const b = panel.click(hit.uv);
    if (b) panelAction(b.id);
    return;
  }
  if (hit.object.userData.screen) { clickScreen(hit.object.userData.screen); return; }
  if (hit.object === world.floor) {
    const head = camera.getWorldPosition(new THREE.Vector3());
    rig.position.x += hit.point.x - head.x;
    rig.position.z += hit.point.z - head.z;
    rig.position.y = 0;
    clampRig();
    panel.close();
  }
}

function pressed(h, idx) {
  const gp = h.source?.gamepad;
  const now = !!gp?.buttons[idx]?.pressed;
  const was = !!h.buttons[idx];
  h.buttons[idx] = now;
  return now && !was;
}

const UP = new THREE.Vector3(0, 1, 0);
function xrInput(dt) {
  for (const h of hands) {
    const gp = h.source?.gamepad;
    if (!gp) continue;
    const ax = gp.axes.length >= 4 ? [gp.axes[2], gp.axes[3]] : [gp.axes[0] || 0, gp.axes[1] || 0];
    if (h.source.handedness === 'left') {
      // Laufen relativ zur Blickrichtung
      if (Math.hypot(ax[0], ax[1]) > 0.15) {
        const dir = camera.getWorldDirection(new THREE.Vector3());
        dir.y = 0; dir.normalize();
        const right = new THREE.Vector3().crossVectors(dir, UP);
        rig.position.addScaledVector(dir, -ax[1] * 2 * dt).addScaledVector(right, ax[0] * 2 * dt);
        clampRig();
      }
      if (pressed(h, 4)) togglePanel(); // X
      if (pressed(h, 5)) toggleMute(); // Y
    } else {
      // Drehen in 30°-Schritten um den Kopf
      if (h.turnReady && Math.abs(ax[0]) > 0.7) {
        const angle = -Math.sign(ax[0]) * Math.PI / 6;
        const head = camera.getWorldPosition(new THREE.Vector3());
        rig.position.sub(head).applyAxisAngle(UP, angle).add(head);
        rig.rotation.y += angle;
        h.turnReady = false;
        if (panel.visible) panel.close();
      } else if (Math.abs(ax[0]) < 0.3) h.turnReady = true;
      if (pressed(h, 4)) togglePanel(); // A
      if (pressed(h, 5)) togglePanel(); // B
    }
  }
}

function togglePanel() {
  if (panel.visible) { panel.close(); return; }
  renderPanel();
  panel.openAt(camera, rig);
}

let panelDirty = true;
function markPanelDirty() { panelDirty = true; }

function renderPanel() {
  panelDirty = false;
  const sources = sourceList();
  const s = media?.state;
  const n = humanPeers().length + 1;
  const sub = [`Raum ${roomCode}`, `${n} ${n === 1 ? 'Person' : 'Personen'}`];
  if (s) sub.push(media.live ? `${media.title} · LIVE` : `${media.title} · ${formatTime(media.currentTime())}`);
  const lines = chatLines.slice(-6).map((l) => (l.sys ? { text: l.text, color: '#8f95d6' } : { text: `${l.name}: ${l.text}`, color: '#e6e8ff' }));
  if (!sources.length) lines.unshift({ text: 'Tipp: Am PC einen Link einfügen oder den Bildschirm teilen.', color: '#ffd37a' });
  panel.render({
    title: '🍿 MInfy Lounge',
    subtitle: sub.join(' · '),
    sections: [
      { label: 'ICH', buttons: [
        { id: 'mic', text: !localMic ? '🎤 kein Mikro' : me.muted ? '🔇 Stumm' : '🎤 Mikro an', active: !!localMic && !me.muted, disabled: !localMic },
        { id: 'seat', text: '💺 Platz wechseln' },
        { id: 'close', text: '✖ Menü zu' },
        { id: 'exit', text: '🚪 VR verlassen' },
      ] },
      { label: 'GROSSE LEINWAND', buttons: sources.length ? sources.map((src) => ({ id: `focus:${src.id}`, text: `${src.id === 'media' ? '🎬' : '🖥️'} ${src.label}`.slice(0, 34), active: src.id === focus }))
        : [{ id: 'none', text: 'Noch nichts geteilt', disabled: true }] },
      { label: 'VIDEO', buttons: [
        { id: 'back', text: '⏪ 10 s', disabled: !s || media.live },
        { id: 'play', text: s?.playing ? '⏸ Pause' : '▶️ Play', disabled: !s },
        { id: 'fwd', text: '⏩ 10 s', disabled: !s || media.live },
        { id: 'stop', text: '⏹', disabled: !s },
        { id: 'voldown', text: '🔉' },
        { id: 'volup', text: `🔊 ${Math.round(contentVolume * 100)} %` },
      ] },
      { label: 'REAKTION', buttons: REACTIONS.map((e) => ({ id: `react:${e}`, text: e, w: 92 })) },
    ],
    lines,
  });
}

function panelAction(id) {
  if (id.startsWith('focus:')) { setFocus(id.slice(6)); return; }
  if (id.startsWith('react:')) { net.send({ t: 'react', e: id.slice(6) }); return; }
  switch (id) {
    case 'mic': toggleMute(); break;
    case 'seat': sitDown(seatIndex + 1); panel.close(); break;
    case 'close': panel.close(); break;
    case 'exit': renderer.xr.getSession()?.end(); break;
    case 'back': media.seekBy(-10); break;
    case 'fwd': media.seekBy(10); break;
    case 'play': media.togglePlay(); break;
    case 'stop': media.stop(); break;
    case 'voldown': setContentVolume(contentVolume - 0.1); break;
    case 'volup': setContentVolume(contentVolume + 0.1); break;
    default: break;
  }
  markPanelDirty();
}

// =====================================================================
// Pose senden
// =====================================================================
const headPos = new THREE.Vector3(), headQ = new THREE.Quaternion();
const lPos = new THREE.Vector3(), lQ = new THREE.Quaternion(), rPos = new THREE.Vector3(), rQ = new THREE.Quaternion();
let lastPose = 0, lastPoseSent = 0, lastPoseStr = '';
function sendPose(now) {
  if (now - lastPose < 66) return;
  lastPose = now;
  camera.getWorldPosition(headPos);
  camera.getWorldQuaternion(headQ);
  let flags = 0;
  if (isXR()) {
    flags |= 1;
    for (const h of hands) {
      if (!h.source) continue;
      const isLeft = h.source.handedness === 'left';
      const src = h.source.hand ? h.controller : h.grip;
      src.getWorldPosition(isLeft ? lPos : rPos);
      src.getWorldQuaternion(isLeft ? lQ : rQ);
      flags |= isLeft ? 2 : 4;
    }
  } else {
    const yawQ = new THREE.Quaternion().setFromAxisAngle(UP, rig.rotation.y);
    lPos.set(-0.24, -0.5, -0.22).applyQuaternion(yawQ).add(headPos);
    rPos.set(0.24, -0.5, -0.22).applyQuaternion(yawQ).add(headPos);
    lQ.copy(yawQ); rQ.copy(yawQ);
    flags |= 6;
  }
  const p = encodePose(headPos, headQ, lPos, lQ, rPos, rQ, flags);
  const str = p.join(',');
  if (str === lastPoseStr && now - lastPoseSent < 1000) return;
  lastPoseStr = str;
  lastPoseSent = now;
  net.send({ t: 'pose', p });
}

// =====================================================================
// Hauptschleife
// =====================================================================
const clock = new THREE.Clock();
let panelTimer = 0;
renderer.setAnimationLoop((time) => {
  const dt = Math.min(0.1, clock.getDelta());
  if (started) {
    if (isXR()) {
      xrInput(dt);
      updateLasers();
      panelTimer += dt;
      if (panel.visible && (panelDirty || panelTimer > 1)) { panelTimer = 0; renderPanel(); }
    } else {
      desktopMove(dt);
    }
    for (const p of peers.values()) p.avatar?.update(dt);
    for (const s of world.screens) s.update();
    sendPose(time);
  } else {
    // Langsame Kamerafahrt hinter der Startseite
    rig.position.set(Math.sin(time / 8000) * 2, 0, 4);
    rig.rotation.y = Math.sin(time / 9000) * 0.25;
    camera.position.set(0, 1.7, 0);
  }
  renderer.render(scene, camera);
  if (!isXR()) {
    placeCssObject();
    cssRenderer.render(cssScene, camera);
  }
});

world.main.showMessage(['MInfy Lounge', 'Zusammen schauen, teilen und zocken'], { icon: '🍿' });

// Für die Fehlersuche in der Browser-Konsole
window.lounge = { scene, camera, rig, world, panel, renderPanel, peers, get media() { return media; }, get rtc() { return rtc; } };
