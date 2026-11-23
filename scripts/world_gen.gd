extends RefCounted
## Erzeugt die Insel-Welt. Die Höhenfunktion ist deterministisch,
## damit Server (Gegner-Bewegung) und Clients (Grafik) exakt dieselbe Welt kennen.

const LP = preload("res://scripts/lowpoly.gd")
const D = preload("res://scripts/game_data.gd")

const HALF := 120.0
const STEP := 2.5
const SKY_TOP := Color(0.3, 0.52, 0.88)
const SKY_HORIZON := Color(0.74, 0.84, 0.95)

static var _noise: FastNoiseLite = null


static func _n() -> FastNoiseLite:
	if _noise == null:
		_noise = FastNoiseLite.new()
		_noise.seed = 1337
		_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_noise.frequency = 0.011
		_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		_noise.fractal_octaves = 3
	return _noise


static func height(x: float, z: float) -> float:
	var h: float = _n().get_noise_2d(x, z) * 8.0 + 5.0
	var d: float = Vector2(x, z).length()
	h = lerpf(h, -5.0, clampf((d - 88.0) / 25.0, 0.0, 1.0))
	h = _flatten(h, x, z, D.VILLAGE, 16.0, 12.0, 2.5)
	h = _flatten(h, x, z, D.RUINS, 13.0, 12.0, 7.0)
	h = _flatten(h, x, z, D.MEADOW, 16.0, 14.0, 2.2)
	return h


static func _flatten(h: float, x: float, z: float, center: Vector3, inner: float, blend: float, level: float) -> float:
	var dist: float = Vector2(x - center.x, z - center.z).length()
	var t: float = clampf((dist - inner) / blend, 0.0, 1.0)
	t = t * t * (3.0 - 2.0 * t)
	return lerpf(level, h, t)


static func _near(x: float, z: float, c: Vector3, r: float) -> bool:
	return Vector2(x - c.x, z - c.z).length() < r


static func build(parent: Node3D) -> void:
	parent.add_child(_environment())
	parent.add_child(_sun())
	parent.add_child(_terrain())
	parent.add_child(_water())
	_trees(parent)
	_rocks(parent)
	_flowers(parent)
	_village(parent)
	_ruins(parent)
	_signs(parent)
	_clouds(parent)


static func _environment() -> WorldEnvironment:
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = SKY_TOP
	sm.sky_horizon_color = SKY_HORIZON
	sm.ground_bottom_color = Color(0.2, 0.35, 0.5)
	sm.ground_horizon_color = SKY_HORIZON
	var sky := Sky.new()
	sky.sky_material = sm
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = SKY_HORIZON
	env.fog_density = 0.006
	env.fog_sky_affect = 0.25
	var we := WorldEnvironment.new()
	we.environment = env
	return we


static func _sun() -> DirectionalLight3D:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, 35, 0)
	sun.light_energy = 1.15
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.shadow_enabled = false
	return sun


static func _ground_color(h: float, x: float, z: float) -> Color:
	if h < 0.6:
		return Color(0.88, 0.82, 0.58)
	if _near(x, z, D.VILLAGE, 5.5):
		return Color(0.62, 0.5, 0.34)
	if _near(x, z, D.RUINS, 11.0):
		return Color(0.63, 0.61, 0.56)
	if h > 10.8:
		return Color(0.56, 0.56, 0.6)
	var v: float = _n().get_noise_2d(x * 4.0 + 500.0, z * 4.0) * 0.07
	var g := Color(0.45 + v, 0.7 + v, 0.32)
	var fd: float = Vector2(x - D.FOREST.x, z - D.FOREST.z).length()
	if fd < 34.0:
		g = g.lerp(Color(0.24 + v, 0.48 + v, 0.24), clampf(1.0 - fd / 34.0, 0.0, 1.0) * 1.4)
	if h > 9.0:
		g = g.lerp(Color(0.56, 0.56, 0.6), (h - 9.0) / 1.8)
	return g


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var nrm := (c - a).cross(b - a)
	if nrm.y < 0.0:
		var tmp := b
		b = c
		c = tmp
		nrm = -nrm
	nrm = nrm.normalized()
	var center := (a + b + c) / 3.0
	var col := _ground_color(center.y, center.x, center.z)
	for v in [a, b, c]:
		st.set_normal(nrm)
		st.set_color(col)
		st.add_vertex(v)


