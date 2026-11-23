extends Node3D
## Schwebendes Spielmenü (Inventar, Ausrüstung, Fähigkeiten, Status) im Stil eines
## "Virtual-Reality-MMO"-Menüs: wird per Wischgeste geöffnet, schwebt fest in der Welt,
## runde Symbol-Leiste links, Liste in der Mitte, Details rechts. Bedienung per Laserstrahl.
##
## Öffnen/Schließen in VR: rechten Trigger halten und nach unten wischen (nach oben = schließen)
##                        oder Menü-Taste links. Am PC: I.
## Klicken: rechter Trigger (VR) bzw. Linksklick auf das Fadenkreuz (PC).
##
## Außerdem: "materialisierte" Tränke als physikalische Flaschen. Zum Trinken an den Mund führen.

const D = preload("res://scripts/game_data.gd")
const LP = preload("res://scripts/lowpoly.gd")
const WG = preload("res://scripts/world_gen.gd")

const COL_PANEL := Color(0.97, 0.97, 0.98, 0.86)
const COL_HEADER := Color(0.93, 0.93, 0.95, 0.95)
const COL_ROW := Color(0.88, 0.88, 0.91, 0.92)
const COL_HOVER := Color(1.0, 0.78, 0.35, 0.97)
const COL_SELECTED := Color(0.98, 0.62, 0.18, 0.97)
const COL_ACCENT := Color(0.98, 0.62, 0.18, 1.0)
const COL_TEXT := Color(0.18, 0.18, 0.24)
const COL_ICON := Color(0.9, 0.9, 0.93, 0.95)
const PIX := 0.0005
const ROWS := 8
const ROW_H := 0.062
const TABS := ["items", "equip", "skills", "status", "close"]
const TAB_NAMES := {"items": "GEGENSTÄNDE", "equip": "AUSRÜSTUNG", "skills": "FÄHIGKEITEN",
	"status": "STATUS", "close": "SCHLIESSEN"}
const ACTION_NAMES := {"use": "Benutzen", "materialize": "Materialisieren", "equip": "Ausrüsten",
	"give": "Geben (an Mitspieler)", "drop": "Wegwerfen", "select_skill": "Als aktive Fähigkeit wählen"}

var client
var is_open := false
var tab := "items"
var selected := -1
var scroll := 0
var widgets: Array = []
var hovered := -1
var content: Node3D
var cursor: MeshInstance3D
var laser: MeshInstance3D
var content_hash := ""
var opened_at := Vector3.ZERO

var gesture_start := Vector3.ZERO
var gesture_t := -1.0
var trigger_was := false

var bottles: Array = []
var bottle_held: Dictionary = {}


func _ready() -> void:
	visible = false
	_build_static()
	cursor = LP.sphere(0.008, COL_ACCENT, Vector3.ZERO, 8, 2.0)
	cursor.visible = false
	add_child(cursor)
	cursor.top_level = true
	laser = LP.box(Vector3(0.004, 0.004, 1.0), COL_ACCENT, Vector3.ZERO, 2.0)
	laser.visible = false
	add_child(laser)
	laser.top_level = true


# ======================= Öffnen / Schließen =======================

func toggle() -> void:
	if is_open:
		close_menu()
	else:
		open_menu()


func open_menu() -> void:
	var cam: Camera3D = client.camera
	var fwd := -cam.global_basis.z
	fwd.y = 0.0
	if fwd.length() < 0.01:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()
	global_position = cam.global_position + fwd * 0.75 + Vector3(0, -0.18, 0)
	look_at(global_position + fwd, Vector3.UP)
	rotate_object_local(Vector3.RIGHT, deg_to_rad(-12.0))
	opened_at = global_position
	is_open = true
	visible = true
	scale = Vector3(0.05, 0.05, 0.05)
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector3.ONE, 0.25)
	client._play("menu_open", global_position)
	client._haptic(client.rhand, 0.3, 0.05)
	content_hash = ""
	_rebuild()


