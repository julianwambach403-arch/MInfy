extends Node3D
## Ein aufgeschlagenes 3D-Buch mit echten Doppelseiten.
##
## Koordinaten (lokal, vor der Skalierung): Der Buchrücken (Falz) liegt auf der Y-Achse
## bei x = 0, die linke Seite reicht bis x = -W, die rechte bis x = +W. Die Seiten zeigen
## nach +Z zum Leser.
##
## Umblättern: Ein Blatt ist am Falz befestigt. Beim Umblättern dreht es sich um die
## Y-Achse (theta = 0: rechts liegend, theta = PI: links liegend) und biegt sich dabei
## wie Papier (siehe shaders/sheet.gdshader).
## Bei Manga (rechts nach links) blättert man die LINKE Seite nach RECHTS um.

signal spread_changed(first_page: int, total: int)
signal beyond_end(forward: bool)     # über das letzte/erste Blatt hinaus geblättert
signal page_turned

const PageCache = preload("res://scripts/page_cache.gd")
const PAGE_SHADER = preload("res://shaders/page.gdshader")
const SHEET_SHADER = preload("res://shaders/sheet.gdshader")

const W := 0.2      # Seitenbreite (m) bei Größe 1
const H := 0.29     # Seitenhöhe (m) – typisches Tankōbon-Format
const STACK := 0.014
const CURL := 0.85

var cache: PageCache
var source
var pages: Array = []          # Seiten-Referenzen des Kapitels
var spreads: Array = []        # [{a: idx, b: idx, wide: idx}]  a = zuerst gelesen
var cur := 0
var rtl := true
var offset := false            # erste Seite allein (für passende Doppelseiten)
var brightness := 1.0

var page_l: MeshInstance3D
var page_r: MeshInstance3D
var sheet: MeshInstance3D
var stack_l: MeshInstance3D
var stack_r: MeshInstance3D
var mat_l: ShaderMaterial
var mat_r: ShaderMaterial
var mat_s: ShaderMaterial
var info: Label3D
var _audio: AudioStreamPlayer3D

# Umblätter-Zustand
var flipping := false
var flip_side := ""           # "right": rechtes Blatt wandert nach links; "left": umgekehrt
var flip_target := 0
var flip_t := 0.0             # 0 = Start, 1 = umgeblättert
var flip_goal := -1.0         # -1: Hand steuert; sonst Animation zu 0 oder 1
var flip_hand = null
var _phi_prev := 0.0
var _phi_vel := 0.0
var _swipe_cd := 0.0


func _ready() -> void:
	_build()
	_audio = AudioStreamPlayer3D.new()
	_audio.stream = _make_rustle()
	_audio.unit_size = 2.0
	_audio.volume_db = -6.0
	add_child(_audio)


func _build() -> void:
	var cover_mat := StandardMaterial3D.new()
	cover_mat.albedo_color = Color(0.32, 0.12, 0.12)
	cover_mat.roughness = 0.7
	var paper_mat := StandardMaterial3D.new()
	paper_mat.albedo_color = Color(0.93, 0.91, 0.86)
	paper_mat.roughness = 1.0
	# Buchdeckel (etwas größer als die Seiten)
	for s in [-1.0, 1.0]:
		var c := MeshInstance3D.new()
		var cb := BoxMesh.new()
		cb.size = Vector3(W + 0.008, H + 0.014, 0.004)
		c.mesh = cb
		c.material_override = cover_mat
		c.position = Vector3(s * (W * 0.5 + 0.004), 0, -STACK - 0.002)
		add_child(c)
	var spine := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 0.012
	sm.bottom_radius = 0.012
	sm.height = H + 0.014
	sm.radial_segments = 12
	spine.mesh = sm
	spine.material_override = cover_mat
	spine.position = Vector3(0, 0, -STACK - 0.004)
	spine.scale = Vector3(1.0, 1.0, 0.5)
	add_child(spine)
	# Seitenstapel links und rechts (Dicke zeigt, wie weit man ist)
	stack_l = _stack(paper_mat)
	stack_r = _stack(paper_mat)
	# Sichtbare Seiten
	mat_l = _page_material(false)
	mat_r = _page_material(true)
	page_l = _page_mesh(mat_l, -W * 0.5)
	page_r = _page_mesh(mat_r, W * 0.5)
	# Umblatt-Blatt (fein unterteilt, damit es sich biegen kann)
	mat_s = ShaderMaterial.new()
	mat_s.shader = SHEET_SHADER
	mat_s.set_shader_parameter("width", W)
	sheet = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.orientation = PlaneMesh.FACE_Z
	pm.size = Vector2(W, H)
	pm.center_offset = Vector3(W * 0.5, 0, 0)
	pm.subdivide_width = 32
	pm.subdivide_depth = 1
	sheet.mesh = pm
	sheet.material_override = mat_s
	sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sheet.extra_cull_margin = W
	sheet.visible = false
	add_child(sheet)
	info = Label3D.new()
	info.font_size = 24
	info.pixel_size = 0.0004
	info.position = Vector3(0, -H * 0.5 - 0.016, 0.002)
	info.modulate = Color(0.95, 0.95, 0.95, 0.85)
	info.outline_size = 6
	info.outline_modulate = Color(0, 0, 0, 0.6)
	add_child(info)
	_update_stacks()