static func _terrain() -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := int(HALF * 2.0 / STEP)
	var heights: Array = []
	for i in n + 1:
		var row := PackedFloat32Array()
		for j in n + 1:
			row.append(height(-HALF + i * STEP, -HALF + j * STEP))
		heights.append(row)
	for i in n:
		for j in n:
			var x0 := -HALF + i * STEP
			var z0 := -HALF + j * STEP
			var x1 := x0 + STEP
			var z1 := z0 + STEP
			var r0: PackedFloat32Array = heights[i]
			var r1: PackedFloat32Array = heights[i + 1]
			var a := Vector3(x0, r0[j], z0)
			var b := Vector3(x1, r1[j], z0)
			var c := Vector3(x0, r0[j + 1], z1)
			var d := Vector3(x1, r1[j + 1], z1)
			_tri(st, a, b, c)
			_tri(st, b, d, c)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = LP.vmat()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func _water() -> MeshInstance3D:
	var pm := PlaneMesh.new()
	pm.size = Vector2(700, 700)
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.2, 0.5, 0.78)
	m.roughness = 0.15
	m.metallic_specular = 0.8
	mi.material_override = m
	mi.position.y = -0.2
	return mi


static func _mm(mesh: Mesh, xforms: Array, color: Color) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = LP.mat(color)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi


static func _cyl_mesh(top: float, bottom: float, h: float, segs: int) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	m.radial_segments = segs
	m.rings = 1
	return m


static func _trees(parent: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var trunks: Array = []
	var pine1: Array = []
	var pine2: Array = []
	var round_crowns: Array = []
	for i in 1600:
		var x := rng.randf_range(-100.0, 100.0)
		var z := rng.randf_range(-100.0, 100.0)
		var h := height(x, z)
		if h < 1.0 or h > 10.0 or Vector2(x, z).length() > 97.0:
			continue
		if _near(x, z, D.VILLAGE, 21.0) or _near(x, z, D.RUINS, 16.0) or _near(x, z, D.MEADOW, 17.0):
			continue
		var in_forest := _near(x, z, D.FOREST, 34.0)
		if in_forest and _near(x, z, D.FOREST, 9.0):
			continue
		if not in_forest and rng.randf() > 0.2:
			continue
		var s := rng.randf_range(0.8, 1.45)
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s))
		trunks.append(Transform3D(b, Vector3(x, h + 0.8 * s, z)))
		if in_forest:
			pine1.append(Transform3D(b, Vector3(x, h + 2.8 * s, z)))
			pine2.append(Transform3D(b, Vector3(x, h + 4.3 * s, z)))
		else:
			round_crowns.append(Transform3D(b, Vector3(x, h + 2.6 * s, z)))
	parent.add_child(_mm(_cyl_mesh(0.18, 0.26, 1.6, 6), trunks, Color(0.45, 0.3, 0.18)))
	parent.add_child(_mm(_cyl_mesh(0.0, 1.5, 2.8, 7), pine1, Color(0.18, 0.45, 0.25)))
	parent.add_child(_mm(_cyl_mesh(0.0, 1.05, 2.0, 7), pine2, Color(0.22, 0.52, 0.28)))
	var sm := SphereMesh.new()
	sm.radius = 1.4
	sm.height = 2.6
	sm.radial_segments = 7
	sm.rings = 4
	parent.add_child(_mm(sm, round_crowns, Color(0.36, 0.62, 0.28)))


static func _rocks(parent: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var xf: Array = []
	for i in 140:
		var x := rng.randf_range(-95.0, 95.0)
		var z := rng.randf_range(-95.0, 95.0)
		var h := height(x, z)
		if h < 0.3 or _near(x, z, D.VILLAGE, 16.0) or _near(x, z, D.RUINS, 10.0):
			continue
		if rng.randf() > 0.5 and not _near(x, z, D.RUINS, 30.0):
			continue
		var s := rng.randf_range(0.4, 1.6)
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s * rng.randf_range(0.8, 1.4), s * 0.7, s))
		xf.append(Transform3D(b, Vector3(x, h + 0.1, z)))
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 6
	sm.rings = 3
	parent.add_child(_mm(sm, xf, Color(0.55, 0.55, 0.58)))


