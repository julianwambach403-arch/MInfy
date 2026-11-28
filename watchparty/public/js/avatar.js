// Avatare der Freunde: Kopf mit Visier, Körper, zwei Hände, Namensschild.
// Beim Sprechen leuchtet das Visier, und die Stimme kommt räumlich von der Person.
import * as THREE from 'three';
import { makeLabel, makeEmojiSprite } from './util.js';

const _e = new THREE.Euler();

export const POSE_LEN = 22;

export function encodePose(head, headQ, left, leftQ, right, rightQ, flags) {
  const r = (v) => Math.round(v * 1000) / 1000;
  return [
    r(head.x), r(head.y), r(head.z), r(headQ.x), r(headQ.y), r(headQ.z), r(headQ.w),
    r(left.x), r(left.y), r(left.z), r(leftQ.x), r(leftQ.y), r(leftQ.z), r(leftQ.w),
    r(right.x), r(right.y), r(right.z), r(rightQ.x), r(rightQ.y), r(rightQ.z), r(rightQ.w),
    flags,
  ];
}

export class Avatar {
  constructor(peer) {
    this.id = peer.id;
    this.group = new THREE.Group();
    const color = new THREE.Color(peer.color);
    this.mat = new THREE.MeshStandardMaterial({ color, roughness: 0.5 });
    this.visorMat = new THREE.MeshStandardMaterial({ color: 0x0a0c18, roughness: 0.2, metalness: 0.4, emissive: color, emissiveIntensity: 0.05 });

    this.head = new THREE.Group();
    const skull = new THREE.Mesh(new THREE.SphereGeometry(0.13, 20, 14), this.mat);
    skull.scale.set(1, 1.08, 1);
    const visor = new THREE.Mesh(new THREE.BoxGeometry(0.2, 0.08, 0.08), this.visorMat);
    visor.position.set(0, 0.01, -0.105);
    this.head.add(skull, visor);

    this.body = new THREE.Mesh(new THREE.CapsuleGeometry(0.16, 0.32, 4, 12), this.mat);
    this.hands = [0, 1].map(() => {
      const h = new THREE.Mesh(new THREE.BoxGeometry(0.07, 0.04, 0.11), this.mat);
      this.group.add(h);
      return h;
    });
    this.group.add(this.head, this.body);

    this.label = makeLabel(peer.name, peer.color);
    this.group.add(this.label);
    this.name = peer.name;

    this.target = null;
    this.reactions = [];
    this.level = 0;
    this.group.visible = false;
  }

  setInfo(peer) {
    if (peer.name !== this.name) {
      this.group.remove(this.label);
      this.label.material.map.dispose();
      this.label = makeLabel(peer.name, peer.color);
      this.group.add(this.label);
      this.name = peer.name;
    }
    this.mat.color.set(peer.color);
    this.visorMat.emissive.set(peer.color);
    this.muted = peer.muted;
  }

  setPose(p) {
    if (!Array.isArray(p) || p.length < POSE_LEN) return;
    const first = !this.target;
    this.target = {
      head: new THREE.Vector3(p[0], p[1], p[2]), headQ: new THREE.Quaternion(p[3], p[4], p[5], p[6]).normalize(),
      left: new THREE.Vector3(p[7], p[8], p[9]), leftQ: new THREE.Quaternion(p[10], p[11], p[12], p[13]).normalize(),
      right: new THREE.Vector3(p[14], p[15], p[16]), rightQ: new THREE.Quaternion(p[17], p[18], p[19], p[20]).normalize(),
      flags: p[21] | 0,
    };
    if (first) this._snap();
    this.group.visible = true;
  }

  _snap() {
    const t = this.target;
    this.head.position.copy(t.head); this.head.quaternion.copy(t.headQ);
    this.hands[0].position.copy(t.left); this.hands[0].quaternion.copy(t.leftQ);
    this.hands[1].position.copy(t.right); this.hands[1].quaternion.copy(t.rightQ);
  }

  attachVoice(stream, listener) {
    if (this.voiceStream === stream) return;
    this.detachVoice();
    this.voiceStream = stream;
    // Chrome gibt WebRTC-Ton nur an Web Audio weiter, wenn er auch an einem (stummen) Element hängt
    this.voiceEl = new Audio();
    this.voiceEl.muted = true;
    this.voiceEl.srcObject = stream;
    this.voiceEl.play().catch(() => {});
    const audio = new THREE.PositionalAudio(listener);
    audio.setMediaStreamSource(stream);
    audio.setRefDistance(2);
    audio.setRolloffFactor(0.6);
    audio.setMaxDistance(30);
    this.head.add(audio);
    this.voice = audio;
    this.analyser = new THREE.AudioAnalyser(audio, 32);
  }

  detachVoice() {
    if (this.voice) {
      try { this.voice.disconnect(); } catch { /* schon getrennt */ }
      this.head.remove(this.voice);
    }
    if (this.voiceEl) this.voiceEl.srcObject = null;
    this.voice = this.voiceEl = this.analyser = this.voiceStream = null;
  }

  react(emoji) {
    const s = makeEmojiSprite(emoji);
    s.position.copy(this.head.position).add(new THREE.Vector3(0, 0.35, 0));
    this.group.add(s);
    this.reactions.push({ s, t: 0 });
  }

  update(dt) {
    const t = this.target;
    if (t) {
      const k = 1 - Math.exp(-dt * 14);
      this.head.position.lerp(t.head, k);
      this.head.quaternion.slerp(t.headQ, k);
      this.hands[0].position.lerp(t.left, k);
      this.hands[0].quaternion.slerp(t.leftQ, k);
      this.hands[1].position.lerp(t.right, k);
      this.hands[1].quaternion.slerp(t.rightQ, k);
      this.hands[0].visible = !!(t.flags & 2);
      this.hands[1].visible = !!(t.flags & 4);
    }
    // Körper unter dem Kopf, nur nach der Blickrichtung (Gier) gedreht
    _e.setFromQuaternion(this.head.quaternion, 'YXZ');
    this.body.position.copy(this.head.position).add(new THREE.Vector3(0, -0.48, 0));
    this.body.quaternion.setFromEuler(new THREE.Euler(0, _e.y, 0));
    this.body.position.addScaledVector(new THREE.Vector3(Math.sin(_e.y), 0, Math.cos(_e.y)), 0.06);
    this.label.position.copy(this.head.position).add(new THREE.Vector3(0, 0.25, 0));

    // Sprechanzeige
    const lvl = this.analyser && !this.muted ? Math.min(1, this.analyser.getAverageFrequency() / 60) : 0;
    this.level += (lvl - this.level) * Math.min(1, dt * 12);
    this.visorMat.emissiveIntensity = 0.05 + this.level * 2.2;

    for (let i = this.reactions.length - 1; i >= 0; i--) {
      const r = this.reactions[i];
      r.t += dt;
      r.s.position.y += dt * 0.25;
      r.s.material.opacity = Math.min(1, 3 - r.t);
      if (r.t > 3) {
        this.group.remove(r.s);
        r.s.material.map.dispose();
        this.reactions.splice(i, 1);
      }
    }
  }

  dispose() {
    this.detachVoice();
    this.group.parent?.remove(this.group);
  }
}

