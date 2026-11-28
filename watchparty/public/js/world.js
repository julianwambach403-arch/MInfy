// Die Lounge: gemütlicher Kinosaal mit großer Leinwand, Seitenbildschirmen und Sofas.
import * as THREE from 'three';
import { roundRect } from './util.js';

const SCREEN_RATIO = 16 / 9;

export class Screen {
  constructor(width, name) {
    this.width = width;
    this.height = width / SCREEN_RATIO;
    this.name = name;
    this.group = new THREE.Group();
    this.group.name = name;

    const frame = new THREE.Mesh(
      new THREE.BoxGeometry(this.width + 0.16, this.height + 0.16, 0.08),
      new THREE.MeshStandardMaterial({ color: 0x0b0c12, roughness: 0.6, metalness: 0.3 }),
    );
    frame.position.z = -0.05;
    this.group.add(frame);

    this.videoMat = new THREE.MeshBasicMaterial({ color: 0xffffff, toneMapped: false });
    this.holeMat = new THREE.MeshBasicMaterial({ color: 0x000000, opacity: 0, blending: THREE.NoBlending });
    this.surface = new THREE.Mesh(new THREE.PlaneGeometry(1, 1), this.videoMat);
    this.surface.scale.set(this.width, this.height, 1);
    this.surface.userData.screen = this;
    this.group.add(this.surface);

    // Klickfläche (ganzer Rahmen), damit man den Bildschirm auch leer anklicken kann
    this.hit = new THREE.Mesh(new THREE.PlaneGeometry(this.width, this.height), new THREE.MeshBasicMaterial({ visible: false }));
    this.hit.position.z = 0.01;
    this.hit.userData.screen = this;
    this.group.add(this.hit);

    this.canvas = document.createElement('canvas');
    this.canvas.width = 1280;
    this.canvas.height = 720;
    this.canvasTex = new THREE.CanvasTexture(this.canvas);
    this.canvasTex.colorSpace = THREE.SRGBColorSpace;

    this.labelCanvas = document.createElement('canvas');
    this.labelCanvas.width = 1024;
    this.labelCanvas.height = 96;
    this.labelTex = new THREE.CanvasTexture(this.labelCanvas);
    this.labelTex.colorSpace = THREE.SRGBColorSpace;
    const labelH = Math.max(0.16, this.width * 0.035);
    this.label = new THREE.Mesh(
      new THREE.PlaneGeometry(labelH * (1024 / 96), labelH),
      new THREE.MeshBasicMaterial({ map: this.labelTex, transparent: true, depthWrite: false, toneMapped: false }),
    );
    this.label.position.set(0, -this.height / 2 - labelH * 0.9, 0.02);
    this.group.add(this.label);

    this.videoEl = null;
    this.videoTex = null;
    this.mode = null;
    this.key = null;
    this.showMessage(['Frei'], { small: true });
    this.setLabel('');
  }

  // Wird pro Bild aufgerufen: passt das Seitenverhältnis an das Video an
  update() {
    if (this.mode !== 'video' || !this.videoEl) return;
    const v = this.videoEl;
    if (v.videoWidth && v.videoHeight) this._fit(v.videoWidth / v.videoHeight);
  }

  _fit(aspect) {
    let w = this.width, h = this.height;
    if (aspect > SCREEN_RATIO) h = w / aspect; else w = h * aspect;
    this.surface.scale.set(w, h, 1);
  }

  showVideo(videoEl, key) {
    if (this.mode === 'video' && this.videoEl === videoEl) return;
    this.videoTex?.dispose();
    this.videoEl = videoEl;
    this.videoTex = new THREE.VideoTexture(videoEl);
    this.videoTex.colorSpace = THREE.SRGBColorSpace;
    this.videoMat.map = this.videoTex;
    this.videoMat.needsUpdate = true;
    this.surface.material = this.videoMat;
    this.mode = 'video';
    this.key = key;
  }

  showHole(key) {
    this.mode = 'hole';
    this.key = key;
    this.surface.material = this.holeMat;
    this.surface.scale.set(this.width, this.height, 1);
  }

