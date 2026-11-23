extends RefCounted
## Hilfsfunktionen für den einheitlichen Low-Poly-Look.
## Alle Modelle im Spiel werden hieraus gebaut – dadurch passt alles zusammen
## und es gibt keine Lizenzprobleme.

const D = preload("res://scripts/game_data.gd")

static var _mats: Dictionary = {}


static func mat(color: Color, emission: float = 0.0) -> StandardMaterial3D:
	var key := "%s_%s" % [color.to_html(), emission]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	_mats[key] = m
	return m


static func vmat() -> StandardMaterial3D:
	if _mats.has("__vcol"):
		return _mats["__vcol"]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.95
	_mats["__vcol"] = m
	return m


static func unshaded(color: Color) -> StandardMaterial3D:
	var key := "__unshaded_%s" % color.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mats[key] = m
	return m


static func inst(mesh: Mesh, color: Color, pos: Vector3 = Vector3.ZERO, emission: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat(color, emission)
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func box(size: Vector3, color: Color, pos: Vector3 = Vector3.ZERO, emission: float = 0.0) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	return inst(m, color, pos, emission)


static func sphere(radius: float, color: Color, pos: Vector3 = Vector3.ZERO, segs: int = 8, emission: float = 0.0) -> MeshInstance3D:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = segs
	m.rings = maxi(segs / 2, 2)
	return inst(m, color, pos, emission)


static func cyl(top: float, bottom: float, h: float, color: Color, pos: Vector3 = Vector3.ZERO, segs: int = 8, emission: float = 0.0) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	m.radial_segments = segs
	m.rings = 1
	return inst(m, color, pos, emission)


static func prism(size: Vector3, color: Color, pos: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var m := PrismMesh.new()
	m.size = size
	return inst(m, color, pos)


static func label(text: String, font_size: int = 48, pixel: float = 0.004) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = font_size
	l.pixel_size = pixel
	l.outline_size = maxi(font_size / 4, 4)
	l.outline_modulate = Color(0, 0, 0, 0.85)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	return l


static func make_hand(color: Color) -> MeshInstance3D:
	return box(Vector3(0.075, 0.05, 0.11), color, Vector3(0, -0.01, 0.03))


static func make_sword(tier: int) -> Node3D:
	var s := Node3D.new()
	s.add_child(box(Vector3(0.035, 0.035, 0.16), Color(0.35, 0.22, 0.12), Vector3(0, 0, 0.02)))
	s.add_child(box(Vector3(0.2, 0.035, 0.04), Color(0.55, 0.5, 0.45), Vector3(0, 0, -0.07)))
	s.add_child(sphere(0.03, Color(0.55, 0.5, 0.45), Vector3(0, 0, 0.11), 6))
	var blade := box(Vector3(0.055, 0.014, 0.8), Color.WHITE, Vector3(0, 0, -0.48))
	blade.name = "Blade"
	s.add_child(blade)
	set_sword_tier(s, tier)
	return s


static func set_sword_tier(s: Node3D, tier: int) -> void:
	var blade := s.get_node_or_null("Blade") as MeshInstance3D
	if blade == null:
		return
	var info: Dictionary = D.SWORDS[clampi(tier, 0, D.SWORDS.size() - 1)]
	blade.material_override = mat(info["color"], float(info["glow"]))


static func burst(parent: Node, pos: Vector3, color: Color, amount: int, speed: float, size: float, lifetime: float = 0.8) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = lifetime
	p.explosiveness = 0.95
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -5, 0)
	p.scale_amount_min = size * 0.5
	p.scale_amount_max = size
	var m := BoxMesh.new()
	m.size = Vector3.ONE * 0.08
	m.material = mat(color, 1.5)
	p.mesh = m
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.get_tree().create_timer(lifetime + 0.5).timeout.connect(p.queue_free)
