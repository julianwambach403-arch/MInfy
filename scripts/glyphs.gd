extends RefCounted
## Erkennung von in die Luft gezeichneten Zauberzeichen.
## Prinzip wie der "$1 Unistroke Recognizer" (Wobbrock et al.): Strich auf N Punkte
## neu abtasten, verschieben, skalieren und mit Vorlagen vergleichen.
## Anders als beim Original bleibt die Ausrichtung erhalten (ein "V" ist kein "^"),
## es werden nur kleine Drehungen toleriert. Zeichenrichtung und Startpunkt sind egal,
## weil jede Vorlage in mehreren Varianten vorliegt.

const N := 48
const ROTATIONS := [-0.35, -0.17, 0.0, 0.17, 0.35]
const MIN_SCORE := 0.5          # entspricht mittlerer Abweichung 0,25 (getestet: echte Zeichen < 0,23, Kritzeleien > 0,27)
const CORNER_PENALTY := 0.02
const CORNER_K := 3
const CORNER_ANGLE := 1.047      # 60 Grad

## Zeichen der Standard-Fähigkeiten (Skill-ID -> Zeichen)
const SKILL_GLYPHS := {
	"fireball": "kreis", "heal": "haken", "frost": "dreieck",
	"whirl": "spirale", "lightning": "blitz", "shield": "quadrat",
}
## Zeichen für eigene Fähigkeiten (von Claude), in der Reihenfolge ihrer Entstehung
const CUSTOM_GLYPHS := ["stern", "welle", "dach", "acht"]

const NAMES := {
	"kreis": "Kreis", "haken": "Haken (V)", "dreieck": "Dreieck", "spirale": "Spirale",
	"blitz": "Blitz (Zickzack)", "quadrat": "Quadrat", "stern": "Stern", "welle": "Welle",
	"dach": "Dach (^)", "acht": "Acht (liegend)",
}

static var _cache: Dictionary = {}


# ---------------- Vorlagen ----------------

static func _poly(corners: Array, closed: bool) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var c := corners.duplicate()
	if closed:
		c.append(corners[0])
	for i in c.size() - 1:
		var a: Vector2 = c[i]
		var b: Vector2 = c[i + 1]
		for k in 8:
			pts.append(a.lerp(b, k / 8.0))
	pts.append(c[c.size() - 1])
	return pts


static func _closed_variants(corners: Array) -> Array:
	# Jede Ecke als Startpunkt, beide Richtungen
	var out: Array = []
	for s in corners.size():
		var rot: Array = []
		for i in corners.size():
			rot.append(corners[(s + i) % corners.size()])
		out.append(_poly(rot, true))
		var rev := rot.duplicate()
		rev.reverse()
		out.append(_poly(rev, true))
	return out


static func _open_variants(corners: Array) -> Array:
	var rev := corners.duplicate()
	rev.reverse()
	return [_poly(corners, false), _poly(rev, false)]


static func _reversed(p: PackedVector2Array) -> PackedVector2Array:
	var r := p.duplicate()
	r.reverse()
	return r


static func _raw_templates(glyph: String) -> Array:
	match glyph:
		"kreis":
			var out: Array = []
			for s in 8:
				for dir in [1.0, -1.0]:
					var pts := PackedVector2Array()
					for i in 33:
						var a: float = s * TAU / 8.0 + dir * TAU * i / 32.0
						pts.append(Vector2(cos(a), sin(a)))
					out.append(pts)
			return out
		"dreieck":
			return _closed_variants([Vector2(0, 1), Vector2(-0.87, -0.5), Vector2(0.87, -0.5)])
		"quadrat":
			return _closed_variants([Vector2(-1, 1), Vector2(1, 1), Vector2(1, -1), Vector2(-1, -1)])
		"haken":
			return _open_variants([Vector2(-1, 1), Vector2(0, -1), Vector2(1, 1)]) \
				+ _open_variants([Vector2(-0.6, 0.0), Vector2(0, -1), Vector2(1, 1)])
		"dach":
			return _open_variants([Vector2(-1, -1), Vector2(0, 1), Vector2(1, -1)])
		"blitz":
			return _open_variants([Vector2(0.4, 1), Vector2(-0.4, 0.05), Vector2(0.4, -0.05), Vector2(-0.4, -1)]) \
				+ _open_variants([Vector2(-0.4, 1), Vector2(0.4, 0.05), Vector2(-0.4, -0.05), Vector2(0.4, -1)])
		"stern":
			var corners: Array = []
			for k in 5:
				var a := PI / 2.0 + k * 2.0 * TAU / 5.0
				corners.append(Vector2(cos(a), sin(a)))
			return _closed_variants(corners)
		"welle":
			var w := PackedVector2Array()
			for i in 41:
				var x := -1.0 + 2.0 * i / 40.0
				w.append(Vector2(x, 0.45 * sin(x * TAU)))
			return [w, _reversed(w)]
		"spirale":
			var out2: Array = []
			for dir in [1.0, -1.0]:
				var sp := PackedVector2Array()
				for i in 46:
					var t := i / 45.0
					var a: float = dir * t * TAU * 1.5
					sp.append(Vector2(cos(a), sin(a)) * (0.15 + 0.85 * t))
				out2.append(sp)
				out2.append(_reversed(sp))
			return out2
		"acht":
			var out3: Array = []
			for dir in [1.0, -1.0]:
				var e := PackedVector2Array()
				for i in 49:
					var a: float = dir * TAU * i / 48.0
					e.append(Vector2(sin(a), sin(a) * cos(a)))
				out3.append(e)
				out3.append(_reversed(e))
			return out3
	return []