func close_menu() -> void:
	if not is_open:
		return
	is_open = false
	cursor.visible = false
	laser.visible = false
	client._play("menu_close", global_position)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3(0.05, 0.05, 0.05), 0.15)
	tw.tween_callback(func(): visible = is_open)


# ======================= Bausteine =======================

func _quad(parent: Node3D, center: Vector2, size: Vector2, color: Color, z: float) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = LP.unshaded(color)
	mi.position = Vector3(center.x, center.y, z)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _text(parent: Node3D, text: String, center: Vector2, width: float, font: int = 36,
		align := HORIZONTAL_ALIGNMENT_LEFT, color := COL_TEXT) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = font
	l.pixel_size = PIX
	l.modulate = color
	l.outline_size = 0
	l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.width = width / PIX
	l.horizontal_alignment = align
	l.position = Vector3(center.x, center.y, 0.012)
	l.render_priority = 4
	parent.add_child(l)
	return l


func _button(parent: Node3D, id: String, center: Vector2, size: Vector2, text: String,
		color := COL_ROW, font: int = 34, align := HORIZONTAL_ALIGNMENT_LEFT, is_static := false) -> void:
	var bg := _quad(parent, center, size, color, 0.006)
	bg.render_priority = 2
	if text != "":
		_text(parent, text, center, size.x - 0.03, font, align)
	widgets.append({"id": id, "rect": Rect2(center - size / 2.0, size), "bg": bg, "color": color,
		"static": is_static})


func _build_static() -> void:
	var p1 := _quad(self, Vector2(-0.17, 0.0), Vector2(0.68, 0.64), COL_PANEL, 0.0)
	p1.render_priority = 1
	var p2 := _quad(self, Vector2(0.43, 0.0), Vector2(0.42, 0.64), COL_PANEL, 0.0)
	p2.render_priority = 1
	var a1 := _quad(self, Vector2(-0.17, 0.318), Vector2(0.68, 0.006), COL_ACCENT, 0.004)
	a1.render_priority = 3
	var a2 := _quad(self, Vector2(0.43, 0.318), Vector2(0.42, 0.006), COL_ACCENT, 0.004)
	a2.render_priority = 3
	for i in TABS.size():
		var y := 0.22 - i * 0.11
		var center := Vector2(-0.6, y)
		var disc := LP.cyl(0.045, 0.045, 0.006, Color.WHITE, Vector3(center.x, center.y, 0.0), 20)
		disc.rotation.x = PI / 2.0
		disc.material_override = LP.unshaded(COL_ICON)
		add_child(disc)
		_icon(TABS[i], Vector3(center.x, center.y, 0.012))
		widgets.append({"id": "tab:" + str(TABS[i]), "rect": Rect2(center - Vector2(0.05, 0.05), Vector2(0.1, 0.1)),
			"bg": disc, "color": COL_ICON, "static": true})
	content = Node3D.new()
	add_child(content)


## Kleine 3D-Symbole in den runden Knöpfen
func _icon(kind: String, pos: Vector3) -> void:
	var n := Node3D.new()
	n.position = pos
	add_child(n)
	var dark := Color(0.35, 0.35, 0.42)
	match kind:
		"items":
			n.add_child(LP.box(Vector3(0.034, 0.028, 0.012), Color(0.6, 0.42, 0.25), Vector3(0, -0.004, 0)))
			n.add_child(LP.box(Vector3(0.02, 0.006, 0.012), Color(0.45, 0.3, 0.18), Vector3(0, 0.014, 0)))
		"equip":
			var blade := LP.box(Vector3(0.007, 0.05, 0.004), Color(0.75, 0.78, 0.85), Vector3(0, 0.006, 0))
			n.add_child(blade)
			n.add_child(LP.box(Vector3(0.022, 0.005, 0.005), dark, Vector3(0, -0.019, 0)))
			n.add_child(LP.box(Vector3(0.006, 0.012, 0.005), Color(0.45, 0.3, 0.18), Vector3(0, -0.027, 0)))
			n.rotation.z = -0.6
		"skills":
			n.add_child(LP.sphere(0.014, COL_ACCENT, Vector3.ZERO, 8, 2.0))
			for k in 4:
				var ray := LP.box(Vector3(0.004, 0.022, 0.003), COL_ACCENT, Vector3.ZERO, 1.5)
				ray.rotation.z = k * PI / 4.0
				n.add_child(ray)
		"status":
			n.add_child(LP.sphere(0.009, dark, Vector3(0, 0.012, 0), 8))
			n.add_child(LP.cyl(0.006, 0.014, 0.02, dark, Vector3(0, -0.01, 0), 8))
		"close":
			for r in [0.785, -0.785]:
				var bar := LP.box(Vector3(0.006, 0.04, 0.004), Color(0.85, 0.3, 0.25), Vector3.ZERO)
				bar.rotation.z = r
				n.add_child(bar)


