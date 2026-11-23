extends Node3D
## Physikalische Schmiede an Gretas Esse (läuft nur auf dem Client).
##
## Ablauf:
##   1. Am Bedienfeld per Knopfdruck (mit der Hand antippen) Waffe und Material wählen
##      und "SCHMIEDEN" drücken. Der Server zieht das Erz ab, und ein Rohling liegt in der Glut.
##   2. Den Rohling in der Glut erhitzen (er glüht rot, dann orange, dann gelb).
##   3. Rohling greifen (Grip-Taste), auf den Amboss legen, Hammer greifen und zuschlagen.
##      Aufprallgeschwindigkeit und Hitze bestimmen die Qualität. Der Rohling verformt sich.
##   4. Die fertig geformte Klinge im Wasserfass abschrecken. Damit ist die Waffe fertig.
##
## Gegriffene Gegenstände folgen der Hand über Geschwindigkeiten (nicht angeheftet),
## sie kollidieren also mit Amboss, Esse usw. und können geworfen werden.

const D = preload("res://scripts/game_data.gd")
const LP = preload("res://scripts/lowpoly.gd")
const WG = preload("res://scripts/world_gen.gd")

const REQUIRED_STRIKES := 10.0
const IDEAL_SPEED := 4.5
const MIN_HEAT := 0.4
const COAL := Vector3(-1.0, 0.95, 0.0)
const ANVIL_TOP := Vector3(0.3, 0.66, 0.0)
const BARREL := Vector3(1.35, 0.0, 0.25)
const BARREL_R := 0.28
const WATER_Y := 0.7
const HAMMER_HOME := Vector3(0.95, 0.86, -0.45)
const INGOT_START := Vector3(0.07, 0.04, 0.22)
const INGOT_FINAL := [Vector3(0.06, 0.014, 0.72), Vector3(0.13, 0.03, 0.42), Vector3(0.1, 0.075, 0.36)]

var client
var hammer: RigidBody3D
var ingot: RigidBody3D = null
var ingot_shape: BoxShape3D
var ingot_mesh: BoxMesh
var ingot_mat: StandardMaterial3D
var panel_label: Label3D
var buttons: Array = []
var held: Dictionary = {}
var phys_mat := PhysicsMaterial.new()

var sel_type := 0
var sel_mat := 1
var forging := false
var forge_type := 0
var heat := 0.0
var progress := 0.0
var strikes := 0
var quality_sum := 0.0
var strike_cd := 0.0
var last_head := Vector3.ZERO
var head_speed := 0.0
var head_speed_prev := 0.0
var in_water_before := false
var status := "Wähle Waffe und Material, dann SCHMIEDEN drücken."
var panel_t := 0.0


func _ready() -> void:
	var f: Vector3 = D.FORGE
	position = Vector3(f.x, WG.height(f.x, f.z), f.z)
	phys_mat.friction = 0.9
	phys_mat.bounce = 0.05
	_build()
	_update_panel()


# ======================= Aufbau =======================

func _static_box(size: Vector3, pos: Vector3, color: Color, visible_mesh: bool = true) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.position = pos
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	sb.add_child(cs)
	if visible_mesh:
		sb.add_child(LP.box(size, color))
	add_child(sb)
	return sb


