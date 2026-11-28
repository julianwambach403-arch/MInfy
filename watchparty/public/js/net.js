// Netzwerk: WebSocket zum Server (Raum, Avatare, Chat, Synchronisierung)
// und WebRTC direkt zwischen den Teilnehmern (Sprache und geteilte Bildschirme).
import { Emitter } from './util.js';

export class Net extends Emitter {
  constructor() {
    super();
    this.ws = null;
    this.id = null;
    this.token = null;
    this.offset = 0; // Serverzeit - lokale Zeit
    this._bestRtt = Infinity;
    this._queue = [];
  }

  serverNow() { return Date.now() + this.offset; }

  connect({ room, name, color, relay = false }) {
    return new Promise((resolve, reject) => {
      const proto = location.protocol === 'https:' ? 'wss' : 'ws';
      const ws = new WebSocket(`${proto}://${location.host}/ws`);
      this.ws = ws;
      let welcomed = false;
      ws.onopen = () => {
        ws.send(JSON.stringify({ t: 'join', room, name, color, relay }));
        this._ping();
      };
      ws.onmessage = (ev) => {
        let m;
        try { m = JSON.parse(ev.data); } catch { return; }
        if (m.t === 'pong') { this._onPong(m); return; }
        if (m.t === 'welcome') {
          welcomed = true;
          this.id = m.id;
          this.token = m.token;
          if (this._bestRtt === Infinity) this.offset = m.serverTime - Date.now();
          this._pingTimer = setInterval(() => this._ping(), 5000);
          resolve(m);
          return;
        }
        if (m.t === 'error' && !welcomed) { reject(new Error(m.message)); return; }
        this.emit(m.t, m);
      };
      ws.onerror = () => { if (!welcomed) reject(new Error('Keine Verbindung zum Server.')); };
      ws.onclose = () => {
        clearInterval(this._pingTimer);
        if (welcomed) this.emit('disconnected');
        else reject(new Error('Verbindung abgelehnt.'));
      };
    });
  }

  send(obj) {
    if (this.ws && this.ws.readyState === 1) this.ws.send(JSON.stringify(obj));
  }

  _ping() { this.send({ t: 'ping', c: Date.now() }); }
  _onPong(m) {
    const now = Date.now();
    const rtt = now - m.c;
    // Nur Messungen mit kurzer Laufzeit sind genau
    if (rtt <= this._bestRtt * 1.5 || rtt < 60) {
      this._bestRtt = Math.min(this._bestRtt, rtt);
      this.offset = m.s + rtt / 2 - now;
    }
  }
}

// ---------- WebRTC (Mesh: jeder mit jedem) ----------
export class RTC extends Emitter {
  constructor(net, iceServers) {
    super();
    this.net = net;
    this.iceServers = iceServers;
    this.peers = new Map();
    this.mic = null; // MediaStream
    this.screen = null; // MediaStream
    net.on('signal', (m) => this._onSignal(m.from, m.data));
  }

  addPeer(id, { sendMic = true, sendScreen = true } = {}) {
    if (this.peers.has(id)) return this.peers.get(id);
    const pc = new RTCPeerConnection({ iceServers: this.iceServers });
    const p = { id, pc, polite: this.net.id > id, makingOffer: false, ignoreOffer: false, sendMic, sendScreen,
      senders: { mic: null, screen: [] }, streams: new Map() };
    this.peers.set(id, p);

    pc.onnegotiationneeded = async () => {
      try {
        p.makingOffer = true;
        await pc.setLocalDescription();
        this.net.send({ t: 'signal', to: id, data: { description: pc.localDescription } });
      } catch (e) {
        console.warn('Angebot fehlgeschlagen', e);
      } finally {
        p.makingOffer = false;
      }
    };
    pc.onicecandidate = ({ candidate }) => {
      if (candidate) this.net.send({ t: 'signal', to: id, data: { candidate } });
    };
    pc.ontrack = (e) => {
      const stream = e.streams[0];
      if (!stream) return;
      p.streams.set(stream.id, stream);
      this.emit('stream', id, stream);
      stream.addEventListener('removetrack', () => this.emit('stream', id, stream));
    };
    pc.onconnectionstatechange = () => {
      if (pc.connectionState === 'failed') pc.restartIce();
      this.emit('state', id, pc.connectionState);
    };
    pc.onsignalingstatechange = () => {
      if (pc.signalingState === 'stable') this._applyBitrate(p);
    };

    if (sendMic && this.mic) this._addMic(p);
    if (sendScreen && this.screen) this._addScreen(p);
    return p;
  }

  removePeer(id) {
    const p = this.peers.get(id);
    if (!p) return;
    p.pc.close();
    this.peers.delete(id);
  }

  getStream(peerId, streamId) {
    return this.peers.get(peerId)?.streams.get(streamId) || null;
  }

  async _onSignal(from, data) {
    let p = this.peers.get(from);
    if (!p) p = this.addPeer(from);
    const pc = p.pc;
    try {
      if (data.description) {
        const desc = data.description;
        const collision = desc.type === 'offer' && (p.makingOffer || pc.signalingState !== 'stable');
        p.ignoreOffer = !p.polite && collision;
        if (p.ignoreOffer) return;
        await pc.setRemoteDescription(desc);
        if (desc.type === 'offer') {
          await pc.setLocalDescription();
          this.net.send({ t: 'signal', to: from, data: { description: pc.localDescription } });
        }
      } else if (data.candidate) {
        try { await pc.addIceCandidate(data.candidate); } catch (e) { if (!p.ignoreOffer) console.warn(e); }
      }
    } catch (e) {
      console.warn('Signalisierung fehlgeschlagen', e);
    }
  }

  _addMic(p) {
    const track = this.mic.getAudioTracks()[0];
    if (!track) return;
    if (p.senders.mic) p.senders.mic.replaceTrack(track);
    else p.senders.mic = p.pc.addTrack(track, this.mic);
  }

  _addScreen(p) {
    for (const track of this.screen.getTracks()) p.senders.screen.push(p.pc.addTrack(track, this.screen));
  }

  _removeScreen(p) {
    for (const s of p.senders.screen) { try { p.pc.removeTrack(s); } catch { /* Verbindung schon zu */ } }
    p.senders.screen = [];
  }

  async _applyBitrate(p) {
    for (const s of p.senders.screen) {
      if (!s.track || s.track.kind !== 'video') continue;
      try {
        const params = s.getParameters();
        if (!params.encodings || !params.encodings.length) continue;
        const target = this.screenBitrate || 6_000_000;
        if (params.encodings[0].maxBitrate === target) continue;
        params.encodings[0].maxBitrate = target;
        params.degradationPreference = this.screen?.getVideoTracks()[0]?.contentHint === 'motion' ? 'maintain-framerate' : 'balanced';
        await s.setParameters(params);
      } catch { /* nicht unterstützt */ }
    }
  }

  setMic(stream) {
    this.mic = stream;
    for (const p of this.peers.values()) if (p.sendMic) this._addMic(p);
  }

  setScreen(stream) {
    for (const p of this.peers.values()) this._removeScreen(p);
    this.screen = stream;
    if (stream) for (const p of this.peers.values()) if (p.sendScreen) this._addScreen(p);
  }
}
