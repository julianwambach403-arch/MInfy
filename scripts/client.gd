extends Node3D
## Spieler-Client: VR-Rig (Meta Quest 3 / PC-VR) oder Desktop-Testmodus,
## Startmenü, Darstellung anderer Spieler und Gegner, Effekte, HUD.

const D = preload("res://scripts/game_data.gd")
const Cfg = preload("res://scripts/config.gd")
const LP = preload("res://scripts/lowpoly.gd")
const WG = preload("res://scripts/world_gen.gd")
const Sfx = preload("res://scripts/sfx.gd")

const MOVE_SPEED := 3.2
const SNAP_ANGLE := 0.5236
const SKIN := Color(0.96, 0.8, 0.66)
const CONNECT_TIMEOUT := 10.0

var opts: Dictionary = {}
var vr := false
var origin: XROrigin3D
var camera: Camera3D
var lhand: Node3D
var rhand: Node3D
var sword: Node3D
var sword_tip: Node3D
var orb: MeshInstance3D
var wrist: Label3D
var banner: Label3D
var lobby_root: Node3D
var lobby_label: Label3D
var fx_root: Node3D
var remotes_root: Node3D
var enemies_root: Node3D

var state := "lobby"
var lobby_row := 0
var name_idx := 0
var color_idx := 0
var server_idx := 0
var lobby_status := ""
var connect_t := 0.0
var names: Array = []
var servers: Array = []

var my_id := 0
var stats: Dictionary = {}
var remotes: Dictionary = {}
var enemies: Dictionary = {}
var fireballs: Dictionary = {}
var npcs: Dictionary = {}
var hit_cd: Dictionary = {}
var banner_lines: Array = []
var sounds: Dictionary = {}
var last_tip := Vector3.ZERO
var pose_timer := 0.0
var latch_x := false
var latch_y := false
var cast_cd := 0.0
var swing_cd := 0.0
var woosh_cd := 0.0
var time := 0.0
var skill_idx := 0
var skill_cds: Dictionary = {}
var wrist_t := 0.0


func _ready() -> void:
	names = Cfg.NAMES.duplicate()
	if opts.has("name"):
		names.push_front(str(opts["name"]))
	servers = Cfg.SERVERS.duplicate(true)
	if opts.has("host"):
		servers.push_front(["Startparameter", str(opts["host"]), int(opts.get("port", Cfg.SERVER_PORT))])
	_load_prefs()
	if opts.has("name"):
		name_idx = 0
	if opts.has("host"):
		server_idx = 0
	sounds = Sfx.build_all()
	WG.build(self)
	fx_root = Node3D.new()
	add_child(fx_root)
	remotes_root = Node3D.new()
	add_child(remotes_root)
	enemies_root = Node3D.new()
	add_child(enemies_root)
	vr = _init_xr()
	_build_npcs()
	_build_rig()
	_build_lobby()
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	if opts.has("autoconnect"):
		_connect()


# ======================= XR / Rig =======================

func _init_xr() -> bool:
	if opts.has("desktop"):
		return false
	var xri := XRServer.find_interface("OpenXR")
	if xri != null and xri.is_initialized():
		get_viewport().use_xr = true
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		var oxr := xri as OpenXRInterface
		if oxr:
			oxr.session_begun.connect(_on_xr_session_begun.bind(oxr))
		print("[Client] OpenXR aktiv – VR-Modus.")
		return true
	print("[Client] Kein VR-Headset gefunden – Desktop-Modus (WASD + Maus).")
	return false


func _on_xr_session_begun(oxr: OpenXRInterface) -> void:
	var rates := oxr.get_available_display_refresh_rates()
	if rates.has(90.0):
		oxr.display_refresh_rate = 90.0
		Engine.physics_ticks_per_second = 90


func _build_rig() -> void:
	origin = XROrigin3D.new()
	add_child(origin)
	origin.current = true
	var sp := D.SPAWN
	origin.position = Vector3(sp.x, WG.height(sp.x, sp.z), sp.z)
	if vr:
		camera = XRCamera3D.new()
		origin.add_child(camera)
		var l := XRController3D.new()
		l.tracker = &"left_hand"
		origin.add_child(l)
		l.button_pressed.connect(_on_left_button)
		lhand = l
		var r := XRController3D.new()
		r.tracker = &"right_hand"
		origin.add_child(r)
		r.button_pressed.connect(_on_right_button)
		rhand = r
	else:
		camera = Camera3D.new()
		camera.position.y = 1.7
		origin.add_child(camera)
		lhand = Node3D.new()
		lhand.position = Vector3(-0.28, -0.26, -0.45)
		camera.add_child(lhand)
		rhand = Node3D.new()
		rhand.position = Vector3(0.3, -0.3, -0.42)
		camera.add_child(rhand)
	camera.current = true
	camera.near = 0.05
	camera.far = 400.0
	lhand.add_child(LP.make_hand(SKIN))
	rhand.add_child(LP.make_hand(SKIN))
	sword = LP.make_sword(0)
	rhand.add_child(sword)
	sword_tip = Node3D.new()
	sword_tip.position = Vector3(0, 0, -0.88)
	sword.add_child(sword_tip)
	orb = LP.sphere(0.045, Color(1.0, 0.5, 0.15), Vector3(0, 0.03, -0.08), 8, 3.0)
	lhand.add_child(orb)

	wrist = LP.label("", 32, 0.0007)
	wrist.position = Vector3(0, 0.1, 0.06) if vr else Vector3(0.02, 0.16, 0.0)
	wrist.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	wrist.no_depth_test = true
	wrist.render_priority = 10
	wrist.outline_render_priority = 9
	lhand.add_child(wrist)

	banner = LP.label("", 40, 0.0012)
	banner.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	banner.position = Vector3(0, 0.28, -1.5)
	banner.no_depth_test = true
	banner.render_priority = 10
	banner.outline_render_priority = 9
	banner.modulate = Color(1, 0.95, 0.7)
	camera.add_child(banner)


func _snap_turn(angle: float) -> void:
	var t := origin.global_transform
	var pivot := camera.global_position
	t.origin -= pivot
	t = t.rotated(Vector3.UP, angle)
	t.origin += pivot
	origin.global_transform = t