func _build() -> void:
	var stone := Color(0.5, 0.48, 0.46)
	var wood := Color(0.45, 0.3, 0.18)
	# Unsichtbarer Boden, damit nichts durch das Gelände fällt
	_static_box(Vector3(7, 0.4, 7), Vector3(0, -0.2, 0), wood, false)
	# Holzboden (Optik)
	add_child(LP.box(Vector3(3.6, 0.04, 2.4), Color(0.5, 0.36, 0.24), Vector3(0.2, 0.0, 0.0)))

	# Esse
	_static_box(Vector3(1.2, 0.9, 0.9), Vector3(-1.0, 0.45, 0), stone)
	add_child(LP.box(Vector3(0.9, 0.05, 0.6), Color(1.0, 0.35, 0.08), Vector3(-1.0, 0.92, 0), 3.0))
	add_child(LP.box(Vector3(1.3, 0.12, 1.0), stone.darkened(0.2), Vector3(-1.0, 2.0, -0.05)))
	add_child(LP.box(Vector3(0.45, 1.3, 0.45), stone.darkened(0.1), Vector3(-1.0, 2.7, -0.1)))
	for sx in [-1, 1]:
		add_child(LP.box(Vector3(0.1, 1.1, 0.1), stone.darkened(0.3), Vector3(-1.0 + 0.55 * sx, 1.45, -0.4)))
	var flames := CPUParticles3D.new()
	flames.amount = 20
	flames.lifetime = 0.6
	flames.direction = Vector3.UP
	flames.spread = 15.0
	flames.initial_velocity_min = 0.3
	flames.initial_velocity_max = 0.8
	flames.gravity = Vector3(0, 0.5, 0)
	flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	flames.emission_box_extents = Vector3(0.4, 0.01, 0.25)
	flames.scale_amount_min = 0.4
	flames.scale_amount_max = 1.0
	var fm := BoxMesh.new()
	fm.size = Vector3.ONE * 0.06
	fm.material = LP.mat(Color(1.0, 0.55, 0.15), 3.0)
	flames.mesh = fm
	flames.position = Vector3(-1.0, 0.95, 0)
	add_child(flames)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.5, 0.2)
	glow.light_energy = 1.2
	glow.omni_range = 3.0
	glow.position = Vector3(-1.0, 1.3, 0.2)
	add_child(glow)

	# Amboss
	_static_box(Vector3(0.3, 0.5, 0.3), Vector3(0.3, 0.25, 0), Color(0.25, 0.25, 0.28))
	_static_box(Vector3(0.6, 0.16, 0.26), Vector3(0.3, 0.58, 0), Color(0.3, 0.3, 0.34))
	var horn := LP.cyl(0.0, 0.08, 0.3, Color(0.3, 0.3, 0.34), Vector3(0.74, 0.6, 0), 8)
	horn.rotation.z = PI / 2.0
	add_child(horn)
	add_child(LP.box(Vector3(0.45, 0.1, 0.45), wood, Vector3(0.3, 0.05, 0)))

	# Wasserfass: Boden + vier Wände als Kollision, innen liegt Wasser
	var bx: float = BARREL.x
	var bz: float = BARREL.z
	_static_box(Vector3(0.56, 0.4, 0.56), Vector3(bx, 0.2, bz), wood, false)
	_static_box(Vector3(0.04, 0.78, 0.64), Vector3(bx - 0.31, 0.39, bz), wood, false)
	_static_box(Vector3(0.04, 0.78, 0.64), Vector3(bx + 0.31, 0.39, bz), wood, false)
	_static_box(Vector3(0.64, 0.78, 0.04), Vector3(bx, 0.39, bz - 0.31), wood, false)
	_static_box(Vector3(0.64, 0.78, 0.04), Vector3(bx, 0.39, bz + 0.31), wood, false)
	var barrel_mesh := CylinderMesh.new()
	barrel_mesh.top_radius = 0.34
	barrel_mesh.bottom_radius = 0.3
	barrel_mesh.height = 0.78
	barrel_mesh.radial_segments = 12
	barrel_mesh.cap_top = false
	var bm := StandardMaterial3D.new()
	bm.albedo_color = wood
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	var barrel := MeshInstance3D.new()
	barrel.mesh = barrel_mesh
	barrel.material_override = bm
	barrel.position = Vector3(bx, 0.39, bz)
	add_child(barrel)
	add_child(LP.cyl(0.32, 0.32, 0.02, Color(0.25, 0.5, 0.8), Vector3(bx, WATER_Y, bz), 12, 0.3))

	# Werkbank für den Hammer
	_static_box(Vector3(0.5, 0.78, 0.35), Vector3(0.95, 0.39, -0.45), wood)

	# Bedienfeld
	add_child(LP.box(Vector3(1.5, 0.62, 0.04), Color(0.3, 0.22, 0.15), Vector3(0.3, 1.33, -0.78)))
	add_child(LP.box(Vector3(0.08, 1.1, 0.08), wood, Vector3(-0.38, 0.55, -0.8)))
	add_child(LP.box(Vector3(0.08, 1.1, 0.08), wood, Vector3(0.98, 0.55, -0.8)))
	add_child(LP.box(Vector3(1.5, 0.05, 0.2), wood, Vector3(0.3, 0.93, -0.7)))
	panel_label = LP.label("", 30, 0.0016)
	panel_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	panel_label.position = Vector3(0.3, 1.33, -0.755)
	panel_label.modulate = Color(1.0, 0.93, 0.8)
	add_child(panel_label)
	var defs := [["type_prev", "< Waffe"], ["type_next", "Waffe >"], ["mat_prev", "< Material"],
		["mat_next", "Material >"], ["go", "SCHMIEDEN"]]
	for i in defs.size():
		var x := -0.26 + i * 0.28
		var col := Color(0.8, 0.3, 0.2) if defs[i][0] == "go" else Color(0.8, 0.65, 0.3)
		var b := LP.box(Vector3(0.14, 0.06, 0.08), col, Vector3(x, 0.98, -0.66), 0.3)
		add_child(b)
		var l := LP.label(defs[i][1], 26, 0.0016)
		l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		l.position = Vector3(x, 1.07, -0.7)
		add_child(l)
		buttons.append({"id": defs[i][0], "node": b, "label": l, "armed": true, "home_z": -0.66})

	# Hammer (physikalisch)
	hammer = RigidBody3D.new()
	hammer.mass = 1.2
	hammer.physics_material_override = phys_mat
	hammer.continuous_cd = true
	hammer.contact_monitor = true
	hammer.max_contacts_reported = 4
	# Schwerpunkt im Hammerkopf: fällt und kippt wie ein echter Hammer
	hammer.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	hammer.center_of_mass = Vector3(0, 0, -0.27)
	_add_shape(hammer, Vector3(0.035, 0.035, 0.34), Vector3(0, 0, -0.15))
	_add_shape(hammer, Vector3(0.07, 0.15, 0.08), Vector3(0, 0, -0.33))
	hammer.add_child(LP.box(Vector3(0.035, 0.035, 0.34), wood, Vector3(0, 0, -0.15)))
	hammer.add_child(LP.box(Vector3(0.07, 0.15, 0.08), Color(0.35, 0.35, 0.38), Vector3(0, 0, -0.33)))
	add_child(hammer)
	hammer.body_entered.connect(_on_hammer_contact)
	_reset_hammer()


