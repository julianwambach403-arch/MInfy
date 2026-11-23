"""
Sternenelf – Bonelab-Avatar-Generator
=====================================

Erzeugt den Charakter aus dem Profilbild (Galaxie-Haut, türkise Haare,
Elfenohren, leuchtende Sternenaugen, mintgrüner Hoodie) komplett per Code:

  * Mesh "Body"  (Körper, Hoodie, Hose, Schuhe, Hände)
  * Mesh "Head"  (Kopf, Augen, Mund, Piercings, Ohren, Haare)
  * Armature im Mixamo-Namensschema (Unity erkennt sie sofort als Humanoid)
  * Texturen (Galaxie, Augen, Haare, Stoffe) als PNG
  * Export: SternenElf.fbx (+ .blend zum Weiterbearbeiten, + Vorschaubilder)

Ausführen:
  blender -b -P generate_avatar.py -- --out export
oder mit dem Python-Modul "bpy":
  python generate_avatar.py --out export
"""

import math
import os
import sys

import bpy  # zuerst importieren (bmesh/mathutils kommen mit bpy)
import bmesh
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

# ---------------------------------------------------------------- Argumente
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
OUT = os.path.abspath(argv[argv.index("--out") + 1]) if "--out" in argv else \
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "export")
RENDER = "--no-render" not in argv
TEX = os.path.join(OUT, "textures")
os.makedirs(TEX, exist_ok=True)

rng = np.random.default_rng(7)
bpy.ops.wm.read_factory_settings(use_empty=True)


# ================================================================ Texturen
def save_png(name, rgba):
    """rgba: (h, w, 4) float 0..1, Zeile 0 = unten (Blender-Konvention)."""
    h, w, _ = rgba.shape
    img = bpy.data.images.new(name, w, h, alpha=True)
    img.pixels.foreach_set(np.clip(rgba, 0, 1).astype(np.float32).ravel())
    path = os.path.join(TEX, name + ".png")
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    return path


def periodic_noise(n, beta, seed):
    """Kachelbares fraktales Rauschen über FFT (nahtlos wiederholbar)."""
    r = np.random.default_rng(seed)
    f = np.fft.fft2(r.normal(size=(n, n)))
    fx = np.fft.fftfreq(n)[:, None]
    fy = np.fft.fftfreq(n)[None, :]
    k = np.sqrt(fx ** 2 + fy ** 2)
    k[0, 0] = 1
    out = np.real(np.fft.ifft2(f / k ** beta))
    return (out - out.min()) / (out.max() - out.min())