# ======================= Startmenü =======================

func _build_lobby() -> void:
	lobby_root = Node3D.new()
	lobby_root.position = Vector3(0, 1.55, -2.2)
	origin.add_child(lobby_root)
	var q := QuadMesh.new()
	q.size = Vector2(2.6, 1.6)
	var back := MeshInstance3D.new()
	back.mesh = q
	back.material_override = LP.unshaded(Color(0.08, 0.1, 0.2, 0.88))
	back.position.z = -0.02
	lobby_root.add_child(back)
	lobby_label = LP.label("", 56, 0.0021)
	lobby_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	lobby_root.add_child(lobby_label)
	_update_lobby()


func _update_lobby() -> void:
	var srv: Array = servers[server_idx]
	var rows := [
		"Name:   <  %s  >" % names[name_idx],
		"Farbe:  <  %s  >" % D.COLOR_NAMES[color_idx],
		"Server: <  %s  (%s)  >" % [srv[0], srv[1]],
	]
	var t := "M I N F Y\nein kleines VR-Abenteuer\n\n"
	for i in rows.size():
		t += (">> " if i == lobby_row else "     ") + rows[i] + "\n"
	if vr:
		t += "\nRechter Stick: auswählen / ändern\n[A] Verbinden"
	else:
		t += "\nPfeiltasten: auswählen / ändern\n[Enter] Verbinden"
	if lobby_status != "":
		t += "\n\n" + lobby_status
	lobby_label.text = t


func _lobby_change(dir: int) -> void:
	match lobby_row:
		0:
			name_idx = wrapi(name_idx + dir, 0, names.size())
		1:
			color_idx = wrapi(color_idx + dir, 0, D.COLORS.size())
		2:
			server_idx = wrapi(server_idx + dir, 0, servers.size())
	_update_lobby()


func _lobby_vr_input() -> void:
	if not vr:
		return
	var rs: Vector2 = (rhand as XRController3D).get_vector2("primary")
	if absf(rs.y) > 0.7:
		if not latch_y:
			latch_y = true
			lobby_row = wrapi(lobby_row - int(signf(rs.y)), 0, 3)
			_update_lobby()
	elif absf(rs.y) < 0.3:
		latch_y = false
	if absf(rs.x) > 0.7:
		if not latch_x:
			latch_x = true
			_lobby_change(int(signf(rs.x)))
	elif absf(rs.x) < 0.3:
		latch_x = false


func _load_prefs() -> void:
	var cf := ConfigFile.new()
	if cf.load("user://prefs.cfg") == OK:
		name_idx = clampi(int(cf.get_value("lobby", "name", 0)), 0, names.size() - 1)
		color_idx = clampi(int(cf.get_value("lobby", "color", 0)), 0, D.COLORS.size() - 1)
		server_idx = clampi(int(cf.get_value("lobby", "server", 0)), 0, servers.size() - 1)


func _save_prefs() -> void:
	var cf := ConfigFile.new()
	cf.set_value("lobby", "name", name_idx)
	cf.set_value("lobby", "color", color_idx)
	cf.set_value("lobby", "server", server_idx)
	cf.save("user://prefs.cfg")


func _connect() -> void:
	if state != "lobby":
		return
	var srv: Array = servers[server_idx]
	var err: int = Game.connect_to(str(srv[1]), int(srv[2]))
	if err != OK:
		lobby_status = "Fehler beim Verbinden (Code %d)." % err
		_update_lobby()
		return
	_save_prefs()
	state = "connecting"
	connect_t = 0.0
	lobby_status = "Verbinde mit %s:%d ..." % [srv[1], srv[2]]
	_update_lobby()


func _on_connected() -> void:
	lobby_status = "Verbunden! Betrete die Welt ..."
	_update_lobby()
	Game.rpc_id(1, "req_join", str(names[name_idx]), color_idx)


func _on_connection_failed() -> void:
	_back_to_lobby("Server nicht erreichbar. Läuft der Server? Ist UDP-Port %d offen?" % int(servers[server_idx][2]))


func _on_server_disconnected() -> void:
	_back_to_lobby("Verbindung zum Server verloren.")


func _back_to_lobby(status: String) -> void:
	Game.disconnect_peer()
	state = "lobby"
	lobby_status = status
	lobby_root.visible = true
	for a in remotes.values():
		(a["root"] as Node3D).queue_free()
	remotes.clear()
	for e in enemies.values():
		(e["node"] as Node3D).queue_free()
	enemies.clear()
	for f in fireballs.values():
		(f["node"] as Node3D).queue_free()
	fireballs.clear()
	_update_lobby()


# ======================= Server-Ereignisse =======================

func on_joined(id: int, st: Dictionary) -> void:
	my_id = id
	state = "playing"
	lobby_root.visible = false
	lobby_status = ""
	on_stats(st)
	_say("Willkommen, %s! Sprich mit Ältestem Bruno am Lagerfeuer." % st["name"])
	if not vr:
		_say("WASD laufen, Maus schauen, Links: Schwert, Rechts: Fähigkeit, 1-6/Tab: wählen, E: Sprechen")


func on_join_failed(reason: String) -> void:
	_back_to_lobby(reason)


func on_stats(st: Dictionary) -> void:
	var old_sword: int = stats.get("sword", -1)
	var old_level: int = stats.get("level", 0)
	stats = st
	if int(st["sword"]) != old_sword:
		LP.set_sword_tier(sword, int(st["sword"]))
	if int(st["level"]) != old_level:
		var sk: Dictionary = D.SKILLS[skill_idx]
		if int(sk["level"]) > int(st["level"]):
			skill_idx = 0
		_update_orb()
	_refresh_wrist()


func _skill_ready_in(i: int) -> float:
	return maxf(float(skill_cds.get(i, 0.0)), 0.0)