static func _flowers(parent: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var cols := [Color(1, 0.85, 0.2), Color(1, 0.45, 0.6), Color(0.95, 0.95, 1), Color(0.6, 0.5, 1)]
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var bm := BoxMesh.new()
	bm.size = Vector3(0.14, 0.14, 0.14)
	mm.mesh = bm
	var xf: Array = []
	for i in 900:
		var center: Vector3 = D.MEADOW if i % 3 != 0 else D.VILLAGE
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * 26.0
		var x := center.x + cos(a) * r
		var z := center.z + sin(a) * r
		if _near(x, z, D.VILLAGE, 6.0):
			continue
		var h := height(x, z)
		if h < 0.8:
			continue
		xf.append([Transform3D(Basis.IDENTITY, Vector3(x, h + 0.12, z)), cols[i % cols.size()]])
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i][0])
		mm.set_instance_color(i, xf[i][1])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	mmi.material_override = m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)


static func _house(parent: Node3D, pos: Vector3, wall: Color, roof: Color) -> void:
	var h := Node3D.new()
	h.position = Vector3(pos.x, height(pos.x, pos.z) - 0.1, pos.z)
	var dir := -Vector3(pos.x, 0, pos.z).normalized()
	h.rotation.y = atan2(-dir.x, -dir.z)
	var beam := Color(0.36, 0.24, 0.15)
	h.add_child(LP.box(Vector3(4.5, 3.0, 4.0), wall, Vector3(0, 1.5, 0)))
	h.add_child(LP.prism(Vector3(5.2, 1.9, 4.7), roof, Vector3(0, 3.95, 0)))
	h.add_child(LP.box(Vector3(1.0, 1.9, 0.12), beam, Vector3(0, 0.95, -2.02)))
	h.add_child(LP.box(Vector3(0.6, 0.6, 0.1), Color(1.0, 0.85, 0.5), Vector3(-1.4, 1.8, -2.02), 0.8))
	h.add_child(LP.box(Vector3(0.6, 0.6, 0.1), Color(1.0, 0.85, 0.5), Vector3(1.4, 1.8, -2.02), 0.8))
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			h.add_child(LP.box(Vector3(0.22, 3.0, 0.22), beam, Vector3(2.2 * sx, 1.5, 1.95 * sz)))
	h.add_child(LP.box(Vector3(4.6, 0.2, 4.1), beam, Vector3(0, 3.0, 0)))
	h.add_child(LP.box(Vector3(0.5, 1.4, 0.5), Color(0.55, 0.52, 0.5), Vector3(1.4, 4.4, 1.0)))
	parent.add_child(h)


static func _village(parent: Node3D) -> void:
	var walls := [Color(0.93, 0.86, 0.7), Color(0.9, 0.8, 0.65), Color(0.95, 0.9, 0.8)]
	var roofs := [Color(0.72, 0.3, 0.22), Color(0.3, 0.42, 0.65), Color(0.55, 0.32, 0.5)]
	for k in 5:
		var ang := float(k) * TAU / 5.0 + 0.35
		_house(parent, Vector3(cos(ang) * 13.5, 0, sin(ang) * 13.5), walls[k % 3], roofs[k % 3])
	# Lagerfeuer
	var fire := Node3D.new()
	fire.position = Vector3(0, height(0, 0), 0)
	for i in 8:
		var a := float(i) * TAU / 8.0
		fire.add_child(LP.sphere(0.18, Color(0.5, 0.5, 0.52), Vector3(cos(a) * 0.7, 0.08, sin(a) * 0.7), 6))
	var log1 := LP.box(Vector3(1.1, 0.16, 0.16), Color(0.4, 0.26, 0.15), Vector3(0, 0.12, 0))
	log1.rotation.y = 0.6
	fire.add_child(log1)
	var log2 := LP.box(Vector3(1.1, 0.16, 0.16), Color(0.4, 0.26, 0.15), Vector3(0, 0.12, 0))
	log2.rotation.y = -0.6
	fire.add_child(log2)
	fire.add_child(LP.cyl(0.0, 0.35, 0.8, Color(1.0, 0.45, 0.1), Vector3(0, 0.5, 0), 6, 3.0))
	fire.add_child(LP.cyl(0.0, 0.2, 0.55, Color(1.0, 0.85, 0.3), Vector3(0, 0.45, 0), 6, 3.0))
	var sparks := CPUParticles3D.new()
	sparks.amount = 16
	sparks.lifetime = 1.4
	sparks.direction = Vector3.UP
	sparks.spread = 20.0
	sparks.initial_velocity_min = 0.6
	sparks.initial_velocity_max = 1.4
	sparks.gravity = Vector3(0, 0.3, 0)
	sparks.scale_amount_min = 0.3
	sparks.scale_amount_max = 0.6
	var sb := BoxMesh.new()
	sb.size = Vector3.ONE * 0.05
	sb.material = LP.mat(Color(1.0, 0.7, 0.2), 3.0)
	sparks.mesh = sb
	sparks.position.y = 0.6
	fire.add_child(sparks)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.3)
	light.light_energy = 1.6
	light.omni_range = 9.0
	light.position.y = 1.0
	fire.add_child(light)
	# Baumstämme als Sitzbänke
	for i in 3:
		var a := float(i) * TAU / 3.0 + 0.5
		var bench := LP.cyl(0.22, 0.22, 1.6, Color(0.45, 0.3, 0.18), Vector3(cos(a) * 2.2, 0.2, sin(a) * 2.2), 7)
		bench.rotation = Vector3(0, -a, PI / 2.0)
		fire.add_child(bench)
	parent.add_child(fire)