  showMessage(lines, { small = false, icon = '' } = {}) {
    const sig = JSON.stringify([lines, small, icon]);
    if (this.mode === 'canvas' && this._sig === sig) return;
    this._sig = sig;
    const c = this.canvas, ctx = c.getContext('2d');
    const g = ctx.createLinearGradient(0, 0, c.width, c.height);
    g.addColorStop(0, '#141833');
    g.addColorStop(1, '#2a1238');
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, c.width, c.height);
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillStyle = '#ffffff';
    const big = small ? 64 : 72;
    let y = c.height / 2 - (lines.length - 1) * (small ? 40 : 34) - (icon ? 50 : 0);
    if (icon) {
      ctx.font = '120px "Segoe UI Emoji","Noto Color Emoji",sans-serif';
      ctx.fillText(icon, c.width / 2, y);
      y += 130;
    }
    lines.forEach((line, i) => {
      ctx.font = i === 0 ? `700 ${big}px system-ui, sans-serif` : '400 38px system-ui, sans-serif';
      ctx.fillStyle = i === 0 ? '#ffffff' : '#c9cbe8';
      ctx.fillText(line, c.width / 2, y);
      y += i === 0 ? 90 : 56;
    });
    this.canvasTex.needsUpdate = true;
    this.videoMat.map = this.canvasTex;
    this.videoMat.needsUpdate = true;
    this.surface.material = this.videoMat;
    this.surface.scale.set(this.width, this.height, 1);
    this.mode = 'canvas';
    this.key = null;
    this.videoEl = null;
  }

  setLabel(text, color = '#ffffff') {
    if (this._label === text + color) return;
    this._label = text + color;
    const c = this.labelCanvas, ctx = c.getContext('2d');
    ctx.clearRect(0, 0, c.width, c.height);
    this.label.visible = !!text;
    if (!text) { this.labelTex.needsUpdate = true; return; }
    ctx.font = '600 52px system-ui, sans-serif';
    const w = Math.min(c.width, ctx.measureText(text).width + 90);
    ctx.fillStyle = 'rgba(8,10,20,0.8)';
    roundRect(ctx, (c.width - w) / 2, 8, w, 80, 40);
    ctx.fill();
    ctx.fillStyle = color;
    ctx.beginPath(); ctx.arc((c.width - w) / 2 + 40, 48, 12, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = '#fff';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText(text, c.width / 2 + 16, 50);
    this.labelTex.needsUpdate = true;
  }
}

function couch(color) {
  const g = new THREE.Group();
  const mat = new THREE.MeshStandardMaterial({ color, roughness: 0.9 });
  const dark = new THREE.MeshStandardMaterial({ color: new THREE.Color(color).multiplyScalar(0.6), roughness: 0.9 });
  const base = new THREE.Mesh(new THREE.BoxGeometry(3.4, 0.42, 0.95), dark);
  base.position.y = 0.21;
  const cushion = new THREE.Mesh(new THREE.BoxGeometry(3.2, 0.14, 0.85), mat);
  cushion.position.set(0, 0.49, -0.02);
  const back = new THREE.Mesh(new THREE.BoxGeometry(3.4, 0.6, 0.22), dark);
  back.position.set(0, 0.72, 0.38);
  const armL = new THREE.Mesh(new THREE.BoxGeometry(0.2, 0.32, 0.95), dark);
  armL.position.set(-1.6, 0.58, 0);
  const armR = armL.clone();
  armR.position.x = 1.6;
  g.add(base, cushion, back, armL, armR);
  for (const m of g.children) { m.castShadow = false; m.receiveShadow = false; }
  return g;
}