# ======================= Inhalte =======================

func _stats() -> Dictionary:
	return client.stats


func _rebuild() -> void:
	for c in content.get_children():
		c.queue_free()
	widgets = widgets.filter(func(w): return w["static"])
	hovered = -1
	for w in widgets:
		var mi: MeshInstance3D = w["bg"]
		mi.material_override = LP.unshaded(COL_SELECTED if w["id"] == "tab:" + tab else COL_ICON)
	match tab:
		"items":
			_build_items()
		"equip":
			_build_equip()
		"skills":
			_build_skills()
		"status":
			_build_status()


func _header(text: String) -> void:
	var h := _quad(content, Vector2(-0.17, 0.28), Vector2(0.66, 0.06), COL_HEADER, 0.003)
	h.render_priority = 2
	_text(content, text, Vector2(-0.17, 0.28), 0.62, 38)


func _rows(entries: Array) -> void:
	# entries: [[id, text], ...]
	var pages := maxi(ceili(entries.size() / float(ROWS)), 1)
	scroll = clampi(scroll, 0, pages - 1)
	for i in ROWS:
		var idx := scroll * ROWS + i
		if idx >= entries.size():
			break
		var e: Array = entries[idx]
		var col := COL_SELECTED if e[0] == "row:%d" % selected or e[0] == "skill:%d" % selected else COL_ROW
		_button(content, e[0], Vector2(-0.17, 0.2 - i * ROW_H), Vector2(0.64, 0.054), e[1], col)
	if entries.is_empty():
		_text(content, "(leer)", Vector2(-0.17, 0.15), 0.6, 34, HORIZONTAL_ALIGNMENT_CENTER)
	if pages > 1:
		_button(content, "scroll:-1", Vector2(-0.36, -0.285), Vector2(0.24, 0.042), "Zurück", COL_ROW, 30,
			HORIZONTAL_ALIGNMENT_CENTER)
		_button(content, "scroll:1", Vector2(0.02, -0.285), Vector2(0.24, 0.042), "Weiter", COL_ROW, 30,
			HORIZONTAL_ALIGNMENT_CENTER)
		_text(content, "%d/%d" % [scroll + 1, pages], Vector2(-0.17, -0.285), 0.1, 30, HORIZONTAL_ALIGNMENT_CENTER)


func _detail(title: String, body: String, actions: Array) -> void:
	_text(content, title, Vector2(0.43, 0.26), 0.38, 40, HORIZONTAL_ALIGNMENT_CENTER)
	var sep := _quad(content, Vector2(0.43, 0.215), Vector2(0.36, 0.003), COL_ACCENT, 0.004)
	sep.render_priority = 3
	_text(content, body, Vector2(0.43, 0.1), 0.37, 30, HORIZONTAL_ALIGNMENT_LEFT)
	for i in actions.size():
		var act: String = actions[i]
		var col := Color(0.95, 0.75, 0.75, 0.95) if act == "drop" else COL_ROW
		_button(content, "act:" + act, Vector2(0.43, -0.06 - i * 0.065), Vector2(0.38, 0.055),
			ACTION_NAMES.get(act, act), col, 32, HORIZONTAL_ALIGNMENT_CENTER)