func _refresh_wrist() -> void:
	if stats.is_empty():
		return
	var st := stats
	var t := "%s  -  Level %d\nHP %d/%d    Mana %d/%d\nEP %d/%d    Gold %d\n%s" % [
		st["name"], st["level"], st["hp"], st["max_hp"], st["mana"], st["max_mana"],
		st["xp"], st["xp_need"], st["gold"], st["sword_name"]]
	var sk: Dictionary = D.SKILLS[skill_idx]
	var wait := _skill_ready_in(skill_idx)
	var status := "bereit" if wait <= 0.0 else "%.0fs" % ceilf(wait)
	if float(st["mana"]) < float(sk["mana"]):
		status = "zu wenig Mana"
	t += "\nFähigkeit: %s (%d Mana) - %s" % [sk["name"], int(sk["mana"]), status]
	var unlocked := 0
	for s2 in D.SKILLS:
		if int(s2["level"]) <= int(st["level"]):
			unlocked += 1
	t += "\n%d/%d Fähigkeiten freigeschaltet" % [unlocked, D.SKILLS.size()]
	if st.get("shield", false):
		t += "\nSCHUTZSCHILD AKTIV"
	if st["quest_done"]:
		t += "\nAlle Aufgaben erledigt!"
	elif st["quest_active"]:
		t += "\nAufgabe: %s %d/%d" % [st["quest_title"], st["quest_progress"], st["quest_count"]]
	else:
		t += "\nSprich mit Bruno für eine Aufgabe"
	wrist.text = t
	var hp_ratio := float(st["hp"]) / maxf(float(st["max_hp"]), 1.0)
	wrist.modulate = Color(1, 1, 1) if hp_ratio > 0.3 else Color(1, 0.5, 0.5)
	orb.visible = float(st["mana"]) >= float(sk["mana"]) and wait <= 0.0


func _update_orb() -> void:
	var sk: Dictionary = D.SKILLS[skill_idx]
	orb.material_override = LP.mat(sk["color"], 3.0)


func _select_skill(dir: int) -> void:
	var lvl: int = stats.get("level", 1)
	for i in D.SKILLS.size():
		skill_idx = wrapi(skill_idx + dir, 0, D.SKILLS.size())
		if int(D.SKILLS[skill_idx]["level"]) <= lvl:
			break
	_choose_skill(skill_idx)


func _choose_skill(i: int) -> void:
	var sk: Dictionary = D.SKILLS[i]
	if int(sk["level"]) > int(stats.get("level", 1)):
		_say("%s wird mit Level %d freigeschaltet." % [sk["name"], sk["level"]])
		return
	skill_idx = i
	_update_orb()
	_refresh_wrist()
	_say("Fähigkeit: %s - %s" % [sk["name"], sk["desc"]])
	_haptic(lhand, 0.3, 0.05)


func on_snapshot(pl: Array, en: Array) -> void:
	if state != "playing":
		return
	var seen := {}
	for p in pl:
		var pid: int = p[0]
		seen[pid] = true
		if pid == my_id:
			continue
		if not remotes.has(pid):
			remotes[pid] = _make_avatar(int(p[2]))
			var a0: Dictionary = remotes[pid]
			var h0: Node3D = a0["head"]
			var l0: Node3D = a0["lh"]
			var r0: Node3D = a0["rh"]
			h0.position = p[3]
			l0.position = p[5]
			r0.position = p[7]
		var a: Dictionary = remotes[pid]
		a["t"] = p
	for pid in remotes.keys():
		if not seen.has(pid):
			(remotes[pid]["root"] as Node3D).queue_free()
			remotes.erase(pid)
	for arr in en:
		var eid: int = arr[0]
		var tname: String = D.ENEMY_TYPES[int(arr[1])]
		if not enemies.has(eid):
			enemies[eid] = _make_enemy(tname)
			var new_node: Node3D = enemies[eid]["node"]
			new_node.position = arr[2]
		var e: Dictionary = enemies[eid]
		var node: Node3D = e["node"]
		var alive: bool = arr[6]
		if alive and not e["alive"]:
			node.position = arr[2]
		node.visible = alive
		e["alive"] = alive
		e["tpos"] = arr[2]
		e["tyaw"] = arr[3]
		if int(arr[4]) != int(e["hp"]):
			e["hp"] = int(arr[4])
			var def: Dictionary = D.ENEMIES[tname]
			var lbl: Label3D = e["label"]
			lbl.text = "%s  Lv %d\n%d / %d" % [def["name"], def["level"], arr[4], arr[5]]
			var ratio := float(arr[4]) / maxf(float(arr[5]), 1.0)
			lbl.modulate = Color(1.0, 0.35, 0.3).lerp(Color(0.6, 1.0, 0.5), ratio)
		var slowed: bool = arr[7] if arr.size() > 7 else false
		if slowed != bool(e.get("slowed", false)):
			e["slowed"] = slowed
			var lbl2: Label3D = e["label"]
			lbl2.outline_modulate = Color(0.2, 0.6, 1.0, 0.9) if slowed else Color(0, 0, 0, 0.85)


func on_damage(pos: Vector3, amount: int, kind: int) -> void:
	var col := Color(1, 0.95, 0.5) if kind == 0 else Color(1, 0.3, 0.25)
	var l := LP.label(str(amount), 72, 0.004)
	l.modulate = col
	l.no_depth_test = true
	l.render_priority = 5
	fx_root.add_child(l)
	l.global_position = pos + Vector3(randf_range(-0.2, 0.2), 0, randf_range(-0.2, 0.2))
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position", l.position + Vector3(0, 0.9, 0), 1.0)
	tw.tween_property(l, "modulate:a", 0.0, 1.0)
	tw.tween_property(l, "outline_modulate:a", 0.0, 1.0)
	tw.chain().tween_callback(l.queue_free)
	if kind == 0:
		_play("hit", pos)
	else:
		_play("hurt", pos)
		if camera.global_position.distance_to(pos) < 1.0:
			_haptic(lhand, 0.6, 0.2)
			_haptic(rhand, 0.6, 0.2)