func _add_shape(body: CollisionObject3D, size: Vector3, pos: Vector3) -> BoxShape3D:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position = pos
	body.add_child(cs)
	return shape


func _reset_hammer() -> void:
	hammer.transform = Transform3D(Basis(Vector3.FORWARD, PI / 2.0), HAMMER_HOME)
	hammer.linear_velocity = Vector3.ZERO
	hammer.angular_velocity = Vector3.ZERO


func _spawn_ingot() -> void:
	_remove_ingot()
	ingot = RigidBody3D.new()
	ingot.mass = 1.0
	ingot.physics_material_override = phys_mat
	ingot.continuous_cd = true
	ingot_shape = _add_shape(ingot, INGOT_START, Vector3.ZERO)
	ingot_mesh = BoxMesh.new()
	ingot_mesh.size = INGOT_START
	ingot_mat = StandardMaterial3D.new()
	ingot_mat.emission_enabled = true
	ingot_mat.roughness = 0.4
	ingot_mat.metallic = 0.6
	var mi := MeshInstance3D.new()
	mi.mesh = ingot_mesh
	mi.material_override = ingot_mat
	ingot.add_child(mi)
	add_child(ingot)
	ingot.position = COAL + Vector3(0, 0.08, 0)
	_update_ingot_color()


func _remove_ingot() -> void:
	for key in held.keys():
		if held[key]["body"] == ingot:
			held.erase(key)
	if ingot != null:
		ingot.queue_free()
	ingot = null


# ======================= Greifen =======================

func holding(key: String) -> bool:
	return held.has(key)


func held_body(key: String) -> RigidBody3D:
	return held[key]["body"] if held.has(key) else null


