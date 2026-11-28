// Schwebendes Bedienfeld in VR: wird auf ein Canvas gezeichnet und mit dem Laserstrahl bedient.
import * as THREE from 'three';
import { roundRect } from './util.js';

const CW = 1024, CH = 860;
const PW = 0.82, PH = PW * (CH / CW);

export class Panel {
  constructor() {
    this.canvas = document.createElement('canvas');
    this.canvas.width = CW;
    this.canvas.height = CH;
    this.ctx = this.canvas.getContext('2d');
    this.tex = new THREE.CanvasTexture(this.canvas);
    this.tex.colorSpace = THREE.SRGBColorSpace;
    this.mesh = new THREE.Mesh(
      new THREE.PlaneGeometry(PW, PH),
      new THREE.MeshBasicMaterial({ map: this.tex, transparent: true, toneMapped: false, depthTest: true }),
    );
    this.mesh.renderOrder = 20;
    this.mesh.userData.panel = this;
    this.mesh.visible = false;
    this.buttons = [];
    this.hover = null;
    this.model = null;

    this.cursor = new THREE.Mesh(new THREE.CircleGeometry(0.008, 16), new THREE.MeshBasicMaterial({ color: 0xffffff, depthTest: false }));
    this.cursor.renderOrder = 21;
    this.cursor.position.z = 0.002;
    this.cursor.visible = false;
    this.mesh.add(this.cursor);
  }

  get visible() { return this.mesh.visible; }

  // Vor dem Kopf aufklappen
  openAt(camera, rig) {
    const pos = new THREE.Vector3(), dir = new THREE.Vector3();
    camera.getWorldPosition(pos);
    camera.getWorldDirection(dir);
    dir.y = 0;
    if (dir.lengthSq() < 1e-4) dir.set(0, 0, -1);
    dir.normalize();
    const p = pos.clone().addScaledVector(dir, 0.65);
    p.y = pos.y - 0.15;
    rig.worldToLocal(p);
    this.mesh.position.copy(p);
    const look = pos.clone();
    look.y = this.mesh.getWorldPosition(new THREE.Vector3()).y;
    this.mesh.lookAt(look);
    this.mesh.visible = true;
  }

  close() { this.mesh.visible = false; this.cursor.visible = false; }

  render(model) {
    this.model = model;
    const ctx = this.ctx;
    ctx.clearRect(0, 0, CW, CH);
    ctx.fillStyle = 'rgba(12,14,30,0.92)';
    roundRect(ctx, 0, 0, CW, CH, 36);
    ctx.fill();
    ctx.strokeStyle = 'rgba(140,150,255,0.5)';
    ctx.lineWidth = 3;
    roundRect(ctx, 2, 2, CW - 4, CH - 4, 34);
    ctx.stroke();

    ctx.textBaseline = 'middle';
    ctx.textAlign = 'left';
    ctx.fillStyle = '#fff';
    ctx.font = '700 40px system-ui, sans-serif';
    ctx.fillText(model.title, 36, 50);
    ctx.font = '400 26px system-ui, sans-serif';
    ctx.fillStyle = '#b8bce6';
    ctx.fillText(model.subtitle || '', 36, 92);

    this.buttons = [];
    let y = 128;
    for (const sec of model.sections) {
      ctx.font = '600 24px system-ui, sans-serif';
      ctx.fillStyle = '#8f95d6';
      ctx.fillText(sec.label, 36, y + 14);
      y += 34;
      let x = 36;
      const bh = 64;
      for (const b of sec.buttons) {
        ctx.font = '600 28px system-ui, "Segoe UI Emoji", "Noto Color Emoji", sans-serif';
        const bw = b.w || Math.min(CW - 72, ctx.measureText(b.text).width + 44);
        if (x + bw > CW - 36) { x = 36; y += bh + 12; }
        const hov = this.hover === b.id && !b.disabled;
        ctx.fillStyle = b.disabled ? 'rgba(255,255,255,0.05)' : b.active ? (hov ? '#7b6bff' : '#5b4bea') : hov ? 'rgba(255,255,255,0.24)' : 'rgba(255,255,255,0.1)';
        roundRect(ctx, x, y, bw, bh, 18);
        ctx.fill();
        ctx.fillStyle = b.disabled ? '#666a8c' : '#fff';
        ctx.textAlign = 'center';
        ctx.fillText(b.text, x + bw / 2, y + bh / 2 + 1, bw - 20);
        ctx.textAlign = 'left';
        this.buttons.push({ ...b, x, y, w: bw, h: bh });
        x += bw + 12;
      }
      y += bh + 18;
    }

    if (model.lines?.length) {
      ctx.font = '400 24px system-ui, sans-serif';
      for (const line of model.lines.slice(-Math.floor((CH - y - 20) / 32))) {
        ctx.fillStyle = line.color || '#d6d8f5';
        ctx.fillText(line.text, 36, y + 12, CW - 72);
        y += 32;
      }
    }
    this.tex.needsUpdate = true;
  }

  _buttonAt(uv) {
    const x = uv.x * CW, y = (1 - uv.y) * CH;
    return this.buttons.find((b) => x >= b.x && x <= b.x + b.w && y >= b.y && y <= b.y + b.h) || null;
  }

  pointAt(uv) {
    if (!uv) { this.cursor.visible = false; this.setHover(null); return null; }
    this.cursor.visible = true;
    this.cursor.position.set((uv.x - 0.5) * PW, (uv.y - 0.5) * PH, 0.002);
    const b = this._buttonAt(uv);
    this.setHover(b && !b.disabled ? b.id : null);
    return b;
  }

  setHover(id) {
    if (this.hover === id) return;
    this.hover = id;
    if (this.model) this.render(this.model);
  }

  click(uv) {
    const b = this._buttonAt(uv);
    return b && !b.disabled ? b : null;
  }
}