func _stack(mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(W - 0.002, H - 0.002, 1.0)
	m.mesh = b
	m.material_override = mat
	add_child(m)
	return m


func _page_material(right_side: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = PAGE_SHADER
	m.set_shader_parameter("spine_left", 1.0 if right_side else 0.0)
	return m


func _page_mesh(mat: Material, x: float) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(W, H)
	m.mesh = q
	m.material_override = mat
	m.position = Vector3(x, 0, 0.0005)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	return m


func _update_stacks() -> void:
	var p := 0.0 if spreads.size() <= 1 else float(cur) / (spreads.size() - 1)
	# Die schon gelesenen Seiten liegen auf der Seite, wo man angefangen hat
	var done := STACK * p
	var todo := STACK * (1.0 - p)
	var lt := done if rtl else todo
	var rt := todo if rtl else done
	# Stapel liegen auf dem Deckel (z = -STACK), die Seite oben auf dem Stapel.
	var tops := []
	for pair in [[stack_l, lt, -1.0, page_l], [stack_r, rt, 1.0, page_r]]:
		var m: MeshInstance3D = pair[0]
		var t: float = maxf(pair[1], 0.001)
		m.scale = Vector3(1, 1, t)
		m.position = Vector3(pair[2] * W * 0.5, 0, -STACK + t * 0.5)
		var top := -STACK + t
		(pair[3] as MeshInstance3D).position.z = top + 0.0005
		tops.append(top)
	sheet.position.z = maxf(tops[0], tops[1])


# ================================================================ Inhalt

func open_chapter(p_source, p_pages: Array, start_page := 0) -> void:
	source = p_source
	pages = p_pages
	flipping = false
	sheet.visible = false
	_layout()
	cur = spread_of_page(start_page)
	_show()


func set_rtl(v: bool) -> void:
	var p := first_page()
	rtl = v
	_layout()
	cur = spread_of_page(p)
	_show()


func set_offset(v: bool) -> void:
	var p := first_page()
	offset = v
	_layout()
	cur = spread_of_page(p)
	_show()


func _is_wide(i: int) -> bool:
	return cache != null and i >= 0 and i < pages.size() and cache.get_aspect(pages[i]) > 1.05


## Ordnet die Seiten zu Doppelseiten. Querformat-Bilder (schon im Scan als Doppelseite)
## bekommen eine ganze Doppelseite für sich.
func _layout() -> void:
	spreads.clear()
	var i := 0
	if offset and pages.size() > 0 and not _is_wide(0):
		spreads.append({"a": -1, "b": 0, "wide": -1})
		i = 1
	while i < pages.size():
		if _is_wide(i):
			spreads.append({"a": -1, "b": -1, "wide": i})
			i += 1
		elif i + 1 < pages.size() and not _is_wide(i + 1):
			spreads.append({"a": i, "b": i + 1, "wide": -1})
			i += 2
		else:
			spreads.append({"a": i, "b": -1, "wide": -1})
			i += 1
	if spreads.is_empty():
		spreads.append({"a": -1, "b": -1, "wide": -1})


func spread_of_page(p: int) -> int:
	for s in spreads.size():
		var sp: Dictionary = spreads[s]
		if sp.a == p or sp.b == p or sp.wide == p:
			return s
	return clampi(0 if p <= 0 else spreads.size() - 1, 0, spreads.size() - 1)


func first_page() -> int:
	if spreads.is_empty():
		return 0
	var sp: Dictionary = spreads[clampi(cur, 0, spreads.size() - 1)]
	if sp.wide >= 0:
		return sp.wide
	return sp.a if sp.a >= 0 else maxi(sp.b, 0)


func at_end() -> bool:
	return cur >= spreads.size() - 1


## Was liegt auf welcher Seite einer Doppelseite? -> {idx, src: Vector2(u0,u1), align}
func _side(s: int, side: String) -> Dictionary:
	if s < 0 or s >= spreads.size():
		return {"idx": -1}
	var sp: Dictionary = spreads[s]
	if sp.wide >= 0:
		return {"idx": sp.wide, "src": Vector2(0.0, 0.5) if side == "left" else Vector2(0.5, 1.0), "half": true}
	var first_on_right := rtl
	var idx: int = sp.a if (side == "right") == first_on_right else sp.b
	return {"idx": idx, "src": Vector2(0, 1), "half": false}


## Setzt Bild-Parameter einer Seite in ein Material (prefix "" für Seiten, "front_"/"back_" fürs Blatt).
func _apply(mat: ShaderMaterial, prefix: String, info_d: Dictionary, side: String) -> void:
	var idx: int = info_d.idx
	var has_name := "has_tex" if prefix == "" else prefix + "has"
	var tex_name := "tex" if prefix == "" else prefix + "tex"
	if idx < 0 or idx >= pages.size():
		mat.set_shader_parameter(has_name, 0.0 if idx >= 0 else 1.0)
		mat.set_shader_parameter(tex_name, _blank())
		mat.set_shader_parameter(prefix + "fit", Vector4(0, 0, 0, 0))
		return
	var tex := cache.get_texture(pages[idx])
	if tex == null:
		mat.set_shader_parameter(has_name, 0.0)
		return
	var ia := cache.get_aspect(pages[idx])
	if info_d.half:
		ia *= 0.5
	var pa := W / H
	var fit := Vector4(0, 0, 1, 1)
	if ia > pa:
		var h := pa / ia
		fit = Vector4(0, (1.0 - h) * 0.5, 1, (1.0 + h) * 0.5)
	else:
		var w := ia / pa
		if info_d.half:
			# Hälften einer Doppelseite an den Falz schieben
			fit = Vector4(1.0 - w, 0, 1, 1) if side == "left" else Vector4(0, 0, w, 1)
		else:
			fit = Vector4((1.0 - w) * 0.5, 0, (1.0 + w) * 0.5, 1)
	mat.set_shader_parameter(tex_name, tex)
	mat.set_shader_parameter(has_name, 1.0)
	mat.set_shader_parameter(prefix + "fit", fit)
	mat.set_shader_parameter(prefix + "src", info_d.src)


var _blank_tex: ImageTexture
func _blank() -> Texture2D:
	if _blank_tex == null:
		var img := Image.create(4, 4, false, Image.FORMAT_RGB8)
		img.fill(Color(0.96, 0.95, 0.91))
		_blank_tex = ImageTexture.create_from_image(img)
	return _blank_tex


## Zeigt die aktuelle Doppelseite (bzw. während des Umblätterns die richtige Mischung).
func _show() -> void:
	_request_around()
	if flipping:
		if flip_side == "right":
			_apply(mat_r, "", _side(flip_target, "right"), "right")
			_apply(mat_l, "", _side(cur, "left"), "left")
			_apply(mat_s, "front_", _side(cur, "right"), "right")
			_apply(mat_s, "back_", _side(flip_target, "left"), "left")
		else:
			_apply(mat_l, "", _side(flip_target, "left"), "left")
			_apply(mat_r, "", _side(cur, "right"), "right")
			_apply(mat_s, "back_", _side(cur, "left"), "left")
			_apply(mat_s, "front_", _side(flip_target, "right"), "right")
	else:
		_apply(mat_l, "", _side(cur, "left"), "left")
		_apply(mat_r, "", _side(cur, "right"), "right")
	for m in [mat_l, mat_r, mat_s]:
		m.set_shader_parameter("brightness", brightness)
	_update_stacks()
	var total := pages.size()
	var fp := first_page()
	var sp: Dictionary = spreads[cur] if cur < spreads.size() else {}
	var lastp: int = fp
	if sp.get("b", -1) >= 0:
		lastp = sp.b
	info.text = ("Seite %d–%d / %d" % [fp + 1, lastp + 1, total]) if lastp != fp else ("Seite %d / %d" % [fp + 1, total])
	spread_changed.emit(fp, total)


func _request_around() -> void:
	if cache == null or source == null:
		return
	var Cfg = preload("res://scripts/config.gd")
	# Erst die aktuelle Doppelseite, dann abwechselnd vor- und zurück
	var order: Array = [cur]
	for d in range(1, Cfg.PRELOAD_SPREADS + 1):
		order.append(cur + d)
		if d <= 1:
			order.append(cur - d)
	for s in order:
		if s < 0 or s >= spreads.size():
			continue
		var sp: Dictionary = spreads[s]
		for k in ["a", "b", "wide"]:
			var i: int = sp[k]
			if i >= 0 and i < pages.size():
				cache.request(source, pages[i])


## Vom PageCache: neue Seite geladen.
func on_page_ready(_key: String) -> void:
	if pages.is_empty():
		return
	# Hat sich durch ein Querformat-Bild die Aufteilung geändert?
	var p := first_page()
	var old := spreads.size()
	_layout()
	if spreads.size() != old and not flipping:
		cur = spread_of_page(p)
	_show()


# ================================================================ Umblättern

## side: welches Blatt angehoben wird ("left"/"right"). Gibt false zurück, wenn es dort nicht weitergeht.
func begin_flip(side: String, hand = null) -> bool:
	if flipping or spreads.is_empty():
		return false
	var forward := (side == "left") == rtl
	var target := cur + (1 if forward else -1)
	if target < 0 or target >= spreads.size():
		beyond_end.emit(forward)
		return false
	flipping = true
	flip_side = side
	flip_target = target
	flip_t = 0.0
	flip_hand = hand
	flip_goal = -1.0 if hand != null else 1.0
	_phi_vel = 0.0
	_phi_prev = 0.0 if side == "right" else PI
	sheet.visible = true
	_set_sheet_angle(_phi_prev)
	_show()
	_audio.pitch_scale = randf_range(0.9, 1.15)
	_audio.play()
	return true


func turn(forward: bool) -> bool:
	var side := "left" if forward == rtl else "right"
	if flipping:
		# Schnell hintereinander blättern: laufende Animation sofort beenden
		_finish(flip_goal >= 0.5 or flip_goal < 0.0)
	return begin_flip(side)


## phi = Winkel der Blattkante (0 = rechts liegend, PI = links liegend)
func _set_sheet_angle(phi: float) -> void:
	var k := CURL * sin(phi) * (1.0 if flip_side == "right" else -1.0)
	var theta := clampf(phi - k, 0.0, PI)
	mat_s.set_shader_parameter("theta", theta)
	mat_s.set_shader_parameter("curl", k)


func _phi_from_t(t: float) -> float:
	return t * PI if flip_side == "right" else PI * (1.0 - t)


func _process(delta: float) -> void:
	_swipe_cd = maxf(0.0, _swipe_cd - delta)
	if not flipping:
		return
	if flip_goal < 0.0 and flip_hand != null:
		# Blatt folgt der Hand
		var lp := to_local_unscaled(flip_hand.pinch_pos)
		var phi := atan2(maxf(lp.z, 0.0) + 0.02, lp.x)
		phi = clampf(phi, 0.0, PI)
		_phi_vel = lerpf(_phi_vel, (phi - _phi_prev) / maxf(delta, 0.001), clampf(delta * 12.0, 0.0, 1.0))
		_phi_prev = phi
		flip_t = phi / PI if flip_side == "right" else 1.0 - phi / PI
		_set_sheet_angle(phi)
		if not flip_hand.pinching:
			# Losgelassen: über die Mitte (oder mit Schwung) -> umblättern
			var vel_t := _phi_vel / PI * (1.0 if flip_side == "right" else -1.0)
			flip_goal = 1.0 if (flip_t > 0.5 or vel_t > 1.2) and vel_t > -1.2 else 0.0
			flip_hand = null
	else:
		var speed := 2.6
		flip_t = move_toward(flip_t, flip_goal, delta * speed * (0.6 + sin(clampf(flip_t, 0.0, 1.0) * PI)))
		_set_sheet_angle(_phi_from_t(flip_t))
		if is_equal_approx(flip_t, flip_goal):
			_finish(flip_goal > 0.5)


func _finish(done: bool) -> void:
	flipping = false
	sheet.visible = false
	flip_hand = null
	if done:
		cur = flip_target
		page_turned.emit()
	_show()


# ================================================================ Hand-Interaktion

func to_local_unscaled(world: Vector3) -> Vector3:
	return global_transform.affine_inverse() * world


## Liegt der Punkt (Welt) auf/über einer Seite? -> "left"/"right"/""
func page_under(world: Vector3, depth_front := 0.07, depth_back := 0.03) -> String:
	var lp := to_local_unscaled(world)
	if absf(lp.y) > H * 0.5 + 0.02 or lp.z > depth_front or lp.z < -depth_back:
		return ""
	if lp.x > W * 0.25 and lp.x < W + 0.03:
		return "right"
	if lp.x < -W * 0.25 and lp.x > -W - 0.03:
		return "left"
	return ""


## Pinch auf einer Seite -> Blatt greifen. Gibt true zurück, wenn die Hand jetzt blättert.
func try_pinch(hand) -> bool:
	if flipping:
		return false
	var side := page_under(hand.pinch_pos)
	if side == "":
		return false
	if begin_flip(side, hand):
		hand.haptic(0.25, 0.04)
		return true
	hand.haptic(0.6, 0.08)
	return false


## Mit offener Hand über das Buch wischen -> umblättern.
func try_swipe(hand) -> void:
	if flipping or _swipe_cd > 0.0 or hand.pinching or hand.grabbing:
		return
	var lp := to_local_unscaled(hand.palm.origin)
	if absf(lp.y) > H * 0.6 or lp.z < -0.02 or lp.z > 0.22 or absf(lp.x) > W * 1.3:
		return
	var lv: Vector3 = (global_basis.inverse() * hand.vel)
	if absf(lv.x) < 1.1 or absf(lv.x) < absf(lv.y) * 1.5:
		return
	_swipe_cd = 0.6
	# Hand wischt nach links -> rechtes Blatt wird mitgenommen
	begin_flip("right" if lv.x < 0.0 else "left")


## Berührt die Hand das Buch zum Festhalten (Rand, Rücken oder Rückseite)?
func can_grab(world: Vector3) -> bool:
	var lp := to_local_unscaled(world)
	return absf(lp.x) < W + 0.05 and absf(lp.y) < H * 0.5 + 0.05 and lp.z < 0.08 and lp.z > -0.09


## Am PC: Schnittpunkt des Mausstrahls mit der Buchebene (leicht davor).
func ray_point(from: Vector3, dir: Vector3):
	var inv := global_transform.affine_inverse()
	var lo: Vector3 = inv * from
	var ld: Vector3 = inv.basis * dir
	if absf(ld.z) < 1e-5:
		return null
	var t := (0.01 - lo.z) / ld.z
	if t <= 0.0:
		return null
	var lp := lo + ld * t
	if flipping and flip_hand != null:
		# Beim Ziehen am PC: über den Falz hinaus das Blatt anheben
		lp.z = 0.01 + maxf(0.0, W * 0.7 - absf(lp.x)) * 0.8
	if absf(lp.x) > W * 1.6 or absf(lp.y) > H:
		return null
	return global_transform * lp


func set_brightness(b: float) -> void:
	brightness = b
	_show()


# ================================================================ Klang

## Kurzes Papierrascheln, im Code erzeugt (gefiltertes Rauschen mit Hüllkurve).
func _make_rustle() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 0.32)
	var data := PackedByteArray()
	data.resize(n * 2)
	var lp := 0.0
	var lp2 := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in n:
		var t := float(i) / n
		var env := pow(sin(t * PI), 1.6) * (0.6 + 0.4 * sin(t * 37.0) * sin(t * 11.0))
		var x := rng.randf_range(-1.0, 1.0)
		lp += (x - lp) * 0.55
		lp2 += (lp - lp2) * 0.08
		var v := clampf((lp - lp2) * env * 0.9, -1.0, 1.0)
		var s := int(v * 32000.0)
		data.encode_s16(i * 2, s)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w