func _inventory() -> Array:
	return _stats().get("inventory", [])


func _build_items() -> void:
	var inv := _inventory()
	_header("GEGENSTÄNDE     %d/%d Plätze     Gold %d" % [inv.size(), D.INV_SLOTS, int(_stats().get("gold", 0))])
	var entries: Array = []
	for i in inv.size():
		var st: Dictionary = inv[i]
		var n := int(st["n"])
		entries.append(["row:%d" % i, "%s%s" % [D.item_name(st), ("   x%d" % n) if n > 1 else ""]])
	_rows(entries)
	if selected < 0 or selected >= inv.size():
		selected = -1
		var held: Dictionary = _stats().get("held", {})
		var held_txt := ""
		for k in held:
			if int(held[k]) > 0:
				held_txt += "\n- %s x%d (materialisiert)" % [D.ITEMS[k]["name"], held[k]]
		_detail("Inventar", "Wähle links einen Gegenstand aus." + held_txt, [])
		return
	var sel: Dictionary = inv[selected]
	var def: Dictionary = D.ITEMS[sel["id"]]
	var body: String = def["desc"]
	var actions: Array = []
	match str(def["type"]):
		"consumable":
			actions = ["use", "materialize", "give", "drop"]
			body += "\nAnzahl: %d" % int(sel["n"])
		"material":
			actions = ["give", "drop"]
			body += "\nAnzahl: %d" % int(sel["n"])
		"weapon":
			actions = ["equip", "give", "drop"]
			body = _weapon_text(int(sel["wtype"]), int(sel["tier"]), float(sel["q"]))
	_detail(D.item_name(sel), body, actions)


func _weapon_text(wtype: int, tier: int, q: float) -> String:
	var lvl: int = _stats().get("level", 1)
	var wt: Dictionary = D.WEAPON_TYPES[wtype]
	var t := "Typ: %s\nMaterial: %s\nQualität: %d %%\nSchaden (Lv %d): %d" % [
		wt["name"], D.MATERIALS[tier], roundi(q * 100.0), lvl, roundi(D.weapon_damage(lvl, tier, wtype, q))]
	if float(wt["knockback"]) > 0.0:
		t += "\nStößt Gegner zurück"
	return t


func _build_equip() -> void:
	var st := _stats()
	_header("AUSRÜSTUNG")
	var inv := _inventory()
	var entries: Array = []
	entries.append(["row:-2", "[Ausgerüstet] %s" % st.get("sword_name", "?")])
	for i in inv.size():
		var s2: Dictionary = inv[i]
		if s2["id"] == "weapon":
			entries.append(["row:%d" % i, D.item_name(s2)])
	_rows(entries)
	if selected >= 0 and selected < inv.size() and inv[selected]["id"] == "weapon":
		var sel: Dictionary = inv[selected]
		_detail(D.item_name(sel), _weapon_text(int(sel["wtype"]), int(sel["tier"]), float(sel["q"])),
			["equip", "give", "drop"])
	else:
		_detail(str(st.get("sword_name", "?")), _weapon_text(int(st.get("weapon_type", 0)), int(st.get("sword", 0)),
			float(st.get("quality", 0.5))) + "\n\nNeue Waffen schmiedest du an Gretas Esse.", [])


func _build_skills() -> void:
	_header("FÄHIGKEITEN")
	var entries: Array = []
	var list: Array = client._skill_list()
	for idx in list:
		var info: Dictionary = client._skill_info(idx)
		var mark := "* " if info.get("custom", false) else ""
		var active := "  [aktiv]" if idx == client.skill_idx else ""
		entries.append(["skill:%d" % idx, "%s%s%s" % [mark, info["name"], active]])
	for sk in D.SKILLS:
		if int(sk["level"]) > int(_stats().get("level", 1)):
			entries.append(["locked", "%s  (ab Level %d)" % [sk["name"], sk["level"]]])
	_rows(entries)
	if list.has(selected):
		var info: Dictionary = client._skill_info(selected)
		var body := "%s\n\nMana: %d\nAbklingzeit: %.0f s" % [info["desc"], int(info["mana"]), float(info["cd"])]
		if info.get("custom", false):
			body += "\n\nEigene Fähigkeit, von Claude für dich programmiert."
		_detail(str(info["name"]), body, ["select_skill"])
	else:
		_detail("Fähigkeiten", "Wähle eine Fähigkeit aus. Mit * markierte hat Claude für dich erschaffen.", [])