func on_fx(kind: int, pos: Vector3) -> void:
	match kind:
		0:
			LP.burst(fx_root, pos, Color(0.9, 0.9, 0.85), 24, 3.0, 2.0)
			_play("die", pos)
		1:
			LP.burst(fx_root, pos + Vector3(0, 0.2, 0), Color(0.55, 0.42, 0.3), 40, 7.0, 3.0, 1.0)
			_play("slam", pos)
			_haptic(lhand, 0.8, 0.3)
			_haptic(rhand, 0.8, 0.3)
		2:
			LP.burst(fx_root, pos, Color(1.0, 0.85, 0.2), 50, 4.0, 1.5, 1.4)
			_play("levelup", pos)
		3:
			LP.burst(fx_root, pos, Color(0.9, 0.2, 0.2), 30, 3.0, 2.0)
			_play("die", pos)
		4:
			LP.burst(fx_root, pos, Color(1.0, 0.8, 0.1), 10, 2.0, 1.0)
			_play("coin", pos)
		5:
			LP.burst(fx_root, pos, Color(0.5, 0.9, 1.0), 30, 2.5, 1.0)
			_play("upgrade", pos)
		6:
			_play("quest", pos)
		7:
			LP.burst(fx_root, pos, Color(0.4, 1.0, 0.5), 40, 2.5, 1.2, 1.2)
			_play("upgrade", pos)
		8:
			_ring(pos, Color(0.5, 0.85, 1.0), 5.5)
			LP.burst(fx_root, pos + Vector3(0, 0.3, 0), Color(0.7, 0.95, 1.0), 50, 6.0, 1.5, 0.9)
			_play("explode", pos)
		10:
			_ring(pos - Vector3(0, 0.9, 0), Color(0.95, 0.95, 0.95), 3.0)
			LP.burst(fx_root, pos, Color(0.9, 0.9, 1.0), 30, 5.0, 1.0, 0.5)
			_play("swing", pos)
		11:
			LP.burst(fx_root, pos, Color(1.0, 0.85, 0.3), 40, 2.0, 1.2, 1.2)
			_play("levelup", pos)


func _ring(pos: Vector3, color: Color, radius: float) -> void:
	var tm := TorusMesh.new()
	tm.inner_radius = 0.85
	tm.outer_radius = 1.0
	tm.rings = 24
	tm.ring_segments = 4
	var mi := MeshInstance3D.new()
	mi.mesh = tm
	mi.material_override = LP.mat(color, 2.5)
	fx_root.add_child(mi)
	mi.global_position = pos + Vector3(0, 0.15, 0)
	mi.scale = Vector3(0.3, 1.0, 0.3)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3(radius, 1.0, radius), 0.35)
	tw.tween_property(mi, "scale", Vector3(radius, 0.01, radius), 0.25)
	tw.tween_callback(mi.queue_free)


func on_line(a: Vector3, b: Vector3, _kind: int) -> void:
	var length := a.distance_to(b)
	if length < 0.05:
		return
	var root := Node3D.new()
	fx_root.add_child(root)
	# Gezackter Blitz aus mehreren Segmenten
	var pts: Array = [a]
	for i in range(1, 5):
		var p := a.lerp(b, float(i) / 5.0)
		pts.append(p + Vector3(randf_range(-0.3, 0.3), randf_range(-0.3, 0.3), randf_range(-0.3, 0.3)))
	pts.append(b)
	for i in pts.size() - 1:
		var p0: Vector3 = pts[i]
		var p1: Vector3 = pts[i + 1]
		var seg := LP.box(Vector3(0.05, 0.05, p0.distance_to(p1)), Color(0.8, 0.75, 1.0), Vector3.ZERO, 4.0)
		root.add_child(seg)
		seg.global_position = (p0 + p1) / 2.0
		if absf((p1 - p0).normalized().dot(Vector3.UP)) < 0.99:
			seg.look_at(p1, Vector3.UP)
		else:
			seg.look_at(p1, Vector3.RIGHT)
	LP.burst(fx_root, b, Color(0.8, 0.75, 1.0), 16, 3.0, 1.0, 0.4)
	_play("hit", b)
	get_tree().create_timer(0.25).timeout.connect(root.queue_free)


func on_fireball(id: int, o: Vector3, dir: Vector3) -> void:
	var n := Node3D.new()
	fx_root.add_child(n)
	n.global_position = o
	n.add_child(LP.sphere(0.14, Color(1.0, 0.5, 0.1), Vector3.ZERO, 8, 4.0))
	n.add_child(LP.sphere(0.08, Color(1.0, 0.9, 0.5), Vector3.ZERO, 6, 4.0))
	var trail := CPUParticles3D.new()
	trail.amount = 24
	trail.lifetime = 0.35
	trail.spread = 30.0
	trail.direction = -dir
	trail.initial_velocity_min = 0.5
	trail.initial_velocity_max = 1.5
	trail.gravity = Vector3.ZERO
	trail.scale_amount_min = 0.5
	trail.scale_amount_max = 1.2
	var m := BoxMesh.new()
	m.size = Vector3.ONE * 0.07
	m.material = LP.mat(Color(1.0, 0.6, 0.15), 3.0)
	trail.mesh = m
	n.add_child(trail)
	fireballs[id] = {"node": n, "dir": dir.normalized(), "life": 3.5}
	_play("cast", o)


func on_explode(id: int, pos: Vector3) -> void:
	if fireballs.has(id):
		(fireballs[id]["node"] as Node3D).queue_free()
		fireballs.erase(id)
	LP.burst(fx_root, pos, Color(1.0, 0.55, 0.1), 30, 4.0, 1.5, 0.6)
	_play("explode", pos)


func on_msg(text: String) -> void:
	_say(text)


func on_dialog(npc: String, text: String) -> void:
	if not npcs.has(npc):
		return
	var n: Dictionary = npcs[npc]
	var dlg: Label3D = n["dialog"]
	dlg.text = text
	n["dialog_t"] = 14.0


func on_teleport(pos: Vector3) -> void:
	var cam := camera.global_position
	origin.global_position += Vector3(pos.x - cam.x, 0, pos.z - cam.z)
	_follow_ground()


# ======================= Spielschleife =======================