def stamp(img, cx, cy, kernel, color):
    """Addiert einen Kernel mit Wrap-around (für kachelbare Sterne)."""
    n = img.shape[0]
    kh, kw = kernel.shape
    ys = (np.arange(kh) - kh // 2 + cy) % n
    xs = (np.arange(kw) - kw // 2 + cx) % n
    img[np.ix_(ys, xs, [0, 1, 2])] += kernel[:, :, None] * np.array(color)[None, None, :]


def galaxy_texture(n=1024):
    a = periodic_noise(n, 1.6, 1)
    b = periodic_noise(n, 1.4, 2)
    c = periodic_noise(n, 1.8, 3)
    col = np.zeros((n, n, 3))
    col[:] = (0.07, 0.08, 0.32)                                    # tiefes Nachtblau
    col += np.array((0.16, 0.22, 0.65)) * (c ** 1.5)[..., None]    # Blau
    col += np.array((0.35, 0.12, 0.55)) * (np.clip(a - 0.45, 0, 1) * 1.8)[..., None]  # Violett
    col += np.array((0.10, 0.62, 0.70)) * (np.clip(b - 0.55, 0, 1) * 2.2)[..., None]  # Türkis-Nebel
    stars = np.zeros((n, n, 3))
    # winzige Sterne
    for _ in range(2600):
        x, y = rng.integers(0, n, 2)
        stars[y, x] += rng.uniform(0.4, 1.0)
    # weiche Sterne
    yy, xx = np.mgrid[-4:5, -4:5]
    for _ in range(140):
        s = rng.uniform(0.8, 1.8)
        stamp(stars, *rng.integers(0, n, 2), np.exp(-(xx ** 2 + yy ** 2) / (2 * s * s)),
              (0.9, 0.95, 1.0))
    # Funkel-Sterne (4 Zacken, wie im Bild)
    yy, xx = np.mgrid[-14:15, -14:15]
    for _ in range(45):
        L = rng.uniform(6, 13)
        k = (np.exp(-np.abs(xx) / 0.9) * np.exp(-np.abs(yy) / L * 3) +
             np.exp(-np.abs(yy) / 0.9) * np.exp(-np.abs(xx) / L * 3))
        k += 1.5 * np.exp(-(xx ** 2 + yy ** 2) / 3.0)
        stamp(stars, *rng.integers(0, n, 2), np.clip(k, 0, 1.6),
              (1.0, 0.97, 0.85) if rng.random() < 0.5 else (0.75, 0.95, 1.0))
    col = col + stars
    rgba = np.concatenate([col, np.ones((n, n, 1))], axis=2)
    emis = np.concatenate([np.clip(stars, 0, 1) + col * 0.15, np.ones((n, n, 1))], axis=2)
    return save_png("galaxy_skin", rgba), save_png("galaxy_skin_emission", emis)


# Augenform (gemeinsam für Textur und Mesh). u: -1 innen .. +1 außen
def lid_top(u):
    return 0.55 * np.sqrt(np.clip(1 - u * u, 0, 1)) + 0.12 * u + 0.12


def lid_bot(u):
    return -0.80 * np.clip(1 - u * u, 0, 1) ** 0.7 + 0.12 * u + 0.12


def eye_texture(n=512):
    v, u = np.mgrid[-1:1:n * 1j, -1:1:n * 1j]
    col = np.zeros((n, n, 3))
    col[:] = (1.0, 0.96, 0.86)                                     # Augenweiß (cremig)
    r = np.sqrt(u ** 2 + ((v + 0.05) / 1.05) ** 2)
    iris = r < 0.66
    g = np.clip(r / 0.66, 0, 1)[..., None]
    gold_in, gold_out = np.array((1.0, 0.86, 0.45)), np.array((0.80, 0.50, 0.10))
    col = np.where(iris[..., None], gold_in * (1 - g) + gold_out * g, col)
    ring = (r > 0.60) & (r < 0.68)
    col[ring] = (0.45, 0.25, 0.05)
    # 4-zackiger Stern als Pupille
    su, sv = np.abs(u) / 0.42, np.abs(v + 0.05) / 0.68
    star = (su ** 0.55 + sv ** 0.55) < 1.0
    glow = np.exp(-(u ** 2 + (v + 0.05) ** 2) / 0.05)[..., None]
    col = col + glow * np.array((0.6, 0.45, 0.1))
    col[star] = (1.0, 0.98, 0.80)
    outline = ((su ** 0.55 + sv ** 0.55) < 1.15) & ~star
    col[outline] = (0.35, 0.20, 0.02)
    # Wimpernlinie oben + feine Linie unten
    top, bot = lid_top(u), lid_bot(u)
    col[v > top - 0.20] = (0.04, 0.03, 0.06)
    col[v < bot + 0.06] = (0.35, 0.22, 0.20)
    rgba = np.concatenate([col, np.ones((n, n, 1))], axis=2)
    em = np.zeros_like(rgba)
    em[..., :3] = np.where(iris[..., None], col * 0.9, 0.0) + glow * 0.4
    em[..., 3] = 1
    return save_png("eyes", rgba), save_png("eyes_emission", em)


def hair_texture(w=512, h=512):
    """Matte Anime-Haare: feine Strähnenlinien, dunkler Ansatz, gemalter Glanzring."""
    v, u = np.mgrid[0:1:h * 1j, 0:1:w * 1j]              # v = 0 Ansatz .. 1 Spitze
    dark, mid, light = np.array((0.03, 0.36, 0.45)), np.array((0.09, 0.68, 0.68)), \
        np.array((0.55, 0.93, 0.86))
    t = np.clip(v * 1.6, 0, 1)[..., None] ** 0.8
    col = dark * (1 - t) + mid * t
    # feine Strähnen: mehrere Frequenzen quer zur Haarrichtung (kachelbar in u)
    lines = np.zeros(w)
    for f, a in ((4, 0.5), (11, 0.3), (29, 0.25), (67, 0.15)):
        ph = rng.uniform(0, 2 * np.pi, 3)
        x = np.linspace(0, 2 * np.pi, w, endpoint=False)
        lines += a * np.sin(f * x + ph[0] + 0.6 * np.sin(3 * x + ph[1]))
    lines = (lines - lines.min()) / (lines.max() - lines.min())
    col = col * (0.72 + 0.4 * lines[None, :, None])
    # Glanzring mit gezackter Kante, nur auf "erhobenen" Strähnen
    edge = 0.30 + 0.012 * np.sin(np.linspace(0, 2 * np.pi * 3, w))[None, :]
    band = (np.abs(v - edge) < 0.02 * lines[None, :]) & (lines[None, :] > 0.5)
    col[band] = col[band] * 0.35 + light * 0.65
    # dunkle Linien zwischen Strähnen (gibt Tiefe statt Plastik-Glanz)
    col = col * np.where(lines[None, :, None] < 0.12, 0.6, 1.0)
    tip = np.clip((v - 0.8) / 0.2, 0, 1)[..., None] * 0.35
    col = col * (1 - tip) + light * tip                                   # helle Spitzen
    return save_png("hair", np.concatenate([col, np.ones((h, w, 1))], axis=2))


def cloth_texture(name, base, noise_amt=0.06, n=256, seed=11):
    nz = periodic_noise(n, 0.6, seed)[..., None]
    col = np.array(base)[None, None, :] * (1 - noise_amt + 2 * noise_amt * nz)
    return save_png(name, np.concatenate([col, np.ones((n, n, 1))], axis=2))


print("Erzeuge Texturen …")
GAL, GAL_E = galaxy_texture()
EYE, EYE_E = eye_texture()
HAIR = hair_texture()
HOODIE = cloth_texture("hoodie", (0.62, 0.92, 0.78))
TRIM = cloth_texture("hoodie_trim", (0.86, 0.95, 0.62))
PANTS = cloth_texture("pants", (0.16, 0.17, 0.36), 0.1)
SHOES = cloth_texture("shoes", (0.93, 0.95, 0.95), 0.03)
DARK = cloth_texture("dark", (0.03, 0.02, 0.05), 0.0)
ZIP = cloth_texture("zipper", (0.80, 0.90, 0.80), 0.0)


# ================================================================ Materialien
def material(name, tex, emission=None, strength=1.0, rough=0.65):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = bpy.data.images.load(tex)
    nt.links.new(t.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = rough
    if emission:
        e = nt.nodes.new("ShaderNodeTexImage")
        e.image = bpy.data.images.load(emission)
        nt.links.new(e.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = strength
    return m


def outline_material():
    """Inverted-Hull-Kontur: nur die nach außen gedrehten Rückseiten sind sichtbar.
    In Unity reicht dafür ein schwarzes URP/Unlit-Material (Backface-Culling ist Standard)."""
    m = bpy.data.materials.new("Outline")
    m.use_backface_culling = True
    m.diffuse_color = (0.02, 0.05, 0.08, 1)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    mix = nt.nodes.new("ShaderNodeMixShader")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (0.02, 0.05, 0.08, 1)
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    nt.links.new(geo.outputs["Backfacing"], mix.inputs[0])
    nt.links.new(em.outputs[0], mix.inputs[1])
    nt.links.new(tr.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs["Surface"])
    return m


MATS = {
    "Skin_Galaxy": material("Skin_Galaxy", GAL, GAL_E, 0.6, 0.6),
    "Eyes": material("Eyes", EYE, EYE_E, 2.5, 0.3),
    "Hair": material("Hair", HAIR, rough=0.8),
    "Hoodie": material("Hoodie", HOODIE, rough=0.9),
    "Hoodie_Trim": material("Hoodie_Trim", TRIM, rough=0.9),
    "Pants": material("Pants", PANTS, rough=0.9),
    "Shoes": material("Shoes", SHOES, rough=0.6),
    "Dark": material("Dark", DARK, rough=0.5),
    "Zipper": material("Zipper", ZIP, rough=0.3),
    "Outline": outline_material(),
}
OUTLINE = "--no-outline" not in argv


# ================================================================ Skelett
def mirror_name(s):
    return "Left" if s > 0 else "Right"


BONES = {  # name: (head, tail, parent)
    "Hips": ((0, 0, 0.93), (0, 0, 1.05), None),
    "Spine": ((0, 0, 1.05), (0, 0, 1.20), "Hips"),
    "Spine1": ((0, 0, 1.20), (0, 0, 1.33), "Spine"),
    "Spine2": ((0, 0, 1.33), (0, 0, 1.45), "Spine1"),
    "Neck": ((0, 0, 1.45), (0, 0, 1.55), "Spine2"),
    "Head": ((0, 0, 1.55), (0, 0, 1.78), "Neck"),
}
FINGERS = {"Index": -0.024, "Middle": -0.008, "Ring": 0.008, "Pinky": 0.024}
for s in (1, -1):
    S = mirror_name(s)
    BONES[S + "Shoulder"] = ((s * 0.03, 0, 1.40), (s * 0.15, 0, 1.41), "Spine2")
    BONES[S + "Arm"] = ((s * 0.15, 0, 1.41), (s * 0.44, 0, 1.41), S + "Shoulder")
    BONES[S + "ForeArm"] = ((s * 0.44, 0, 1.41), (s * 0.69, 0, 1.41), S + "Arm")
    BONES[S + "Hand"] = ((s * 0.69, 0, 1.41), (s * 0.79, 0, 1.41), S + "ForeArm")
    th = [(s * 0.725, -0.025, 1.400), (s * 0.750, -0.050, 1.395),
          (s * 0.770, -0.065, 1.390), (s * 0.790, -0.075, 1.388)]
    for i in range(3):
        BONES[f"{S}HandThumb{i + 1}"] = (th[i], th[i + 1],
                                         S + "Hand" if i == 0 else f"{S}HandThumb{i}")
    for f, y in FINGERS.items():
        k = 0.8 if f == "Pinky" else 1.0
        x = 0.79
        for i, ln in enumerate((0.030, 0.022, 0.018)):
            BONES[f"{S}Hand{f}{i + 1}"] = ((s * x, y, 1.41), (s * (x + ln * k), y, 1.41),
                                           S + "Hand" if i == 0 else f"{S}Hand{f}{i}")
            x += ln * k
    BONES[S + "UpLeg"] = ((s * 0.09, 0, 0.92), (s * 0.09, 0, 0.50), "Hips")
    BONES[S + "Leg"] = ((s * 0.09, 0, 0.50), (s * 0.09, 0.01, 0.09), S + "UpLeg")
    BONES[S + "Foot"] = ((s * 0.09, 0.01, 0.09), (s * 0.09, -0.10, 0.03), S + "Leg")
    BONES[S + "ToeBase"] = ((s * 0.09, -0.10, 0.03), (s * 0.09, -0.17, 0.03), S + "Foot")

arm_data = bpy.data.armatures.new("SternenElf_Rig")
rig = bpy.data.objects.new("SternenElf_Rig", arm_data)
bpy.context.scene.collection.objects.link(rig)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode="EDIT")
for name, (h, t, p) in BONES.items():
    b = arm_data.edit_bones.new(name)
    b.head, b.tail = h, t
    if p:
        b.parent = arm_data.edit_bones[p]
        b.use_connect = (Vector(arm_data.edit_bones[p].tail) - Vector(h)).length < 1e-4
bpy.ops.object.mode_set(mode="OBJECT")

SEG_NAMES = list(BONES)
SEG_A = np.array([BONES[n][0] for n in SEG_NAMES], float)
SEG_B = np.array([BONES[n][1] for n in SEG_NAMES], float)


def seg_dist(P, A, B):
    AB = B - A
    t = np.einsum("nmk,mk->nm", P[:, None, :] - A[None], AB) / np.einsum("mk,mk->m", AB, AB)
    t = np.clip(t, 0, 1)
    C = A[None] + t[..., None] * AB[None]
    return np.linalg.norm(P[:, None, :] - C, axis=2), t


def skin_weights(obj, allowed=None):
    """Weiche Gewichte über den Abstand zu den Knochen-Segmenten (max. 3 Einflüsse)."""
    idx = [i for i, n in enumerate(SEG_NAMES) if allowed is None or n in allowed]
    P = np.array([v.co[:] for v in obj.data.vertices])
    d, _ = seg_dist(P, SEG_A[idx], SEG_B[idx])
    w = 1.0 / (d ** 4 + 1e-9)
    top = np.argsort(-w, axis=1)[:, :3]
    groups = {}
    for vi in range(len(P)):
        ws = w[vi, top[vi]]
        ws = ws / ws.sum()
        for j, wj in zip(top[vi], ws):
            if wj < 0.02:
                continue
            name = SEG_NAMES[idx[j]]
            if name not in groups:
                groups[name] = obj.vertex_groups.new(name=name)
            groups[name].add([vi], float(wj), "REPLACE")


def bind(obj):
    obj.parent = rig
    mod = obj.modifiers.new("Armature", "ARMATURE")
    mod.object = rig


# ================================================================ Mesh-Baukasten
class Builder:
    def __init__(self):
        self.v, self.f, self.mat, self.uv = [], [], [], []
        self.vg, self.vt = [], []      # Haar-Gruppe und Position entlang der Strähne (0..1)

    def add(self, verts, faces, mat, uvs=None, group=None, vt=None):
        o = len(self.v)
        self.v += [tuple(p) for p in verts]
        self.vg += [group] * len(verts)
        self.vt += list(vt) if vt is not None else [0.0] * len(verts)
        for i, f in enumerate(faces):
            self.f.append(tuple(o + k for k in f))
            self.mat.append(mat)
            self.uv.append(uvs[i] if uvs else None)

    def into_bmesh(self, bm, mat_names):
        bv = [bm.verts.new(p) for p in self.v]
        bm.verts.ensure_lookup_table()
        uvl = bm.loops.layers.uv.verify()
        box = bm.faces.layers.int.get("box") or bm.faces.layers.int.new("box")
        for f, m, uv in zip(self.f, self.mat, self.uv):
            try:
                face = bm.faces.new([bv[i] for i in f])
            except ValueError:
                continue
            face.material_index = mat_names.index(m)
            face.smooth = True
            if uv:
                for loop, c in zip(face.loops, uv):
                    loop[uvl].uv = c
            else:
                face[box] = 1     # später Box-Projektion


def fix_normals(bm):
    """Alle Normalen nach außen (wichtig: Unity rendert nur Vorderseiten)."""
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    eye = MAT_ORDER.index("Eyes")
    for f in bm.faces:
        f.normal_update()
        if f.material_index == eye and f.normal.y > 0:
            f.normal_flip()


NO_OUTLINE = ("Eyes", "Dark", "Zipper", "Outline")


def add_outline(bm, width):
    """Hängt eine leicht vergrößerte Hülle mit umgedrehten Flächen an (Anime-Kontur).
    Gibt für jeden neuen Vertex den Index des Original-Vertex zurück (für die Gewichte)."""
    if not OUTLINE:
        return []
    skip = {MAT_ORDER.index(m) for m in NO_OUTLINE}
    bm.normal_update()
    bm.verts.index_update()
    bm.verts.ensure_lookup_table()
    faces = [f for f in bm.faces if f.material_index not in skip]
    verts = sorted({v for f in faces for v in f.verts}, key=lambda v: v.index)
    new = {}
    src = []
    for v in verts:
        src.append(v.index)
        new[v.index] = bm.verts.new(v.co + v.normal * width)
    om = MAT_ORDER.index("Outline")
    for f in faces:
        try:
            nf = bm.faces.new([new[v.index] for v in reversed(f.verts)])
        except ValueError:
            continue
        nf.material_index = om
        nf.smooth = True
    bm.verts.index_update()
    return src


def box_uv(bm, scale=3.0, only_tagged=True):
    uvl = bm.loops.layers.uv.verify()
    box = bm.faces.layers.int.get("box")
    bm.normal_update()
    for f in bm.faces:
        if only_tagged and not f[box]:
            continue
        n = f.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        a, b = [(1, 2), (0, 2), (0, 1)][ax]
        for loop in f.loops:
            co = loop.vert.co
            loop[uvl].uv = (co[a] * scale, co[b] * scale)


def ellipsoid(center, radii, nu=48, nv=32, shape=None, keep=None):
    """Gibt verts, faces zurück. shape(p_norm) -> p_norm verändert; keep(p_norm) filtert."""
    verts, idx = [], {}
    for j in range(1, nv):
        el = math.pi / 2 - math.pi * j / nv
        for i in range(nu):
            az = 2 * math.pi * i / nu
            p = np.array((math.cos(el) * math.sin(az), -math.cos(el) * math.cos(az), math.sin(el)))
            idx[(i, j)] = len(verts)
            verts.append(p)
    top, bot = len(verts), len(verts) + 1
    verts += [np.array((0, 0, 1.0)), np.array((0, 0, -1.0))]
    faces = []
    for i in range(nu):
        i2 = (i + 1) % nu
        faces.append((top, idx[(i, 1)], idx[(i2, 1)])[::-1])
        faces.append((bot, idx[(i2, nv - 1)], idx[(i, nv - 1)])[::-1])
        for j in range(1, nv - 1):
            faces.append((idx[(i, j)], idx[(i, j + 1)], idx[(i2, j + 1)], idx[(i2, j)])[::-1])
    out = []
    for p in verts:
        q = shape(p.copy()) if shape else p.copy()
        out.append(np.array(center) + q * np.array(radii))
    if keep:
        ok = [keep(p) for p in verts]
        faces = [f for f in faces if all(ok[k] for k in f)]
    return out, faces


def catmull(pts, n):
    P = [np.array(pts[0]) * 2 - np.array(pts[1])] + [np.array(p) for p in pts] + \
        [np.array(pts[-1]) * 2 - np.array(pts[-2])]
    out = []
    segs = len(pts) - 1
    for k in range(n + 1):
        x = k / n * segs
        i = min(int(x), segs - 1)
        t = x - i
        p0, p1, p2, p3 = P[i], P[i + 1], P[i + 2], P[i + 3]
        out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t +
                          (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    return out


CHAIN_BONES = {}   # Gruppe -> Anzahl Knochen
CHAIN_PATHS = {}   # Gruppe -> Liste der Mittellinien aller Strähnen dieser Gruppe


def strand(B, pts, width, thick, nrm, mat, seg=14, ring=6, taper=1.0, uv=True, group=None):
    """Spitz zulaufende, flache Haarsträhne (oder Ohr) entlang der Punkte.
    group: Name der Knochenkette, an der die Strähne hängt (None = fest am Kopf)."""
    C = catmull(pts, seg)
    if group:
        CHAIN_PATHS.setdefault(group, []).append(np.array(C))
    nrm = np.array(nrm, float)
    verts, faces, uvs = [], [], []
    for k, p in enumerate(C[:-1]):
        t = k / seg
        T = C[k + 1] - (C[k - 1] if k else p)
        T /= np.linalg.norm(T)
        S = np.cross(T, nrm)
        if np.linalg.norm(S) < 1e-6:
            S = np.cross(T, (0, 0, 1))
        S /= np.linalg.norm(S)
        N = np.cross(S, T)
        w = width * (1 - t) ** taper * (0.75 + 0.25 * min(1, t * 5))
        h = thick * (1 - t) ** taper * (0.75 + 0.25 * min(1, t * 5))
        for r in range(ring):
            a = 2 * math.pi * r / ring
            verts.append(p + S * math.cos(a) * w + N * math.sin(a) * h)
    tip = len(verts)
    verts.append(C[-1])
    rows = seg
    for k in range(rows - 1):
        for r in range(ring):
            r2 = (r + 1) % ring
            faces.append((k * ring + r, k * ring + r2, (k + 1) * ring + r2, (k + 1) * ring + r))
            uvs.append([(r / ring, k / seg), ((r + 1) / ring, k / seg),
                        ((r + 1) / ring, (k + 1) / seg), (r / ring, (k + 1) / seg)])
    last = (rows - 1) * ring
    for r in range(ring):
        faces.append((last + r, last + (r + 1) % ring, tip))
        uvs.append([(r / ring, (rows - 1) / seg), ((r + 1) / ring, (rows - 1) / seg),
                    ((r + 0.5) / ring, 1.0)])
    faces.append(tuple(range(ring))[::-1])
    uvs.append([(0.5, 0.0)] * ring)
    vt = [k / seg for k in range(seg) for _ in range(ring)] + [1.0]
    B.add(verts, faces, mat, uvs if uv else None, group=group, vt=vt)


# ================================================================ Kopf
HC = np.array((0.0, -0.005, 1.63))          # Kopfmitte
HR = np.array((0.115, 0.12, 0.13))          # Kopfradien


def head_shape(p):
    x, y, z = p
    if z < 0:
        t = -z
        x *= 1 - 0.45 * t * t                          # spitzes Anime-Kinn
        if y < 0:
            y -= 0.08 * t * (-y)
        z *= 1 + 0.08 * t
    if y < 0:                                          # kleine Nase
        y -= 0.10 * math.exp(-((x / 0.15) ** 2 + ((z + 0.27) / 0.13) ** 2))
    return np.array((x, y, z))


head = Builder()
hv, hf = ellipsoid(HC, HR, 64, 40, head_shape)
head.add(hv, hf, "Skin_Galaxy")
head_bvh = BVHTree.FromPolygons([tuple(v) for v in hv], hf)


def on_face(x, z, off=0.0015):
    hit, nrm, _, _ = head_bvh.ray_cast(Vector((x, -1.0, z)), Vector((0, 1, 0)))
    if nrm.y > 0:                     # Normale Richtung Betrachter drehen
        nrm = -nrm
    return np.array(hit + nrm * off), np.array(nrm)


# Augen
for s in (1, -1):
    cx, cz, hw, hh = s * 0.049, 1.630, 0.036, 0.026
    nu_, nv_ = 20, 10
    verts, uvs_v = [], []
    for i in range(nu_ + 1):
        u = -0.999 + 1.998 * i / nu_
        for j in range(nv_ + 1):
            v = lid_bot(u) + (lid_top(u) - lid_bot(u)) * j / nv_
            p, _ = on_face(cx + s * u * hw, cz + v * hh)
            verts.append(p)
            uvs_v.append(((u + 1) / 2, (v + 1) / 2))
    faces, uvs = [], []
    for i in range(nu_):
        for j in range(nv_):
            a, b = i * (nv_ + 1) + j, (i + 1) * (nv_ + 1) + j
            f = (a, b, b + 1, a + 1) if s < 0 else (a, a + 1, b + 1, b)
            faces.append(f)
            uvs.append([uvs_v[k] for k in f])
    head.add(verts, faces, "Eyes", uvs)

# Mund (leichtes, schiefes Lächeln) und Kinn-Piercings
mouth = [on_face(x, 1.568 + 0.010 * ((x - 0.004) / 0.03) ** 2 + 0.002 * x / 0.03, 0.002)[0]
         for x in np.linspace(-0.028, 0.034, 7)]
strand(head, mouth, 0.0028, 0.0028, (0, -1, 0), "Dark", seg=16, taper=0.15)
for x, z in ((-0.016, 1.546), (0.024, 1.541)):
    p, n = on_face(x, z, 0.002)
    dv, df = ellipsoid(p, (0.0045, 0.0045, 0.0045), 10, 6)
    head.add(dv, df, "Dark")

# Elfenohren (lang, spitz, Galaxie-Haut)
for s in (1, -1):
    strand(head, [(s * 0.100, 0.015, 1.612), (s * 0.170, 0.030, 1.640),
                  (s * 0.250, 0.045, 1.690), (s * 0.325, 0.055, 1.735)],
           0.062, 0.013, (0, -1, 0.25), "Skin_Galaxy", seg=16, ring=8, taper=1.1, uv=False,
           group="Ear_L" if s > 0 else "Ear_R")
CHAIN_BONES.update(Ear_L=2, Ear_R=2)


# ================================================================ Haare
def sp(az_deg, el_deg, k=1.0):
    az, el = math.radians(az_deg), math.radians(el_deg)
    d = np.array((math.cos(el) * math.sin(az), -math.cos(el) * math.cos(az), math.sin(el)))
    return HC + d * HR * k, d


def cap_keep(p):
    return p[2] > 0.30 * (-p[1]) - 0.08 + (0.25 if p[1] < -0.6 and p[2] < 0.55 else 0)


hair = Builder()
cv, cf = ellipsoid(HC + np.array((0, 0.004, 0.006)), HR * 1.07, 48, 32, keep=cap_keep)
hair.add(cv, cf, "Hair", [[(0.5, 0.1)] * len(f) for f in cf])

R = np.random.default_rng(3)

# Krone / oberste Lage – wirr, in alle Richtungen
for az in range(0, 360, 24):
    a = az + R.uniform(-8, 8)
    p1, d1 = sp(a, 82, 1.06)
    p2, _ = sp(a, 55, 1.13)
    p3, _ = sp(a, 30 - R.uniform(0, 10), 1.20)
    out = np.array((math.sin(math.radians(a)), -math.cos(math.radians(a)), 0))
    if -50 < ((a + 180) % 360) - 180 < 50:      # vorne: in den Pony übergehen lassen
        continue
    tip = p3 + out * R.uniform(0.03, 0.07) + np.array((0, 0, -0.02))
    strand(hair, [p1, p2, p3, tip], 0.065, 0.016, d1, "Hair", taper=0.9)

# Pony (über Stirn und teils über die Augen)
bangs = [(-0.088, 1.610), (-0.058, 1.668), (-0.030, 1.680), (0.006, 1.612),
         (0.034, 1.684), (0.062, 1.670), (0.090, 1.615)]
for x, zt in bangs:
    root, d = sp(x * 300, 62, 1.02)
    mid = np.array((x * 1.05, -0.112, 1.735))
    tip = np.array((x * 1.18 + 0.008, -0.142, zt))
    lo = np.array((x * 1.12 + 0.004, -0.137, (mid[2] + zt) / 2 + 0.01))
    g = "Bangs_R" if x < -0.045 else "Bangs_L" if x > 0.045 else "Bangs_C"
    strand(hair, [root, mid, lo, tip], 0.034, 0.008, (0, -1, 0.3), "Hair", taper=1.0, group=g)
CHAIN_BONES.update(Bangs_L=2, Bangs_C=2, Bangs_R=2)

# Seitliche, abstehende Strähnen (wie im Bild auf Höhe der Ohren/Wangen)
for layer, (el, drop) in enumerate(((22, -0.03), (0, -0.06))):
    for az in (64, 88, 115, 145, 175, 205, 235, 262, 288):
        a = az + R.uniform(-6, 6) + layer * 7
        root, d = sp(a, el, 1.0)
        out = np.array((math.sin(math.radians(a)), -math.cos(math.radians(a)), 0))
        L = R.uniform(0.11, 0.16) * (0.75 if 140 < a < 220 else 1.0)
        pts = [root, root + out * L * 0.45 + (0, 0, drop * 0.5),
               root + out * L * 0.85 + (0, 0, drop), root + out * L + (0, 0, drop + 0.015)]
        g = "Side_L" if a < 130 else "Side_R" if a > 230 else "Side_Back"
        strand(hair, pts, 0.085, 0.022, np.array((0, 0, 1.0)) * 0.6 + out * 0.4, "Hair",
               ring=8, taper=1.1, group=g)
CHAIN_BONES.update(Side_L=2, Side_R=2, Side_Back=2)

# Lange Strähnen, die das Gesicht einrahmen (bis zur Brust)
for s in (1, -1):
    for dx, zt, w in ((0.0, 1.34, 0.040), (0.03, 1.40, 0.045), (-0.015, 1.47, 0.032)):
        root, _ = sp(s * 42, 38, 1.04)
        pts = [root, np.array((s * (0.112 + dx), -0.105, 1.63)),
               np.array((s * (0.110 + dx), -0.085, 1.50)),
               np.array((s * (0.098 + dx), -0.070, zt))]
        strand(hair, pts, w, 0.010, (s * 0.4, -1, 0), "Hair", seg=18, taper=0.9,
               group="Front_L" if s > 0 else "Front_R")
CHAIN_BONES.update(Front_L=3, Front_R=3)

# Hinterkopf / Nacken
for az in range(120, 250, 16):
    root, d = sp(az, -5, 1.02)
    out = np.array((math.sin(math.radians(az)), -math.cos(math.radians(az)), 0))
    pts = [root, root + out * 0.04 + (0, 0, -0.07), root + out * 0.07 + (0, 0, -0.14)]
    strand(hair, pts, 0.06, 0.015, out, "Hair", taper=0.9,
           group="Nape_L" if az < 185 else "Nape_R")
CHAIN_BONES.update(Nape_L=2, Nape_R=2)

# Antenne / Ahoge
strand(hair, [(0.005, 0.005, 1.765), (0.0, 0.0, 1.85), (0.03, 0.005, 1.915),
              (0.085, 0.010, 1.905), (0.11, 0.012, 1.86)],
       0.028, 0.007, (0, -1, 0), "Hair", seg=18, taper=0.9, group="Ahoge")
CHAIN_BONES["Ahoge"] = 3


# ================================================================ Haar-Rig
def chain_bone(g, k):
    return f"{g}_{k + 1}" if g.startswith("Ear") else f"Hair_{g}_{k + 1}"


bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode="EDIT")
for g, n in CHAIN_BONES.items():
    paths = CHAIN_PATHS[g]
    m = min(len(p) for p in paths)
    avg = np.mean([p[np.linspace(0, len(p) - 1, m).round().astype(int)] for p in paths], axis=0)
    parent = arm_data.edit_bones["Head"]
    for k in range(n):
        a = avg[round(k / n * (m - 1))]
        b = avg[round((k + 1) / n * (m - 1))]
        eb = arm_data.edit_bones.new(chain_bone(g, k))
        eb.head, eb.tail = Vector(a), Vector(b)
        eb.parent = parent
        eb.use_connect = k > 0
        parent = eb
bpy.ops.object.mode_set(mode="OBJECT")
print("Haar-/Ohr-Knochen:", sum(CHAIN_BONES.values()))


def chain_weights(obj, B, src):
    """Gewichte entlang der Strähne: Wurzel am Kopf, dann Knochen für Knochen weich überblendet."""
    vg, vt = list(B.vg), list(B.vt)
    for i in src:                         # Kontur-Hülle erbt die Gewichte des Originals
        vg.append(vg[i])
        vt.append(vt[i])
    groups = {}

    def add(name, idx, w):
        if name not in groups:
            groups[name] = obj.vertex_groups.new(name=name)
        groups[name].add([idx], w, "REPLACE")

    for i, (g, t) in enumerate(zip(vg, vt)):
        if g is None:
            add("Head", i, 1.0)
            continue
        n = CHAIN_BONES[g]
        x = t * n
        k = min(int(x), n - 1)
        f = x - k
        ws = {chain_bone(g, k): 1.0}
        if f < 0.25:
            ws["Head" if k == 0 else chain_bone(g, k - 1)] = (0.25 - f) / 0.5
        elif f > 0.75 and k < n - 1:
            ws[chain_bone(g, k + 1)] = (f - 0.75) / 0.5
        tot = sum(ws.values())
        for name, w in ws.items():
            add(name, i, w / tot)


# ================================================================ Körper (Skin-Modifier)
SV = []      # (pos, radius)
SE = []


def sv(p, r):
    SV.append((p, r))
    return len(SV) - 1


pelvis = sv((0, 0, 0.90), (0.15, 0.11))
waist = sv((0, 0, 1.05), (0.155, 0.115))
chest = sv((0, 0, 1.22), (0.165, 0.115))
upper = sv((0, 0, 1.36), (0.17, 0.11))
neck0 = sv((0, 0, 1.45), (0.05, 0.05))
neck1 = sv((0, 0, 1.56), (0.045, 0.045))
SE += [(pelvis, waist), (waist, chest), (chest, upper), (upper, neck0), (neck0, neck1)]
for s in (1, -1):
    sh = sv((s * 0.17, 0, 1.40), (0.072, 0.072))
    el = sv((s * 0.44, 0, 1.41), (0.060, 0.060))
    wr = sv((s * 0.665, 0, 1.41), (0.056, 0.056))
    wr2 = sv((s * 0.70, 0, 1.41), (0.028, 0.028))
    palm = sv((s * 0.755, 0, 1.41), (0.030, 0.030))
    SE += [(upper, sh), (sh, el), (el, wr), (wr, wr2), (wr2, palm)]
    prev = palm
    th = [BONES[f"{mirror_name(s)}HandThumb{i}"] for i in (1, 2, 3)]
    pts = [th[0][0], th[1][0], th[2][0], th[2][1]]
    for k, p in enumerate(pts):
        n = sv(p, (0.013 - 0.001 * k, 0.013 - 0.001 * k))
        SE.append((prev, n))
        prev = n
    for f in FINGERS:
        bones = [BONES[f"{mirror_name(s)}Hand{f}{i}"] for i in (1, 2, 3)]
        prev = palm
        pts = [bones[0][0], bones[1][0], bones[2][0], bones[2][1]]
        for k, p in enumerate(pts):
            r = (0.0105 - 0.0012 * k) * (0.85 if f == "Pinky" else 1.0)
            n = sv(p, (r, r))
            SE.append((prev, n))
            prev = n
    hip = sv((s * 0.09, 0, 0.88), (0.088, 0.088))
    knee = sv((s * 0.09, 0, 0.50), (0.066, 0.066))
    ank = sv((s * 0.09, 0.01, 0.10), (0.052, 0.052))
    foot = sv((s * 0.09, -0.08, 0.045), (0.052, 0.045))
    toe = sv((s * 0.09, -0.175, 0.04), (0.042, 0.035))
    SE += [(pelvis, hip), (hip, knee), (knee, ank), (ank, foot), (foot, toe)]

skel_me = bpy.data.meshes.new("body_skel")
skel_me.from_pydata([p for p, _ in SV], SE, [])
skel = bpy.data.objects.new("body_skel", skel_me)
bpy.context.scene.collection.objects.link(skel)
skin = skel.modifiers.new("Skin", "SKIN")
skin.use_smooth_shade = True
for i, (_, r) in enumerate(SV):
    skel_me.skin_vertices[0].data[i].radius = r
skel_me.skin_vertices[0].data[pelvis].use_root = True
sub = skel.modifiers.new("Sub", "SUBSURF")
sub.levels = sub.render_levels = 2
dg = bpy.context.evaluated_depsgraph_get()
body_me = bpy.data.meshes.new_from_object(skel.evaluated_get(dg))
bpy.data.objects.remove(skel)

bm = bmesh.new()
bm.from_mesh(body_me)
MAT_ORDER = list(MATS)
BOX = bm.faces.layers.int.new("box")

# V-Ausschnitt sauber in die Brust schneiden (statt grober Flächenkanten)
for s in (1, -1):
    front = [f for f in bm.faces if f.calc_center_median().y < 0.0 and
             1.15 < f.calc_center_median().z < 1.52 and abs(f.calc_center_median().x) < 0.2]
    geom = list({e for f in front for e in f.edges} | {v for f in front for v in f.verts}) + front
    bmesh.ops.bisect_plane(bm, geom=geom, dist=1e-5, plane_co=(s * 0.012, 0, 1.27),
                           plane_no=Vector((s * 1.0, 0, -0.55)).normalized())
# saubere Kanten für Bündchen (Hüfte, Ärmel)
for co, no in [((0, 0, 0.86), (0, 0, 1)), ((0, 0, 0.95), (0, 0, 1)),
               ((0.635, 0, 0), (1, 0, 0)), ((-0.635, 0, 0), (1, 0, 0))]:
    geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
    bmesh.ops.bisect_plane(bm, geom=geom, dist=1e-5, plane_co=co, plane_no=no)
for f in bm.faces:
    f[BOX] = 1

# Materialzuweisung nach nächstem Knochen
centers = np.array([f.calc_center_median()[:] for f in bm.faces])
d, tpar = seg_dist(centers, SEG_A, SEG_B)
near = np.argmin(d, axis=1)
for f, c, ni in zip(bm.faces, centers, near):
    n = SEG_NAMES[ni]
    if "Hand" in n or n in ("Neck", "Head"):
        m = "Skin_Galaxy"
    elif "Foot" in n or "Toe" in n or c[2] < 0.13:
        m = "Shoes"
    elif c[2] < 0.86:
        m = "Pants"
    elif c[2] < 0.95:
        m = "Hoodie_Trim"                                 # Bündchen unten
    elif "ForeArm" in n and abs(c[0]) > 0.635:
        m = "Hoodie_Trim"                                 # Ärmelbündchen
    else:
        m = "Hoodie"
        # offener Reißverschluss: V-Ausschnitt mit Galaxie-Haut
        if c[1] < -0.02 and c[2] > 1.27 and abs(c[0]) < (c[2] - 1.27) * 0.55 + 0.012:
            m = "Skin_Galaxy"
    f.material_index = MAT_ORDER.index(m)
    f.smooth = True

body_bvh = BVHTree.FromBMesh(bm)
extra = Builder()
# Reißverschluss-Kanten entlang des V-Ausschnitts und darunter
for s in (1, -1):
    pts = []
    for z in np.linspace(0.93, 1.40, 24):
        x = s * ((z - 1.27) * 0.55 + 0.016) if z > 1.27 else s * 0.006
        hit = body_bvh.ray_cast(Vector((x, -1, z)), Vector((0, 1, 0)))
        if hit[0]:
            pts.append(np.array(hit[0] + hit[1] * 0.004))
    strand(extra, pts, 0.006, 0.003, (0, -1, 0), "Zipper", seg=30, taper=0.02, uv=False)

# Kapuze (liegt im Nacken)
hv2, hf2 = ellipsoid((0, 0.085, 1.44), (0.14, 0.07, 0.09), 32, 20,
                     shape=lambda p: np.array((p[0], p[1], p[2] + 0.25 * p[1])))
extra.add(hv2, hf2, "Hoodie")
tv, tf = [], []
NU, NV = 40, 12
ARC = math.radians(300)                       # vorne offen (V-Ausschnitt)
for i in range(NU + 1):
    a = math.pi - ARC / 2 + ARC * i / NU     # a = pi -> hinten
    for j in range(NV):
        b = 2 * math.pi * j / NV
        thick = 0.035 * (0.45 + 0.55 * math.sin(math.pi * i / NU))
        R1, R2 = 0.13 + thick * math.cos(b), thick * math.sin(b)
        x, y = R1 * math.sin(a) * 1.2, -R1 * math.cos(a)
        z = 1.385 + R2 + 0.05 * max(0, -math.cos(a))
        tv.append((x, y + 0.02, z))
for i in range(NU):
    for j in range(NV):
        i2, j2 = i + 1, (j + 1) % NV
        tf.append((i * NV + j, i2 * NV + j, i2 * NV + j2, i * NV + j2))
extra.add(tv, tf, "Hoodie")
extra.into_bmesh(bm, MAT_ORDER)
fix_normals(bm)
box_uv(bm)
add_outline(bm, 0.0035)

body = bpy.data.objects.new("Body", body_me)
bm.to_mesh(body_me)
bm.free()
bpy.context.scene.collection.objects.link(body)
for m in MAT_ORDER:
    body.data.materials.append(MATS[m])
skin_weights(body, allowed=[n for n in SEG_NAMES if n != "Head"])
bind(body)



def make_part(name, B, outline_w):
    me = bpy.data.meshes.new(name)
    b = bmesh.new()
    B.into_bmesh(b, MAT_ORDER)
    fix_normals(b)
    box_uv(b, scale=4.0)
    src = add_outline(b, outline_w)
    b.to_mesh(me)
    b.free()
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    for m in MAT_ORDER:
        me.materials.append(MATS[m])
    chain_weights(obj, B, src)
    bind(obj)
    return obj


# Kopf (Gesicht, Ohren) und Haare als getrennte Meshes:
# BONELAB blendet "Head Meshes" und "Hair Meshes" in der Ego-Perspektive aus.
headobj = make_part("Head", head, 0.0022)
hairobj = make_part("Hair", hair, 0.0025)

for o in (body, headobj, hairobj):
    o.data.validate()
    o.data.update()
    o.data.calc_loop_triangles()
    print(f"{o.name}: {len(o.data.loop_triangles)} Dreiecke")

# ================================================================ Export
bpy.ops.object.select_all(action="DESELECT")
for o in (rig, body, headobj, hairobj):
    o.select_set(True)
bpy.context.view_layer.objects.active = rig
fbx = os.path.join(OUT, "SternenElf.fbx")
bpy.ops.export_scene.fbx(
    filepath=fbx, use_selection=True, object_types={"ARMATURE", "MESH"},
    add_leaf_bones=False, bake_anim=False, apply_scale_options="FBX_SCALE_ALL",
    axis_forward="-Z", axis_up="Y", path_mode="COPY", embed_textures=True,
    mesh_smooth_type="FACE", use_armature_deform_only=True)
print("FBX:", fbx)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "SternenElf.blend"))

# ================================================================ Vorschau
TOON_L = Vector((0.35, -0.55, 0.75)).normalized()   # gleiche Lichtrichtung wie im Unity-Shader


def toonify(m, shade, rim=(0.55, 1.0, 0.95), rim_str=0.35, em_str=0.0):
    """Ersetzt das Material für die Vorschau durch eine Nachbildung des Unity-Toon-Shaders:
    harte Licht/Schatten-Kante, farbiger Schatten, Randlicht, Leuchten."""
    nt = m.node_tree
    imgs = [n.image for n in nt.nodes if n.type == "TEX_IMAGE"]
    base = [i for i in imgs if "emission" not in i.name][0]
    emis = [i for i in imgs if "emission" in i.name]
    nt.nodes.clear()
    N = nt.nodes.new
    L = nt.links.new
    out = N("ShaderNodeOutputMaterial")
    tex = N("ShaderNodeTexImage")
    tex.image = base
    geo = N("ShaderNodeNewGeometry")
    dot = N("ShaderNodeVectorMath")
    dot.operation = "DOT_PRODUCT"
    dot.inputs[1].default_value = TOON_L
    L(geo.outputs["Normal"], dot.inputs[0])
    ramp = N("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = -0.12
    ramp.color_ramp.elements[1].position = 0.02
    ramp.color_ramp.interpolation = "EASE"
    L(dot.outputs["Value"], ramp.inputs["Fac"])
    shaded = N("ShaderNodeVectorMath")
    shaded.operation = "MULTIPLY"
    shaded.inputs[1].default_value = shade
    L(tex.outputs["Color"], shaded.inputs[0])
    diff = N("ShaderNodeVectorMath")
    diff.operation = "SUBTRACT"
    L(tex.outputs["Color"], diff.inputs[0])
    L(shaded.outputs[0], diff.inputs[1])
    sc_ = N("ShaderNodeVectorMath")
    sc_.operation = "SCALE"
    L(diff.outputs[0], sc_.inputs[0])
    L(ramp.outputs["Color"], sc_.inputs["Scale"])
    lit = N("ShaderNodeVectorMath")
    lit.operation = "ADD"
    L(shaded.outputs[0], lit.inputs[0])
    L(sc_.outputs[0], lit.inputs[1])
    lw = N("ShaderNodeLayerWeight")
    lw.inputs["Blend"].default_value = 0.5
    pw = N("ShaderNodeMath")
    pw.operation = "POWER"
    L(lw.outputs["Facing"], pw.inputs[0])
    pw.inputs[1].default_value = 3.0
    rs = N("ShaderNodeVectorMath")
    rs.operation = "SCALE"
    rs.inputs[0].default_value = Vector(rim) * rim_str
    L(pw.outputs[0], rs.inputs["Scale"])
    total = N("ShaderNodeVectorMath")
    total.operation = "ADD"
    L(lit.outputs[0], total.inputs[0])
    L(rs.outputs[0], total.inputs[1])
    if emis and em_str:
        et = N("ShaderNodeTexImage")
        et.image = emis[0]
        es = N("ShaderNodeVectorMath")
        es.operation = "SCALE"
        es.inputs["Scale"].default_value = em_str
        L(et.outputs["Color"], es.inputs[0])
        t2 = N("ShaderNodeVectorMath")
        t2.operation = "ADD"
        L(total.outputs[0], t2.inputs[0])
        L(es.outputs[0], t2.inputs[1])
        total = t2
    em = N("ShaderNodeEmission")
    L(total.outputs[0], em.inputs["Color"])
    L(em.outputs[0], out.inputs["Surface"])


if RENDER:
    TOON = {"Skin_Galaxy": ((0.55, 0.5, 0.85), 0.25, 0.5), "Eyes": ((0.8, 0.7, 0.6), 0.0, 0.6),
            "Hair": ((0.45, 0.6, 0.85), 0.35, 0), "Hoodie": ((0.62, 0.78, 0.82), 0.25, 0),
            "Hoodie_Trim": ((0.7, 0.75, 0.7), 0.2, 0), "Pants": ((0.6, 0.6, 0.8), 0.2, 0),
            "Shoes": ((0.7, 0.8, 0.85), 0.2, 0), "Dark": ((1, 1, 1), 0.0, 0),
            "Zipper": ((0.7, 0.8, 0.8), 0.1, 0)}
    for name, (shade, rim_s, em_s) in TOON.items():
        toonify(MATS[name], shade, rim_str=rim_s, em_str=em_s)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 48
    sc.cycles.use_denoising = False
    sc.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("W")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.86, 0.97, 0.93, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.9
    sc.world = world
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 2.5
    sun.rotation_euler = (math.radians(55), 0, math.radians(-30))
    sc.collection.objects.link(sun)
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam

    def shot(name, loc, target, lens, res):
        cam.location = loc
        cam.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
        cam.data.lens = lens
        sc.render.resolution_x, sc.render.resolution_y = res
        sc.render.filepath = os.path.join(OUT, name)
        bpy.ops.render.render(write_still=True)

    shot("preview_portrait.png", (0.15, -1.05, 1.64), (0, 0, 1.58), 55, (800, 800))
    shot("preview_full.png", (1.3, -3.4, 1.15), (0, 0, 0.92), 50, (900, 1000))
    # Rig-Test: Arme runter, leicht gedrehter Kopf
    for side, sgn in (("Left", 1), ("Right", -1)):
        rig.pose.bones[side + "Arm"].rotation_mode = "XYZ"
        rig.pose.bones[side + "ForeArm"].rotation_mode = "XYZ"
    bpy.context.view_layer.update()
    import mathutils
    for side, sgn in (("Left", 1), ("Right", -1)):
        pb = rig.pose.bones[side + "Arm"]
        pb.matrix = mathutils.Matrix.Translation(pb.head) @ \
            mathutils.Matrix.Rotation(math.radians(62 * sgn), 4, "Y") @ \
            mathutils.Matrix.Translation(-pb.head) @ pb.matrix
        bpy.context.view_layer.update()
    shot("preview_pose.png", (1.3, -3.4, 1.15), (0, 0, 0.92), 50, (900, 1000))
    # Haar-Rig-Test: alle Haar- und Ohrketten biegen (wie bei Wind/Kopfbewegung)
    for g, n in CHAIN_BONES.items():
        for k in range(n):
            pb = rig.pose.bones[chain_bone(g, k)]
            pb.rotation_mode = "XYZ"
            pb.rotation_euler = (0.28, 0.0, 0.18) if not g.startswith("Ear") else (0.35, 0, 0)
    bpy.context.view_layer.update()
    shot("preview_hair_rig.png", (0.55, -0.95, 1.68), (0, 0, 1.60), 50, (800, 800))
print("Fertig.")