func grab(hand: Node3D, key: String) -> bool:
	if held.has(key):
		return true
	var radius := 0.16 if client.vr else 0.9
	var best: RigidBody3D = null
	var best_d := radius
	for b in [hammer, ingot]:
		if b == null or _is_held(b):
			continue
		var d: float = (b as RigidBody3D).global_position.distance_to(hand.global_position)
		if d < best_d:
			best_d = d
			best = b
	if best == null:
		return false
	var offset: Transform3D
	if best == hammer:
		offset = Transform3D.IDENTITY
	elif client.vr:
		offset = hand.global_transform.affine_inverse() * best.global_transform
	else:
		offset = Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.15))
	best.gravity_scale = 0.0
	best.sleeping = false
	held[key] = {"body": best, "offset": offset, "hand": hand}
	client._haptic(hand, 0.4, 0.05)
	return true


func release(key: String) -> void:
	if not held.has(key):
		return
	var b: RigidBody3D = held[key]["body"]
	held.erase(key)
	if is_instance_valid(b):
		b.gravity_scale = 1.0
		b.linear_velocity = b.linear_velocity.limit_length(12.0)
		b.angular_velocity = b.angular_velocity.limit_length(20.0)


func release_all() -> void:
	for key in held.keys():
		release(key)


func _is_held(b: RigidBody3D) -> bool:
	for key in held:
		if held[key]["body"] == b:
			return true
	return false


func _follow_hands(delta: float) -> void:
	for key in held.keys():
		var h: Dictionary = held[key]
		var b: RigidBody3D = h["body"]
		var hand: Node3D = h["hand"]
		if not is_instance_valid(b):
			held.erase(key)
			continue
		var offset: Transform3D = h["offset"]
		var target := hand.global_transform * offset
		var dp := target.origin - b.global_position
		if dp.length() > 0.7:
			# Zu weit weg (z. B. Teleport): direkt hinsetzen
			b.global_transform = target
			b.linear_velocity = Vector3.ZERO
			b.angular_velocity = Vector3.ZERO
			continue
		b.linear_velocity = (dp / delta).limit_length(25.0)
		var q_target := target.basis.get_rotation_quaternion()
		var q_cur := b.global_basis.get_rotation_quaternion()
		var dq := (q_target * q_cur.inverse()).normalized()
		var ang := dq.get_angle()
		if ang > PI:
			ang -= TAU
		if absf(ang) > 0.001:
			b.angular_velocity = (dq.get_axis() * ang / delta).limit_length(40.0)
		else:
			b.angular_velocity = Vector3.ZERO


# ======================= Knöpfe =======================

func _poke_buttons() -> void:
	if not client.vr:
		return
	for b in buttons:
		var node: Node3D = b["node"]
		var p := node.global_position
		var dl: float = client.lhand.global_position.distance_to(p)
		var dr: float = client.rhand.global_position.distance_to(p)
		var d := minf(dl, dr)
		if d < 0.07 and b["armed"]:
			b["armed"] = false
			client._haptic(client.lhand if dl < dr else client.rhand, 0.5, 0.05)
			_press(b)
		elif d > 0.14:
			b["armed"] = true


## Desktop: Knopf in Blickrichtung drücken. Gibt true zurück, wenn einer getroffen wurde.
func press_ray(origin: Vector3, dir: Vector3) -> bool:
	for b in buttons:
		var node: Node3D = b["node"]
		var p := node.global_position
		var t := (p - origin).dot(dir)
		if t > 0.0 and t < 3.0 and (origin + dir * t).distance_to(p) < 0.09:
			_press(b)
			return true
	return false