func _process(delta: float) -> void:
	time += delta
	cast_cd = maxf(cast_cd - delta, 0.0)
	swing_cd = maxf(swing_cd - delta, 0.0)
	woosh_cd = maxf(woosh_cd - delta, 0.0)
	for k in hit_cd.keys():
		hit_cd[k] = float(hit_cd[k]) - delta
	for k in skill_cds.keys():
		skill_cds[k] = float(skill_cds[k]) - delta
	wrist_t -= delta
	if wrist_t <= 0.0 and state == "playing":
		wrist_t = 0.25
		_refresh_wrist()
	match state:
		"lobby":
			_lobby_vr_input()
		"connecting":
			connect_t += delta
			if connect_t > CONNECT_TIMEOUT:
				_on_connection_failed()
		"playing":
			_move(delta)
			_sword_vr(delta)
			_send_pose(delta)
	_follow_ground()
	_update_remotes(delta)
	_update_enemies(delta)
	_update_fireballs(delta)
	_update_banner(delta)
	_update_npcs(delta)


func _follow_ground() -> void:
	var c := camera.global_position
	origin.global_position.y = WG.height(c.x, c.z)


func _move(delta: float) -> void:
	if stats.get("dead", false):
		return
	var mv := Vector2.ZERO
	var sprint := 1.0
	if vr:
		mv = (lhand as XRController3D).get_vector2("primary")
		var rs: Vector2 = (rhand as XRController3D).get_vector2("primary")
		if absf(rs.x) > 0.7:
			if not latch_x:
				latch_x = true
				_snap_turn(-signf(rs.x) * SNAP_ANGLE)
		elif absf(rs.x) < 0.3:
			latch_x = false
		if (lhand as XRController3D).is_button_pressed("primary_click"):
			sprint = 1.6
	else:
		if Input.is_key_pressed(KEY_W):
			mv.y += 1.0
		if Input.is_key_pressed(KEY_S):
			mv.y -= 1.0
		if Input.is_key_pressed(KEY_A):
			mv.x -= 1.0
		if Input.is_key_pressed(KEY_D):
			mv.x += 1.0
		mv = mv.limit_length(1.0)
		if Input.is_key_pressed(KEY_SHIFT):
			sprint = 1.6
	if mv.length() < 0.15:
		return
	var b := camera.global_basis
	var fwd := -b.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := b.x
	right.y = 0.0
	right = right.normalized()
	var step := (right * mv.x + fwd * mv.y) * MOVE_SPEED * sprint * delta
	var target := camera.global_position + step
	if WG.height(target.x, target.z) < -1.0 or Vector2(target.x, target.z).length() > 105.0:
		return
	origin.global_position += step


func _send_pose(delta: float) -> void:
	pose_timer -= delta
	if pose_timer > 0.0:
		return
	pose_timer = 0.05
	Game.rpc_id(1, "pose",
		camera.global_position, camera.global_basis.get_rotation_quaternion(),
		lhand.global_position, lhand.global_basis.get_rotation_quaternion(),
		rhand.global_position, rhand.global_basis.get_rotation_quaternion())


func _enemy_axis(e: Dictionary) -> Array:
	var def: Dictionary = D.ENEMIES[e["type"]]
	var base: Vector3 = (e["node"] as Node3D).global_position
	return [base, base + Vector3.UP * float(def["height"]), float(def["radius"])]


func _sword_vr(delta: float) -> void:
	var tip := sword_tip.global_position
	var hilt := rhand.global_position
	var spd := (tip - last_tip).length() / maxf(delta, 0.001)
	last_tip = tip
	if not vr or stats.get("dead", false):
		return
	if spd > 3.5 and woosh_cd <= 0.0:
		woosh_cd = 0.35
		_play("swing", tip)
	if spd < 2.0:
		return
	for eid in enemies:
		var e: Dictionary = enemies[eid]
		if not e["alive"] or float(hit_cd.get(eid, 0.0)) > 0.0:
			continue
		var ax := _enemy_axis(e)
		var pts := Geometry3D.get_closest_points_between_segments(hilt, tip, ax[0], ax[1])
		if pts[0].distance_to(pts[1]) < float(ax[2]) + 0.08:
			hit_cd[eid] = 0.45
			Game.rpc_id(1, "req_hit", eid, spd / 4.5)
			_haptic(rhand, 0.9, 0.12)


func _desktop_swing() -> void:
	if swing_cd > 0.0 or stats.get("dead", false):
		return
	swing_cd = 0.45
	rhand.rotation.x = deg_to_rad(70.0)
	var tw := create_tween()
	tw.tween_property(rhand, "rotation:x", deg_to_rad(-60.0), 0.14)
	tw.tween_property(rhand, "rotation:x", 0.0, 0.2)
	_play("swing", rhand.global_position)
	var cam := camera.global_position
	var fwd := -camera.global_basis.z
	var best := 999.0
	var best_id := -1
	for eid in enemies:
		var e: Dictionary = enemies[eid]
		if not e["alive"]:
			continue
		var ax := _enemy_axis(e)
		var a: Vector3 = ax[0]
		var bb: Vector3 = ax[1]
		var center := Geometry3D.get_closest_point_to_segment(cam, a, bb)
		var to := center - cam
		var dist := to.length() - float(ax[2])
		if dist < 2.3 and fwd.dot(to.normalized()) > 0.45 and dist < best:
			best = dist
			best_id = eid
	if best_id >= 0:
		Game.rpc_id(1, "req_hit", best_id, 1.1)


func _cast() -> void:
	if stats.is_empty() or stats.get("dead", false):
		return
	var sk: Dictionary = D.SKILLS[skill_idx]
	if _skill_ready_in(skill_idx) > 0.0 or cast_cd > 0.0:
		return
	if float(stats.get("mana", 0)) < float(sk["mana"]):
		_say("Nicht genug Mana für %s." % sk["name"])
		return
	cast_cd = 0.3
	var o: Vector3
	var dir: Vector3
	if vr:
		o = lhand.global_position - lhand.global_basis.z * 0.1
		dir = -lhand.global_basis.z
	else:
		dir = -camera.global_basis.z
		o = camera.global_position + dir * 0.6 + Vector3(0, -0.15, 0)
	Game.rpc_id(1, "req_cast", skill_idx, o, dir)
	skill_cds[skill_idx] = float(sk["cd"])
	_haptic(lhand, 0.5, 0.1)
	if str(sk["id"]) == "whirl" and not vr:
		var tw := create_tween()
		tw.tween_property(rhand, "rotation:y", TAU, 0.35).from(0.0)