func _build_status() -> void:
	var st := _stats()
	_header("STATUS  -  %s" % st.get("name", ""))
	var t := "Level %d     EP %d/%d\nHP %d/%d     Mana %d/%d\nGold %d\nWaffe: %s\n" % [
		st.get("level", 1), st.get("xp", 0), st.get("xp_need", 0), st.get("hp", 0), st.get("max_hp", 0),
		st.get("mana", 0), st.get("max_mana", 0), st.get("gold", 0), st.get("sword_name", "")]
	if st.get("quest_done", false):
		t += "Aufgaben: alle erledigt!"
	elif st.get("quest_active", false):
		t += "Aufgabe: %s (%d/%d)" % [st.get("quest_title", ""), st.get("quest_progress", 0), st.get("quest_count", 0)]
	_text(content, t, Vector2(-0.17, 0.1), 0.62, 36)
	var done: Array = st.get("achievement_ids", [])
	var a := ""
	for ach in D.ACHIEVEMENTS:
		a += "%s %s\n" % ["[x]" if done.has(ach["id"]) else "[  ]", ach["name"]]
	_text(content, "ERFOLGE  %d/%d\n%s" % [done.size(), D.ACHIEVEMENTS.size(), a], Vector2(0.43, 0.02), 0.38, 26)


func _hash() -> String:
	var st := _stats()
	return JSON.stringify([st.get("inventory", []), st.get("held", {}), st.get("level", 0), st.get("gold", 0),
		st.get("sword_name", ""), st.get("achievement_ids", []), (st.get("custom_skills", []) as Array).size(),
		st.get("xp", 0)])


func on_stats() -> void:
	if not is_open:
		return
	var h := _hash()
	if h != content_hash:
		content_hash = h
		if tab == "items" and selected >= _inventory().size():
			selected = -1
		_rebuild()


# ======================= Zeigen & Klicken =======================

func _pointer() -> Array:
	if client.vr:
		var hand: Node3D = client.rhand
		return [hand.global_position, -hand.global_basis.z]
	var cam: Camera3D = client.camera
	return [cam.global_position, -cam.global_basis.z]


func _update_pointer() -> void:
	var ray := _pointer()
	var o: Vector3 = ray[0]
	var dir: Vector3 = ray[1]
	var n := global_basis.z.normalized()
	var denom := n.dot(dir)
	var hit_idx := -1
	var hit := Vector3.ZERO
	var has_hit := false
	if absf(denom) > 0.0001:
		var t := n.dot(global_position - o) / denom
		if t > 0.0 and t < 4.0:
			hit = o + dir * t
			var lp := to_local(hit)
			if lp.x > -0.7 and lp.x < 0.7 and lp.y > -0.35 and lp.y < 0.35:
				has_hit = true
				for i in widgets.size():
					var r: Rect2 = widgets[i]["rect"]
					if r.has_point(Vector2(lp.x, lp.y)):
						hit_idx = i
						break
	cursor.visible = has_hit
	if has_hit:
		cursor.global_position = hit + n * 0.01
	laser.visible = client.vr and has_hit
	if laser.visible:
		var length := o.distance_to(hit)
		laser.global_position = (o + hit) / 2.0
		laser.look_at(hit, Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT)
		laser.scale = Vector3(1, 1, length)
	if hit_idx != hovered:
		_set_hover(hovered, false)
		hovered = hit_idx
		_set_hover(hovered, true)
		if hovered >= 0:
			client._play("hover", hit)
			client._haptic(client.rhand, 0.15, 0.02)