static func templates(glyph: String) -> Array:
	if not _cache.has(glyph):
		var norm: Array = []
		for t in _raw_templates(glyph):
			var n := normalize(t)
			if not n.is_empty():
				norm.append([n, count_corners(n)])
		_cache[glyph] = norm
	return _cache[glyph]


## Eine Vorlage zur Anzeige im Menü (normiert, Mittelpunkt 0, Größe ~1)
static func preview(glyph: String) -> PackedVector2Array:
	var t := templates(glyph)
	return t[0][0] if not t.is_empty() else PackedVector2Array()


# ---------------- Verarbeitung ----------------

static func path_length(pts: PackedVector2Array) -> float:
	var d := 0.0
	for i in range(1, pts.size()):
		d += pts[i - 1].distance_to(pts[i])
	return d


static func resample(pts: PackedVector2Array, n: int) -> PackedVector2Array:
	var interval := path_length(pts) / float(n - 1)
	if interval <= 0.0:
		return PackedVector2Array()
	var src := pts.duplicate()
	var out := PackedVector2Array([src[0]])
	var acc := 0.0
	var i := 1
	while i < src.size():
		var d := src[i - 1].distance_to(src[i])
		if acc + d >= interval and d > 0.0:
			var q := src[i - 1].lerp(src[i], (interval - acc) / d)
			out.append(q)
			src.insert(i, q)
			acc = 0.0
		else:
			acc += d
		i += 1
	while out.size() < n:
		out.append(src[src.size() - 1])
	return out


static func normalize(pts: PackedVector2Array) -> PackedVector2Array:
	if pts.size() < 2:
		return PackedVector2Array()
	var r := resample(pts, N)
	if r.size() < N:
		return PackedVector2Array()
	var minv := r[0]
	var maxv := r[0]
	var c := Vector2.ZERO
	for p in r:
		minv = minv.min(p)
		maxv = maxv.max(p)
		c += p
	c /= float(r.size())
	# Nicht-uniform auf ein Quadrat skalieren (gleicht schiefes Zeichnen aus),
	# sehr schmale Striche aber höchstens auf das ~3-fache strecken
	var m := maxf(maxv.x - minv.x, maxv.y - minv.y)
	if m < 0.0001:
		return PackedVector2Array()
	var w := maxf(maxv.x - minv.x, m * 0.35)
	var h := maxf(maxv.y - minv.y, m * 0.35)
	var out := PackedVector2Array()
	for p in r:
		out.append(Vector2((p.x - c.x) / w, (p.y - c.y) / h))
	return out


## Zählt scharfe Richtungswechsel (Ecken): Kreis 0, Haken 1, Blitz 2, Dreieck 2-3, Quadrat 3-4 ...
static func count_corners(p: PackedVector2Array) -> int:
	var ang := PackedFloat32Array()
	ang.resize(p.size())
	for i in range(CORNER_K, p.size() - CORNER_K):
		var a := p[i] - p[i - CORNER_K]
		var b := p[i + CORNER_K] - p[i]
		if a.length() < 0.000001 or b.length() < 0.000001:
			continue
		ang[i] = absf(a.angle_to(b))
	var n := 0
	var i := 0
	while i < p.size():
		if ang[i] > CORNER_ANGLE:
			while i + 1 < p.size() and ang[i + 1] > CORNER_ANGLE:
				i += 1
			n += 1
		i += 1
	return n


static func _distance(a: PackedVector2Array, b: PackedVector2Array) -> float:
	var d := 0.0
	for i in N:
		d += a[i].distance_to(b[i])
	return d / N


static func _rotated(pts: PackedVector2Array, angle: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(p.rotated(angle))
	return out


## Erkennt den Strich unter den erlaubten Zeichen.
## Rückgabe: {"name": Zeichen oder "", "score": 0..1}
static func recognize(raw: PackedVector2Array, allowed: Array) -> Dictionary:
	var c := normalize(raw)
	if c.is_empty():
		return {"name": "", "score": 0.0}
	var corners := count_corners(c)
	var rots: Array = []
	for a in ROTATIONS:
		rots.append(_rotated(c, a))
	var best := INF
	var best_name := ""
	for g in allowed:
		for t in templates(g):
			var tpts: PackedVector2Array = t[0]
			var pen := CORNER_PENALTY * absi(corners - int(t[1]))
			for rc in rots:
				var d := _distance(rc, tpts) + pen
				if d < best:
					best = d
					best_name = g
	var score := clampf(1.0 - best / 0.5, 0.0, 1.0)
	if score < MIN_SCORE:
		return {"name": "", "score": score, "guess": best_name}
	return {"name": best_name, "score": score}