func _interact() -> void:
	var head := camera.global_position
	for key in npcs:
		var p: Vector3 = npcs[key]["pos"]
		if Vector2(head.x - p.x, head.z - p.z).length() < 3.5:
			Game.rpc_id(1, "req_interact", key)
			return


func _haptic(hand: Node3D, amp: float, dur: float) -> void:
	if vr and hand is XRController3D:
		(hand as XRController3D).trigger_haptic_pulse("haptic", 0.0, amp, dur, 0.0)


func _on_left_button(n: String) -> void:
	if state != "playing":
		return
	match n:
		"trigger_click":
			_cast()
		"ax_button":
			_select_skill(1)
		"by_button":
			_select_skill(-1)


func _on_right_button(n: String) -> void:
	if state == "lobby":
		if n == "ax_button" or n == "trigger_click":
			_connect()
		return
	if state != "playing":
		return
	match n:
		"ax_button":
			_interact()
		"by_button":
			Game.rpc_id(1, "req_recall")


func _unhandled_input(event: InputEvent) -> void:
	if vr:
		return
	var ke := event as InputEventKey
	if ke and ke.pressed and not ke.echo:
		match ke.keycode:
			KEY_ESCAPE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if state == "lobby":
			match ke.keycode:
				KEY_UP:
					lobby_row = wrapi(lobby_row - 1, 0, 3)
					_update_lobby()
				KEY_DOWN:
					lobby_row = wrapi(lobby_row + 1, 0, 3)
					_update_lobby()
				KEY_LEFT:
					_lobby_change(-1)
				KEY_RIGHT:
					_lobby_change(1)
				KEY_ENTER, KEY_KP_ENTER:
					_connect()
		elif state == "playing":
			match ke.keycode:
				KEY_E:
					_interact()
				KEY_R:
					Game.rpc_id(1, "req_recall")
				KEY_Q:
					_cast()
				KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
					_choose_skill(int(ke.keycode - KEY_1))
				KEY_TAB:
					_select_skill(1)
	var mb := event as InputEventMouseButton
	if mb and mb.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			return
		if state == "playing":
			if mb.button_index == MOUSE_BUTTON_LEFT:
				_desktop_swing()
			elif mb.button_index == MOUSE_BUTTON_RIGHT:
				_cast()
	var mm := event as InputEventMouseMotion
	if mm and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		origin.rotate_y(-mm.relative.x * 0.0025)
		camera.rotation.x = clampf(camera.rotation.x - mm.relative.y * 0.0025, -1.4, 1.4)


# ======================= Darstellung =======================

func _play(sound: String, pos: Vector3) -> void:
	if not sounds.has(sound):
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = sounds[sound]
	p.unit_size = 5.0
	p.max_distance = 60.0
	fx_root.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()


func _say(text: String) -> void:
	banner_lines.append([text, 6.0])
	while banner_lines.size() > 3:
		banner_lines.pop_front()
	_refresh_banner()


func _refresh_banner() -> void:
	var parts: Array = []
	for l in banner_lines:
		parts.append(l[0])
	banner.text = "\n".join(PackedStringArray(parts))


func _update_banner(delta: float) -> void:
	if banner_lines.is_empty():
		return
	var changed := false
	for l in banner_lines:
		l[1] = float(l[1]) - delta
	while not banner_lines.is_empty() and float(banner_lines[0][1]) <= 0.0:
		banner_lines.pop_front()
		changed = true
	if changed:
		_refresh_banner()


func _make_avatar(color_i: int) -> Dictionary:
	var col: Color = D.COLORS[clampi(color_i, 0, D.COLORS.size() - 1)]
	var root := Node3D.new()
	remotes_root.add_child(root)
	var head := Node3D.new()
	root.add_child(head)
	head.add_child(LP.sphere(0.13, SKIN, Vector3.ZERO, 10))
	head.add_child(LP.cyl(0.13, 0.15, 0.08, col, Vector3(0, 0.06, 0), 10))
	head.add_child(LP.cyl(0.0, 0.12, 0.2, col, Vector3(0, 0.19, 0), 8))
	head.add_child(LP.box(Vector3(0.03, 0.04, 0.02), Color(0.1, 0.1, 0.15), Vector3(-0.045, 0.0, -0.125)))
	head.add_child(LP.box(Vector3(0.03, 0.04, 0.02), Color(0.1, 0.1, 0.15), Vector3(0.045, 0.0, -0.125)))
	var body := Node3D.new()
	root.add_child(body)
	body.add_child(LP.cyl(0.16, 0.21, 0.55, col.darkened(0.15), Vector3.ZERO, 8))
	body.add_child(LP.cyl(0.215, 0.215, 0.07, Color(0.35, 0.22, 0.12), Vector3(0, -0.2, 0), 8))
	body.add_child(LP.box(Vector3(0.12, 0.7, 0.13), Color(0.3, 0.28, 0.35), Vector3(-0.09, -0.6, 0)))
	body.add_child(LP.box(Vector3(0.12, 0.7, 0.13), Color(0.3, 0.28, 0.35), Vector3(0.09, -0.6, 0)))
	body.add_child(LP.box(Vector3(0.38, 0.12, 0.2), col, Vector3(0, 0.25, 0)))
	var lh := Node3D.new()
	root.add_child(lh)
	lh.add_child(LP.make_hand(SKIN))
	var rh := Node3D.new()
	root.add_child(rh)
	rh.add_child(LP.make_hand(SKIN))
	var sw := LP.make_sword(0)
	rh.add_child(sw)
	var label := LP.label("", 44, 0.003)
	root.add_child(label)
	var bubble := LP.sphere(0.85, Color.WHITE, Vector3(0, -0.2, 0), 12)
	bubble.material_override = LP.unshaded(Color(1.0, 0.85, 0.3, 0.22))
	bubble.visible = false
	body.add_child(bubble)
	return {"root": root, "head": head, "body": body, "lh": lh, "rh": rh, "sword": sw,
		"label": label, "tier": 0, "t": [], "label_key": "", "bubble": bubble}