func _set_hover(i: int, on: bool) -> void:
	if i < 0 or i >= widgets.size():
		return
	var w: Dictionary = widgets[i]
	var mi: MeshInstance3D = w["bg"]
	if not is_instance_valid(mi):
		return
	if on:
		mi.material_override = LP.unshaded(COL_HOVER)
	elif str(w["id"]) == "tab:" + tab:
		mi.material_override = LP.unshaded(COL_SELECTED)
	else:
		mi.material_override = LP.unshaded(w["color"])


func click() -> void:
	if not is_open or hovered < 0 or hovered >= widgets.size():
		return
	var id: String = widgets[hovered]["id"]
	client._play("click", global_position)
	client._haptic(client.rhand, 0.4, 0.04)
	var parts := id.split(":")
	var kind := parts[0]
	var arg := parts[1] if parts.size() > 1 else ""
	match kind:
		"tab":
			if arg == "close":
				close_menu()
				return
			tab = arg
			selected = -1
			scroll = 0
		"row":
			selected = int(arg)
		"skill":
			selected = int(arg)
		"scroll":
			scroll += int(arg)
		"act":
			_do_action(arg)
		_:
			return
	_rebuild()


func _do_action(act: String) -> void:
	match act:
		"select_skill":
			client._choose_skill(selected)
		_:
			if selected >= 0:
				Game.rpc_id(1, "req_item_action", selected, act)
				if act == "materialize":
					close_menu()


# ======================= Materialisierte Tränke =======================

func on_materialized(id: String) -> void:
	var col: Color = D.ITEMS[id]["color"]
	var b := RigidBody3D.new()
	b.mass = 0.4
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.04
	shape.height = 0.14
	cs.shape = shape
	b.add_child(cs)
	b.add_child(LP.cyl(0.04, 0.045, 0.1, col, Vector3(0, -0.02, 0), 10, 0.6))
	b.add_child(LP.cyl(0.015, 0.02, 0.05, Color(0.85, 0.9, 0.95), Vector3(0, 0.055, 0), 8))
	b.add_child(LP.cyl(0.017, 0.017, 0.015, Color(0.5, 0.35, 0.2), Vector3(0, 0.085, 0), 8))
	client.fx_root.add_child(b)
	var key := "l" if (not client.vr or client.forge_station.holding("r")) else "r"
	var hand: Node3D = client.lhand if key == "l" else client.rhand
	b.global_position = hand.global_position
	LP.burst(client.fx_root, hand.global_position, col.lightened(0.4), 24, 1.0, 0.6, 0.6)
	client._play("menu_open", hand.global_position)
	bottles.append({"body": b, "id": id, "t": 0.0})
	if not bottle_held.has(key):
		bottle_held[key] = {"body": b, "hand": hand}
		b.gravity_scale = 0.0
	if not client.vr:
		client._say("%s materialisiert. Mit T trinken." % D.ITEMS[id]["name"])


func holding(key: String) -> bool:
	return bottle_held.has(key)


func grab_bottle(hand: Node3D, key: String) -> bool:
	if bottle_held.has(key):
		return true
	for e in bottles:
		var b: RigidBody3D = e["body"]
		if b.global_position.distance_to(hand.global_position) < 0.16:
			bottle_held[key] = {"body": b, "hand": hand}
			b.gravity_scale = 0.0
			return true
	return false


func release_bottle(key: String) -> void:
	if not bottle_held.has(key):
		return
	var b: RigidBody3D = bottle_held[key]["body"]
	bottle_held.erase(key)
	if is_instance_valid(b):
		b.gravity_scale = 1.0
		b.linear_velocity = b.linear_velocity.limit_length(10.0)


## Desktop: Flasche in der linken Hand zum Mund führen
func drink_desktop() -> void:
	if not bottle_held.has("l"):
		client._say("Du hältst keinen Trank. Materialisiere einen im Menü (I).")
		return
	var lh: Node3D = client.lhand
	var home := lh.position
	var tw := create_tween()
	tw.tween_property(lh, "position", Vector3(0.0, -0.1, -0.12), 0.35)
	tw.tween_interval(0.4)
	tw.tween_property(lh, "position", home, 0.3)