func _press(b: Dictionary) -> void:
	var node: Node3D = b["node"]
	var tw := node.create_tween()
	tw.tween_property(node, "position:z", float(b["home_z"]) - 0.025, 0.06)
	tw.tween_property(node, "position:z", float(b["home_z"]), 0.1)
	client._play("click", node.global_position)
	match str(b["id"]):
		"type_prev":
			sel_type = wrapi(sel_type - 1, 0, D.WEAPON_TYPES.size())
		"type_next":
			sel_type = wrapi(sel_type + 1, 0, D.WEAPON_TYPES.size())
		"mat_prev":
			sel_mat = wrapi(sel_mat - 2, 0, 3) + 1
		"mat_next":
			sel_mat = wrapi(sel_mat, 0, 3) + 1
		"go":
			if forging:
				Game.rpc_id(1, "req_forge_cancel")
				_remove_ingot()
				forging = false
				status = "Abgebrochen. Das Erz bekommst du zurück."
			else:
				Game.rpc_id(1, "req_forge_start", sel_type, sel_mat)
				status = "Greta legt einen Rohling bereit ..."
	_update_panel()


# ======================= Schmieden =======================

func on_forge_started(wtype: int, mat: int) -> void:
	forging = true
	forge_type = wtype
	sel_type = wtype
	sel_mat = mat
	heat = 0.0
	progress = 0.0
	strikes = 0
	quality_sum = 0.0
	_spawn_ingot()
	status = "Der Rohling liegt in der Glut (links). Warte, bis er hell glüht!"
	_update_panel()


func _update_ingot_color() -> void:
	if ingot == null:
		return
	var cold := Color(0.38, 0.38, 0.42)
	var c: Color
	if heat < 0.35:
		c = cold.lerp(Color(0.6, 0.12, 0.05), heat / 0.35)
	elif heat < 0.7:
		c = Color(0.6, 0.12, 0.05).lerp(Color(1.0, 0.45, 0.08), (heat - 0.35) / 0.35)
	else:
		c = Color(1.0, 0.45, 0.08).lerp(Color(1.0, 0.9, 0.55), (heat - 0.7) / 0.3)
	ingot_mat.albedo_color = c
	ingot_mat.emission = c
	ingot_mat.emission_energy_multiplier = heat * 4.0


func _reshape() -> void:
	var size := INGOT_START.lerp(INGOT_FINAL[clampi(forge_type, 0, 2)], clampf(progress, 0.0, 1.0))
	ingot_shape.size = size
	ingot_mesh.size = size


func _holder_hand(b: RigidBody3D) -> Node3D:
	for key in held:
		if held[key]["body"] == b:
			return held[key]["hand"]
	return client.rhand


func _on_hammer_contact(body: Node) -> void:
	if ingot == null or body != ingot or strike_cd > 0.0:
		return
	var spd := maxf(head_speed, head_speed_prev)
	if spd < 1.2:
		return
	strike_cd = 0.12
	var pos := ingot.global_position
	client._play("clang", pos)
	client._haptic(_holder_hand(hammer), clampf(spd / 6.0, 0.3, 1.0), 0.08)
	LP.burst(client.fx_root, pos + Vector3(0, 0.03, 0), Color(1.0, 0.7, 0.2), int(6 + spd * 3.0), spd * 0.5, 0.4, 0.5)
	var lp := to_local(pos)
	var on_anvil := absf(lp.x - ANVIL_TOP.x) < 0.36 and absf(lp.z - ANVIL_TOP.z) < 0.2 \
		and lp.y > ANVIL_TOP.y - 0.04 and lp.y < ANVIL_TOP.y + 0.2
	if not on_anvil:
		status = "Leg den Rohling auf den Amboss (Mitte)!"
	elif progress >= 1.0:
		status = "Fertig geformt! Ab damit ins Wasserfass (rechts)."
	elif heat < MIN_HEAT:
		status = "Zu kalt! Zurück in die Glut damit."
	else:
		var force_score := 1.0 - clampf(absf(spd - IDEAL_SPEED) / IDEAL_SPEED, 0.0, 1.0)
		var heat_score := clampf((heat - MIN_HEAT) / 0.45, 0.0, 1.0)
		var hit_q := 0.6 * force_score + 0.4 * heat_score
		strikes += 1
		quality_sum += hit_q
		progress = minf(1.0, progress + (0.5 + 0.5 * force_score) / REQUIRED_STRIKES)
		heat = maxf(0.0, heat - 0.05)
		_reshape()
		var verdict := "Perfekt!"
		if force_score < 0.8:
			verdict = "Zu schwach" if spd < IDEAL_SPEED else "Zu fest"
		status = "Schlag %d (%.1f m/s): %s" % [strikes, spd, verdict]
		if progress >= 1.0:
			status += "\nGeformt! Jetzt im Wasserfass abschrecken."
	_update_panel()