func _update_remotes(delta: float) -> void:
	var k := clampf(delta * 14.0, 0.0, 1.0)
	for pid in remotes:
		var a: Dictionary = remotes[pid]
		var t: Array = a["t"]
		if t.is_empty():
			continue
		var head: Node3D = a["head"]
		var lh: Node3D = a["lh"]
		var rh: Node3D = a["rh"]
		var body: Node3D = a["body"]
		head.position = head.position.lerp(t[3], k)
		head.quaternion = head.quaternion.slerp(t[4], k)
		lh.position = lh.position.lerp(t[5], k)
		lh.quaternion = lh.quaternion.slerp(t[6], k)
		rh.position = rh.position.lerp(t[7], k)
		rh.quaternion = rh.quaternion.slerp(t[8], k)
		var fwd := -(Basis(head.quaternion).z)
		body.position = head.position + Vector3(0, -0.5, 0)
		if Vector2(fwd.x, fwd.z).length() > 0.1:
			body.rotation.y = lerp_angle(body.rotation.y, atan2(-fwd.x, -fwd.z), k)
		var lbl: Label3D = a["label"]
		lbl.position = head.position + Vector3(0, 0.5, 0)
		var key := "%s|%d|%d|%d" % [t[1], t[9], t[10], t[11]]
		if key != a["label_key"]:
			a["label_key"] = key
			lbl.text = "%s  Lv %d\nHP %d/%d" % [t[1], t[11], t[9], t[10]]
		if int(a["tier"]) != int(t[12]):
			a["tier"] = int(t[12])
			LP.set_sword_tier(a["sword"], int(t[12]))
		var root_node: Node3D = a["root"]
		root_node.visible = not bool(t[13])
		var bubble: MeshInstance3D = a["bubble"]
		bubble.visible = t.size() > 14 and bool(t[14])


func _make_enemy(tname: String) -> Dictionary:
	var def: Dictionary = D.ENEMIES[tname]
	var root := Node3D.new()
	enemies_root.add_child(root)
	var model := Node3D.new()
	root.add_child(model)
	match tname:
		"slime":
			var col := Color(0.4, 0.85, 0.35)
			var blob := LP.sphere(0.5, col, Vector3(0, 0.4, 0), 10)
			blob.scale = Vector3(1, 0.8, 1)
			model.add_child(blob)
			model.add_child(LP.sphere(0.3, col.lightened(0.3), Vector3(0, 0.72, 0), 8))
			model.add_child(LP.sphere(0.07, Color(0.05, 0.05, 0.05), Vector3(-0.15, 0.55, -0.42), 6))
			model.add_child(LP.sphere(0.07, Color(0.05, 0.05, 0.05), Vector3(0.15, 0.55, -0.42), 6))
		"wolf":
			var fur := Color(0.45, 0.45, 0.5)
			model.add_child(LP.box(Vector3(0.5, 0.5, 1.1), fur, Vector3(0, 0.65, 0)))
			model.add_child(LP.box(Vector3(0.4, 0.38, 0.45), fur, Vector3(0, 0.85, -0.7)))
			model.add_child(LP.box(Vector3(0.2, 0.18, 0.25), fur.lightened(0.2), Vector3(0, 0.76, -1.0)))
			model.add_child(LP.box(Vector3(0.07, 0.07, 0.03), Color(0.1, 0.1, 0.1), Vector3(0, 0.82, -1.13)))
			model.add_child(LP.prism(Vector3(0.12, 0.18, 0.06), fur.darkened(0.2), Vector3(-0.12, 1.12, -0.65)))
			model.add_child(LP.prism(Vector3(0.12, 0.18, 0.06), fur.darkened(0.2), Vector3(0.12, 1.12, -0.65)))
			model.add_child(LP.box(Vector3(0.07, 0.05, 0.03), Color(1.0, 0.85, 0.2), Vector3(-0.1, 0.92, -0.93), 2.0))
			model.add_child(LP.box(Vector3(0.07, 0.05, 0.03), Color(1.0, 0.85, 0.2), Vector3(0.1, 0.92, -0.93), 2.0))
			for sx in [-1, 1]:
				for sz in [-1, 1]:
					model.add_child(LP.box(Vector3(0.14, 0.45, 0.14), fur.darkened(0.1), Vector3(0.17 * sx, 0.22, 0.4 * sz)))
			var tail := LP.box(Vector3(0.1, 0.1, 0.5), fur, Vector3(0, 0.82, 0.7))
			tail.rotation.x = 0.5
			model.add_child(tail)
		"golem":
			var stone := Color(0.55, 0.53, 0.5)
			model.add_child(LP.box(Vector3(0.6, 1.2, 0.6), stone.darkened(0.15), Vector3(-0.45, 0.6, 0)))
			model.add_child(LP.box(Vector3(0.6, 1.2, 0.6), stone.darkened(0.15), Vector3(0.45, 0.6, 0)))
			model.add_child(LP.box(Vector3(1.7, 1.4, 1.0), stone, Vector3(0, 1.9, 0)))
			model.add_child(LP.box(Vector3(0.85, 0.7, 0.75), stone.lightened(0.05), Vector3(0, 2.95, -0.1)))
			model.add_child(LP.box(Vector3(0.18, 0.1, 0.05), Color(1.0, 0.55, 0.1), Vector3(-0.2, 3.0, -0.49), 3.0))
			model.add_child(LP.box(Vector3(0.18, 0.1, 0.05), Color(1.0, 0.55, 0.1), Vector3(0.2, 3.0, -0.49), 3.0))
			model.add_child(LP.box(Vector3(0.55, 1.5, 0.55), stone.darkened(0.05), Vector3(-1.15, 1.75, 0)))
			model.add_child(LP.box(Vector3(0.55, 1.5, 0.55), stone.darkened(0.05), Vector3(1.15, 1.75, 0)))
			model.add_child(LP.box(Vector3(0.7, 0.2, 0.7), Color(0.3, 0.55, 0.25), Vector3(-1.0, 2.62, 0)))
			model.add_child(LP.box(Vector3(0.6, 0.2, 0.5), Color(0.3, 0.55, 0.25), Vector3(0.3, 2.62, 0.2)))
			model.add_child(LP.box(Vector3(0.4, 0.4, 0.05), Color(0.3, 0.8, 1.0), Vector3(0, 2.0, -0.52), 1.5))
	var label := LP.label("%s  Lv %d" % [def["name"], def["level"]], 48, 0.004)
	label.position.y = float(def["height"]) + 0.45
	root.add_child(label)
	return {"node": root, "model": model, "type": tname, "label": label, "alive": true,
		"hp": -1, "tpos": Vector3.ZERO, "tyaw": 0.0}