func _remove_bottle(e: Dictionary) -> void:
	var b: RigidBody3D = e["body"]
	for key in bottle_held.keys():
		if bottle_held[key]["body"] == b:
			bottle_held.erase(key)
	bottles.erase(e)
	if is_instance_valid(b):
		b.queue_free()


func clear_bottles() -> void:
	for e in bottles.duplicate():
		_remove_bottle(e)


func _physics_process(delta: float) -> void:
	for key in bottle_held.keys():
		var h: Dictionary = bottle_held[key]
		var b: RigidBody3D = h["body"]
		var hand: Node3D = h["hand"]
		if not is_instance_valid(b):
			bottle_held.erase(key)
			continue
		var target := hand.global_position + hand.global_basis.y * 0.03
		var dp := target - b.global_position
		if dp.length() > 0.5:
			b.global_position = target
			b.linear_velocity = Vector3.ZERO
		else:
			b.linear_velocity = (dp / delta).limit_length(20.0)
		var dq := (hand.global_basis.get_rotation_quaternion() * b.global_basis.get_rotation_quaternion().inverse()).normalized()
		var ang := dq.get_angle()
		if ang > PI:
			ang -= TAU
		b.angular_velocity = (dq.get_axis() * ang / delta).limit_length(30.0) if absf(ang) > 0.001 else Vector3.ZERO
	var mouth: Vector3 = client.camera.global_position - client.camera.global_basis.y * 0.08
	for e in bottles.duplicate():
		var b: RigidBody3D = e["body"]
		if not is_instance_valid(b):
			bottles.erase(e)
			continue
		var pos := b.global_position
		# Einfacher Boden (das Gelände hat keine Kollision)
		var ground := WG.height(pos.x, pos.z) + 0.07
		if pos.y < ground:
			b.global_position.y = ground
			var v := b.linear_velocity
			b.linear_velocity = Vector3(v.x * 0.6, maxf(v.y, 0.0), v.z * 0.6)
		if pos.distance_to(mouth) < 0.16:
			Game.rpc_id(1, "req_held_consume", str(e["id"]))
			client._play("drink", pos)
			client._haptic(client.lhand, 0.3, 0.2)
			client._haptic(client.rhand, 0.3, 0.2)
			_remove_bottle(e)
			continue
		var is_held := false
		for key in bottle_held:
			if bottle_held[key]["body"] == b:
				is_held = true
		e["t"] = 0.0 if is_held else float(e["t"]) + delta
		if float(e["t"]) > 30.0 or pos.distance_to(client.camera.global_position) > 25.0:
			# Liegengelassen: kehrt ins Inventar zurück
			LP.burst(client.fx_root, pos, Color(0.9, 0.95, 1.0), 16, 1.0, 0.5, 0.5)
			Game.rpc_id(1, "req_held_return", str(e["id"]))
			_remove_bottle(e)


# ======================= Geste & Laufzeit =======================

func _gesture(delta: float) -> void:
	if not client.vr:
		return
	var xr := client.rhand as XRController3D
	var pressed := xr.get_float("trigger") > 0.6
	var p: Vector3 = client.rhand.position
	if pressed and not trigger_was:
		gesture_start = p
		gesture_t = 0.0
	if pressed and gesture_t >= 0.0:
		gesture_t += delta
		var d := p - gesture_start
		var sideways := Vector2(d.x, d.z).length()
		if gesture_t < 0.6 and sideways < 0.18:
			if not is_open and d.y < -0.2:
				open_menu()
				gesture_t = -1.0
			elif is_open and d.y > 0.2:
				close_menu()
				gesture_t = -1.0
	trigger_was = pressed


func _process(delta: float) -> void:
	if client == null or client.state != "playing":
		if is_open:
			close_menu()
		return
	_gesture(delta)
	if is_open:
		_update_pointer()
		if client.camera.global_position.distance_to(opened_at) > 2.5:
			close_menu()
