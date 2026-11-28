extends Node
## Schwebende 3D-Knöpfe. Bedienung:
##   - mit der Zeigefingerspitze antippen (Handtracking, wie echte Knöpfe)
##   - aus der Ferne zeigen + Pinch (Strahl wie im Quest-Menü) bzw. Controller-Trigger
##   - am PC mit der Maus klicken
## Jeder Knopf liegt in der XY-Ebene seines Knotens, die Vorderseite zeigt nach +Z.

const Hands = preload("res://scripts/hands.gd")

var hands: Hands
var _buttons: Array = []   # {node, size, cb, mat, base, label}
var _poke_z := {}          # side -> letzte Tiefe des Fingers am Knopf
var _hover := {}           # side -> Knopf
var _cooldown := {"left": 0.0, "right": 0.0}
var font: Font


## Erzeugt einen Knopf. cb == null: nur Fläche (für Hintergrund/Panel, zeigt den Strahl).
func button(parent: Node3D, text: String, size: Vector2, pos: Vector3, cb, color := Color(0.16, 0.18, 0.24, 0.92), font_size := 28) -> Dictionary:
	var node := Node3D.new()
	node.position = pos
	parent.add_child(node)
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(size.x, size.y, 0.006 if cb != null else 0.002)
	mi.mesh = box
	mi.position.z = -box.size.z * 0.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if color.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(mi)
	var lbl: Label3D = null
	if text != "" or cb != null:
		lbl = label(node, text, font_size, Vector3(0, 0, 0.0015))
		lbl.width = size.x / lbl.pixel_size * 0.92
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var b := {"node": node, "size": size, "cb": cb, "mat": mat, "base": color, "label": lbl, "mesh": mi}
	_buttons.append(b)
	node.tree_exiting.connect(func(): _buttons.erase(b))
	return b


## Knopf mit Bild (z. B. Manga-Cover).
func image_button(parent: Node3D, size: Vector2, pos: Vector3, cb) -> Dictionary:
	var b := button(parent, "", size, pos, cb, Color(0.3, 0.3, 0.34, 1.0))
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = size * 0.94
	q.mesh = qm
	q.position.z = 0.001
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mat.albedo_color = Color(0.55, 0.55, 0.6)
	q.material_override = mat
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	b.node.add_child(q)
	b["image_mat"] = mat
	b["image_quad"] = q
	return b


static func set_image(b: Dictionary, tex: Texture2D, aspect: float) -> void:
	if not b.has("image_mat"):
		return
	var mat: StandardMaterial3D = b.image_mat
	mat.albedo_texture = tex
	mat.albedo_color = Color.WHITE
	# Bild einpassen (Seitenverhältnis erhalten)
	var box_a: float = b.size.x / b.size.y
	var q: MeshInstance3D = b.image_quad
	var qm := q.mesh as QuadMesh
	var s: Vector2 = b.size * 0.94
	if aspect > box_a:
		qm.size = Vector2(s.x, s.x / aspect)
	else:
		qm.size = Vector2(s.y * aspect, s.y)


func label(parent: Node3D, text: String, font_size := 28, pos := Vector3.ZERO) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = font_size
	l.pixel_size = 0.0004
	l.position = pos
	l.outline_size = 0
	l.modulate = Color(0.95, 0.95, 0.97)
	l.double_sided = false
	l.shaded = false
	if font:
		l.font = font
	parent.add_child(l)
	return l


static func set_text(b: Dictionary, text: String) -> void:
	if b.get("label") != null:
		(b.label as Label3D).text = text


static func set_color(b: Dictionary, c: Color) -> void:
	b.base = c
	(b.mat as StandardMaterial3D).albedo_color = c


## Prüft alle Knöpfe. Gibt die Hände zurück, die gerade die Oberfläche benutzen
## (deren Pinch soll dann nicht das Buch umblättern).
func update(delta: float) -> Dictionary:
	var busy := {}
	for side in _cooldown:
		_cooldown[side] = maxf(0.0, _cooldown[side] - delta)
	for h in hands.hands():
		if not h.tracked():
			hands.show_ray(h, null)
			continue
		var hovered = null
		var used := false
		# 1) Antippen mit dem Finger (nur echte Hände / Controller)
		if h.mode != Hands.Mode.MOUSE:
			var best = null
			var best_z := 1e9
			for b in _buttons:
				if b.cb == null or not (b.node as Node3D).is_visible_in_tree():
					continue
				var lp: Vector3 = (b.node as Node3D).global_transform.affine_inverse() * h.tip_pos
				var sz: Vector2 = b.size
				if absf(lp.x) <= sz.x * 0.5 + 0.004 and absf(lp.y) <= sz.y * 0.5 + 0.004 and lp.z > -0.04 and lp.z < 0.035:
					if lp.z < best_z:
						best_z = lp.z
						best = b
			if best != null:
				hovered = best
				used = true
				var key := "%s_%d" % [h.side, best.node.get_instance_id()]
				var prev: float = _poke_z.get(key, 1.0)
				_poke_z[key] = best_z
				if prev > 0.006 and best_z <= 0.006 and _cooldown[h.side] <= 0.0:
					_press(best, h)
			hands.show_ray(h, null)
		# 2) Strahl + Pinch
		if hovered == null:
			var hit = _ray_hit(h.aim_from, h.aim_dir)
			if hit != null:
				used = true
				hands.show_ray(h, hit.point)
				if hit.button.cb != null:
					hovered = hit.button
					if h.pinch_started and _cooldown[h.side] <= 0.0:
						_press(hit.button, h)
			else:
				hands.show_ray(h, null)
		_set_hover(h.side, hovered)
		if used:
			busy[h.side] = true
	return busy


func _ray_hit(from: Vector3, dir: Vector3):
	var best = null
	var best_t := 3.0
	for b in _buttons:
		var n := b.node as Node3D
		if not n.is_visible_in_tree():
			continue
		var inv := n.global_transform.affine_inverse()
		var lo: Vector3 = inv * from
		var ld: Vector3 = inv.basis * dir
		if absf(ld.z) < 1e-5:
			continue
		var t := -lo.z / ld.z
		if t <= 0.0:
			continue
		var lp := lo + ld * t
		var sz: Vector2 = b.size
		if absf(lp.x) <= sz.x * 0.5 and absf(lp.y) <= sz.y * 0.5:
			var wt := (n.global_transform * lp).distance_to(from)
			# Knöpfe gewinnen gegen die Fläche dahinter
			if b.cb == null:
				wt += 0.01
			if wt < best_t:
				best_t = wt
				best = {"button": b, "point": n.global_transform * lp}
	return best


func _press(b: Dictionary, h) -> void:
	_cooldown[h.side] = 0.35
	h.haptic(0.4, 0.05)
	var node := b.node as Node3D
	var tw := node.create_tween()
	tw.tween_property(node, "scale", Vector3(0.94, 0.94, 0.94), 0.05)
	tw.tween_property(node, "scale", Vector3.ONE, 0.08)
	(b.cb as Callable).call()


func _set_hover(side: String, b) -> void:
	var old = _hover.get(side)
	if old == b:
		return
	if old != null and is_instance_valid(old.node):
		(old.mat as StandardMaterial3D).albedo_color = old.base
	_hover[side] = b
	if b != null:
		var c: Color = b.base
		(b.mat as StandardMaterial3D).albedo_color = c.lightened(0.3)


## true, wenn der Punkt auf einem sichtbaren Knopf/Panel liegt (für Maus-Logik).
func pointer_over_ui(from: Vector3, dir: Vector3) -> bool:
	return _ray_hit(from, dir) != null