func _update_enemies(delta: float) -> void:
	var k := clampf(delta * 10.0, 0.0, 1.0)
	for eid in enemies:
		var e: Dictionary = enemies[eid]
		if not e["alive"]:
			continue
		var n: Node3D = e["node"]
		n.position = n.position.lerp(e["tpos"], k)
		n.rotation.y = lerp_angle(n.rotation.y, float(e["tyaw"]), k)
		var model: Node3D = e["model"]
		var ph := time + float(eid) * 1.7
		match e["type"]:
			"slime":
				var s := sin(ph * 6.0)
				model.scale = Vector3(1.0 - 0.06 * s, 1.0 + 0.12 * s, 1.0 - 0.06 * s)
			"wolf":
				model.position.y = absf(sin(ph * 8.0)) * 0.05
			"golem":
				model.rotation.z = sin(ph * 1.5) * 0.04


func _update_fireballs(delta: float) -> void:
	for id in fireballs.keys():
		var f: Dictionary = fireballs[id]
		var n: Node3D = f["node"]
		var dir: Vector3 = f["dir"]
		n.global_position += dir * D.SPELL_SPEED * delta
		f["life"] = float(f["life"]) - delta
		if float(f["life"]) <= 0.0:
			n.queue_free()
			fireballs.erase(id)


func _build_npcs() -> void:
	for key in D.NPCS:
		var info: Dictionary = D.NPCS[key]
		var p: Vector3 = info["pos"]
		p.y = WG.height(p.x, p.z)
		var root := Node3D.new()
		add_child(root)
		root.position = p
		var to := Vector3(D.SPAWN.x - p.x, 0, D.SPAWN.z - p.z)
		root.rotation.y = atan2(-to.x, -to.z)
		var head := Node3D.new()
		head.position.y = 1.32
		root.add_child(head)
		head.add_child(LP.sphere(0.17, SKIN, Vector3.ZERO, 10))
		head.add_child(LP.box(Vector3(0.04, 0.05, 0.02), Color(0.1, 0.1, 0.15), Vector3(-0.06, 0.02, -0.165)))
		head.add_child(LP.box(Vector3(0.04, 0.05, 0.02), Color(0.1, 0.1, 0.15), Vector3(0.06, 0.02, -0.165)))
		if key == "elder":
			root.add_child(LP.cyl(0.18, 0.4, 1.15, Color(0.45, 0.3, 0.6), Vector3(0, 0.57, 0), 8))
			var beard := LP.prism(Vector3(0.24, 0.32, 0.1), Color(0.95, 0.95, 0.95), Vector3(0, -0.15, -0.13))
			beard.rotation.z = PI
			head.add_child(beard)
			head.add_child(LP.cyl(0.0, 0.24, 0.45, Color(0.35, 0.22, 0.5), Vector3(0, 0.3, 0), 8))
			root.add_child(LP.cyl(0.03, 0.035, 1.8, Color(0.45, 0.3, 0.18), Vector3(0.42, 0.9, -0.1), 6))
			root.add_child(LP.sphere(0.09, Color(0.4, 0.8, 1.0), Vector3(0.42, 1.85, -0.1), 8, 2.5))
		else:
			root.add_child(LP.cyl(0.22, 0.3, 1.15, Color(0.55, 0.35, 0.25), Vector3(0, 0.57, 0), 8))
			root.add_child(LP.box(Vector3(0.42, 0.75, 0.05), Color(0.3, 0.25, 0.22), Vector3(0, 0.6, -0.27)))
			head.add_child(LP.cyl(0.17, 0.18, 0.12, Color(0.7, 0.3, 0.15), Vector3(0, 0.1, 0), 10))
			root.add_child(LP.box(Vector3(0.7, 0.35, 0.35), Color(0.3, 0.3, 0.33), Vector3(0.2, 0.5, -0.75)))
			root.add_child(LP.box(Vector3(0.3, 0.3, 0.25), Color(0.35, 0.25, 0.18), Vector3(0.2, 0.15, -0.75)))
			var hammer := LP.box(Vector3(0.05, 0.5, 0.05), Color(0.45, 0.3, 0.18), Vector3(0.38, 0.85, -0.15))
			hammer.add_child(LP.box(Vector3(0.18, 0.1, 0.1), Color(0.4, 0.4, 0.45), Vector3(0, 0.25, 0)))
			root.add_child(hammer)
		var name_l := LP.label(info["name"], 48, 0.0035)
		name_l.position.y = 2.15
		name_l.modulate = Color(1.0, 0.9, 0.5)
		root.add_child(name_l)
		var hint := LP.label("[A] Sprechen" if vr else "[E] Sprechen", 40, 0.003)
		hint.position.y = 1.92
		hint.visible = false
		root.add_child(hint)
		var dl := LP.label("", 40, 0.003)
		dl.position.y = 2.95
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		dl.width = 800.0
		dl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		root.add_child(dl)
		npcs[key] = {"pos": p, "root": root, "head": head, "dialog": dl, "hint": hint, "dialog_t": 0.0}


func _update_npcs(delta: float) -> void:
	var cam := camera.global_position if camera else Vector3.ZERO
	for key in npcs:
		var n: Dictionary = npcs[key]
		var head: Node3D = n["head"]
		head.position.y = 1.32 + sin(time * 2.0 + float(key.length())) * 0.015
		if float(n["dialog_t"]) > 0.0:
			n["dialog_t"] = float(n["dialog_t"]) - delta
			if float(n["dialog_t"]) <= 0.0:
				var dlg: Label3D = n["dialog"]
				dlg.text = ""
		var p: Vector3 = n["pos"]
		var near := Vector2(cam.x - p.x, cam.z - p.z).length() < 3.5
		var hint: Label3D = n["hint"]
		hint.visible = near and state == "playing" and float(n["dialog_t"]) <= 0.0