export function buildWorld(scene) {
  scene.background = new THREE.Color(0x07080f);
  scene.fog = new THREE.Fog(0x07080f, 18, 40);

  scene.add(new THREE.HemisphereLight(0xb8c0ff, 0x3a2030, 1.6));
  const key = new THREE.PointLight(0xffd7a8, 60, 18, 1.6);
  key.position.set(0, 4.8, 3);
  scene.add(key);
  const fill = new THREE.PointLight(0x8aa8ff, 45, 16, 1.6);
  fill.position.set(0, 4, -5);
  scene.add(fill);
  const sideL = new THREE.PointLight(0xff6fe0, 25, 10, 1.8);
  sideL.position.set(-7, 3, -1);
  const sideR = new THREE.PointLight(0x5fd0ff, 25, 10, 1.8);
  sideR.position.set(7, 3, -1);
  scene.add(sideL, sideR);

  const W = 18, D = 18, H = 6;
  // Boden (Teppich) – dient auch als Teleport-Fläche
  const floor = new THREE.Mesh(new THREE.PlaneGeometry(W, D), new THREE.MeshStandardMaterial({ color: 0x2a2842, roughness: 1 }));
  floor.rotation.x = -Math.PI / 2;
  floor.position.z = -1;
  floor.name = 'floor';
  scene.add(floor);

  const wallMat = new THREE.MeshStandardMaterial({ color: 0x23243f, roughness: 0.95 });
  const mkWall = (w, h, x, y, z, ry) => {
    const m = new THREE.Mesh(new THREE.PlaneGeometry(w, h), wallMat);
    m.position.set(x, y, z);
    m.rotation.y = ry;
    scene.add(m);
  };
  mkWall(W, H, 0, H / 2, -1 - D / 2, 0);
  mkWall(W, H, 0, H / 2, -1 + D / 2, Math.PI);
  mkWall(D, H, -W / 2, H / 2, -1, Math.PI / 2);
  mkWall(D, H, W / 2, H / 2, -1, -Math.PI / 2);
  const ceil = new THREE.Mesh(new THREE.PlaneGeometry(W, D), new THREE.MeshStandardMaterial({ color: 0x0a0b16, roughness: 1 }));
  ceil.rotation.x = Math.PI / 2;
  ceil.position.set(0, H, -1);
  scene.add(ceil);

  // Sternenhimmel an der Decke
  const starGeo = new THREE.BufferGeometry();
  const pts = [];
  for (let i = 0; i < 260; i++) pts.push((Math.random() - 0.5) * (W - 1), H - 0.02, -1 + (Math.random() - 0.5) * (D - 1));
  starGeo.setAttribute('position', new THREE.Float32BufferAttribute(pts, 3));
  scene.add(new THREE.Points(starGeo, new THREE.PointsMaterial({ color: 0xfff3c4, size: 0.05 })));

  // LED-Leisten am Boden
  const ledColors = [0xff4fd8, 0x4fc3f7];
  [[-W / 2 + 0.05, Math.PI / 2], [W / 2 - 0.05, -Math.PI / 2]].forEach(([x], i) => {
    const led = new THREE.Mesh(new THREE.BoxGeometry(0.04, 0.04, D - 0.4), new THREE.MeshBasicMaterial({ color: ledColors[i] }));
    led.position.set(x, 0.05, -1);
    scene.add(led);
  });
  const ledBack = new THREE.Mesh(new THREE.BoxGeometry(W - 0.4, 0.04, 0.04), new THREE.MeshBasicMaterial({ color: 0x9b6bff }));
  ledBack.position.set(0, 0.05, -1 - D / 2 + 0.05);
  scene.add(ledBack);

  // Bühne unter der Leinwand
  const stage = new THREE.Mesh(new THREE.BoxGeometry(11, 0.3, 1.6), new THREE.MeshStandardMaterial({ color: 0x101120, roughness: 0.7 }));
  stage.position.set(0, 0.15, -8.6);
  scene.add(stage);
  const stageLed = new THREE.Mesh(new THREE.BoxGeometry(11, 0.03, 0.03), new THREE.MeshBasicMaterial({ color: 0x4fc3f7 }));
  stageLed.position.set(0, 0.3, -7.8);
  scene.add(stageLed);

  // Leinwände: eine große, vier kleinere an den Seiten
  const main = new Screen(8.4, 'main');
  main.group.position.set(0, 3.0, -8.9);
  scene.add(main.group);

  const sides = [];
  const sideDefs = [
    [-8.0, 2.3, -4.6, 1.15], [8.0, 2.3, -4.6, -1.15],
    [-8.6, 2.3, 0.6, Math.PI / 2], [8.6, 2.3, 0.6, -Math.PI / 2],
  ];
  sideDefs.forEach(([x, y, z, ry], i) => {
    const s = new Screen(3.4, `side${i}`);
    s.group.position.set(x, y, z);
    s.group.rotation.y = ry;
    scene.add(s.group);
    sides.push(s);
  });

  // Sofas in zwei Reihen und Sitzplätze
  const seats = [];
  const rows = [[-2.2, 0x6a3df0], [1.4, 0xd0457a]];
  rows.forEach(([z, color], r) => {
    for (const x of [-2.2, 2.2]) {
      const c = couch(color);
      c.position.set(x, r * 0.35, z);
      if (r === 1) {
        const riser = new THREE.Mesh(new THREE.BoxGeometry(3.8, 0.35, 1.4), new THREE.MeshStandardMaterial({ color: 0x15162a }));
        riser.position.set(x, 0.175, z);
        scene.add(riser);
      }
      scene.add(c);
      for (const dx of [-1, 0, 1]) {
        const pos = new THREE.Vector3(x + dx * 1.05, r * 0.35, z - 0.05);
        // Zur Leinwand-Mitte drehen
        seats.push({ pos, yaw: Math.atan2(-(0 - pos.x), -(-8.9 - pos.z)) });
      }
    }
  });
  // Plätze in der Mitte stehend (z. B. für Spiele)
  seats.push({ pos: new THREE.Vector3(0, 0, -4.2), yaw: 0 });

  // Kleiner Tisch mit Popcorn :)
  const table = new THREE.Mesh(new THREE.CylinderGeometry(0.5, 0.5, 0.05, 24), new THREE.MeshStandardMaterial({ color: 0x2a2440 }));
  table.position.set(0, 0.45, -3.3);
  const leg = new THREE.Mesh(new THREE.CylinderGeometry(0.05, 0.08, 0.45, 8), new THREE.MeshStandardMaterial({ color: 0x1a1628 }));
  leg.position.set(0, 0.22, -3.3);
  const bucket = new THREE.Mesh(new THREE.CylinderGeometry(0.13, 0.1, 0.25, 12, 1, true), new THREE.MeshStandardMaterial({ color: 0xe0303a, side: THREE.DoubleSide }));
  bucket.position.set(0.15, 0.6, -3.3);
  const pop = new THREE.Mesh(new THREE.SphereGeometry(0.13, 10, 6, 0, Math.PI * 2, 0, Math.PI / 2), new THREE.MeshStandardMaterial({ color: 0xfff1b8, roughness: 1 }));
  pop.position.set(0.15, 0.71, -3.3);
  scene.add(table, leg, bucket, pop);

  return { main, sides, screens: [main, ...sides], seats, floor };
}