func _quench() -> void:
	var q := quality_sum / maxf(float(strikes), 1.0)
	if heat < 0.3:
		q *= 0.85
	q = clampf(q, 0.0, 1.0)
	var pos := ingot.global_position
	LP.burst(client.fx_root, pos + Vector3(0, 0.3, 0), Color(0.9, 0.9, 0.95), 40, 1.5, 1.5, 1.5)
	client._play("steam", pos)
	Game.rpc_id(1, "req_forge_finish", strikes, q)
	_remove_ingot()
	forging = false
	status = "Zischhh! Deine Waffe ist fertig. Qualität: %d %%" % roundi(q * 100.0)
	_update_panel()


func _physics_process(delta: float) -> void:
	_follow_hands(delta)
	strike_cd = maxf(strike_cd - delta, 0.0)
	var hp := hammer.to_global(Vector3(0, 0, -0.33))
	head_speed_prev = head_speed
	head_speed = (hp - last_head).length() / maxf(delta, 0.0001)
	last_head = hp
	# Herausgefallenes zurücksetzen
	if not _is_held(hammer):
		var lh := to_local(hammer.global_position)
		if lh.y < -1.0 or lh.length() > 8.0:
			_reset_hammer()
	if ingot != null:
		var lp := to_local(ingot.global_position)
		if not _is_held(ingot) and (lp.y < -1.0 or lp.length() > 8.0):
			ingot.position = COAL + Vector3(0, 0.08, 0)
			ingot.linear_velocity = Vector3.ZERO
		var in_coals := absf(lp.x - COAL.x) < 0.45 and absf(lp.z - COAL.z) < 0.3 \
			and lp.y > COAL.y - 0.1 and lp.y < COAL.y + 0.3
		if in_coals:
			heat = minf(1.0, heat + 0.22 * delta)
		else:
			heat = maxf(0.0, heat - 0.035 * delta)
		_update_ingot_color()
		var in_water := Vector2(lp.x - BARREL.x, lp.z - BARREL.z).length() < BARREL_R and lp.y < WATER_Y
		if in_water and not in_water_before:
			if progress >= 1.0:
				_quench()
				in_water_before = false
				return
			if heat > 0.2:
				heat = 0.0
				client._play("steam", ingot.global_position)
				status = "Zu früh abgeschreckt! Erst fertig schmieden, wieder erhitzen."
		in_water_before = in_water


func _process(delta: float) -> void:
	_poke_buttons()
	panel_t -= delta
	if panel_t <= 0.0:
		panel_t = 0.25
		if client.camera and client.camera.global_position.distance_to(global_position) < 8.0:
			_update_panel()
		elif not held.is_empty():
			release_all()


func _update_panel() -> void:
	if panel_label == null:
		return
	var st: Dictionary = client.stats
	var ores: Dictionary = st.get("ores", {})
	var t := "SCHMIEDE\n"
	t += "Waffe: %s     Material: %s\n" % [D.WEAPON_TYPES[sel_type]["name"], D.MATERIALS[sel_mat]]
	t += "Rezept: %s\n" % D.recipe_text(sel_mat)
	t += "Dein Erz: Eisen %d   Gold %d   Kristall %d\n" % [
		int(ores.get("iron", 0)), int(ores.get("gold", 0)), int(ores.get("crystal", 0))]
	if forging:
		var q := quality_sum / maxf(float(strikes), 1.0)
		t += "Hitze %d %%   Form %d %%   Schläge %d   Qualität %d %%\n" % [
			roundi(heat * 100.0), roundi(progress * 100.0), strikes, roundi(q * 100.0)]
	t += status
	panel_label.text = t
	for b in buttons:
		if b["id"] == "go":
			var bl: Label3D = b["label"]
			bl.text = "ABBRECHEN" if forging else "SCHMIEDEN"