static func _ruins(parent: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 31337
	var root := Node3D.new()
	root.position = Vector3(D.RUINS.x, height(D.RUINS.x, D.RUINS.z), D.RUINS.z)
	var stone := Color(0.7, 0.68, 0.62)
	for i in 12:
		var a := float(i) * TAU / 12.0
		var p := Vector3(cos(a) * 10.0, 0, sin(a) * 10.0)
		if i % 5 == 3:
			var fallen := LP.box(Vector3(0.9, 3.5, 0.9), stone, p + Vector3(0, 0.45, 0))
			fallen.rotation = Vector3(PI / 2.0, a, 0)
			root.add_child(fallen)
			continue
		var h := rng.randf_range(1.5, 5.5)
		root.add_child(LP.box(Vector3(1.1, 0.4, 1.1), stone.darkened(0.15), p + Vector3(0, 0.2, 0)))
		root.add_child(LP.box(Vector3(0.9, h, 0.9), stone, p + Vector3(0, h / 2.0, 0)))
		if h > 4.5:
			root.add_child(LP.box(Vector3(1.2, 0.35, 1.2), stone.darkened(0.1), p + Vector3(0, h + 0.17, 0)))
	root.add_child(LP.cyl(4.0, 4.3, 0.3, stone.darkened(0.2), Vector3(0, 0.05, 0), 10))
	root.add_child(LP.box(Vector3(1.6, 1.0, 1.0), stone.darkened(0.3), Vector3(0, 0.6, 5.5)))
	root.add_child(LP.sphere(0.25, Color(0.5, 0.8, 1.0), Vector3(0, 1.35, 5.5), 8, 2.0))
	parent.add_child(root)


static func _sign(parent: Node3D, pos: Vector3, text: String) -> void:
	var s := Node3D.new()
	s.position = Vector3(pos.x, height(pos.x, pos.z), pos.z)
	var dir := -Vector3(pos.x, 0, pos.z).normalized()
	s.rotation.y = atan2(-dir.x, -dir.z) + PI
	s.add_child(LP.box(Vector3(0.15, 1.8, 0.15), Color(0.45, 0.3, 0.18), Vector3(0, 0.9, 0)))
	s.add_child(LP.box(Vector3(1.9, 0.75, 0.08), Color(0.6, 0.42, 0.25), Vector3(0, 1.6, 0)))
	var l := LP.label(text, 40, 0.0035)
	l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	l.position = Vector3(0, 1.6, 0.05)
	l.modulate = Color(1, 0.95, 0.85)
	s.add_child(l)
	parent.add_child(s)


static func _signs(parent: Node3D) -> void:
	_sign(parent, Vector3(-2, 0, 19), "Süden: Blumenwiese\nSchleime (Lv 1)")
	_sign(parent, Vector3(19, 0, -2), "Osten: Dunkelwald\nWölfe (Lv 3)")
	_sign(parent, Vector3(2, 0, -19), "Norden: Alte Ruinen\nSteingolem (Lv 7)")


static func _clouds(parent: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 16:
		var c := Node3D.new()
		c.position = Vector3(rng.randf_range(-150, 150), rng.randf_range(38, 55), rng.randf_range(-150, 150))
		for k in 3:
			var s := rng.randf_range(4.0, 9.0)
			c.add_child(LP.box(Vector3(s * 1.6, s * 0.5, s), Color(1, 1, 1), Vector3(k * 4.0 - 4.0, rng.randf_range(-1, 1), rng.randf_range(-2, 2)), 0.4))
		parent.add_child(c)
