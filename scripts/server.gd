extends Node
## Autoritativer Spielserver: Gegner-KI, Kampf, Erfahrung, Quests, Speicherstände.

const D = preload("res://scripts/game_data.gd")
const WG = preload("res://scripts/world_gen.gd")
const SAVE_DIR := "user://saves"

var players: Dictionary = {}
var enemies: Dictionary = {}
var projectiles: Dictionary = {}
var next_enemy_id := 1
var next_proj_id := 1
var snap_t := 0.0
var stats_t := 0.0
var save_t := 30.0
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.randomize()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_DIR))
	for s in D.SPAWNS:
		for i in int(s["count"]):
			_create_enemy(str(s["type"]), s["center"], float(s["radius"]))
	print("[Server] %d Gegner erschaffen. Spielstände: %s" % [enemies.size(), ProjectSettings.globalize_path(SAVE_DIR)])


func _exit_tree() -> void:
	for p in players.values():
		if p.get("joined", false):
			_save(p)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _ground(p: Vector3) -> Vector3:
	return Vector3(p.x, WG.height(p.x, p.z), p.z)


func _random_point(center: Vector3, radius: float) -> Vector3:
	for attempt in 10:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * radius
		var p := _ground(Vector3(center.x + cos(a) * r, 0, center.z + sin(a) * r))
		if p.y > 0.3:
			return p
	return _ground(center)


func _player(pid: int):
	var p = players.get(pid)
	if p == null or not p.get("joined", false):
		return null
	return p


# ======================= Gegner =======================

func _create_enemy(t: String, center: Vector3, radius: float) -> void:
	var def: Dictionary = D.ENEMIES[t]
	var pos := _random_point(center, radius)
	enemies[next_enemy_id] = {
		"id": next_enemy_id, "type": t, "center": center, "radius": radius,
		"home": pos, "pos": pos, "yaw": rng.randf() * TAU,
		"hp": int(def["hp"]), "maxhp": int(def["hp"]), "alive": true, "respawn": 0.0,
		"target": 0, "atk_cd": 0.0, "special_cd": 6.0, "wander": pos, "wander_t": 0.0,
		"returning": false, "attackers": {}, "slow_t": 0.0,
	}
	next_enemy_id += 1


func _respawn_enemy(e: Dictionary) -> void:
	var pos := _random_point(e["center"], float(e["radius"]))
	e["pos"] = pos
	e["home"] = pos
	e["wander"] = pos
	e["hp"] = e["maxhp"]
	e["alive"] = true
	e["returning"] = false
	e["target"] = 0
	e["attackers"] = {}
	e["slow_t"] = 0.0


func _move_toward(e: Dictionary, pos: Vector3, target: Vector3, speed: float, delta: float) -> Vector3:
	var dir := Vector3(target.x - pos.x, 0, target.z - pos.z)
	var dist := dir.length()
	if dist < 0.01:
		return pos
	dir /= dist
	e["yaw"] = atan2(-dir.x, -dir.z)
	var np := pos + dir * minf(speed * delta, dist)
	if WG.height(np.x, np.z) < -0.4:
		return pos
	return np


func _tick_enemies(delta: float) -> void:
	for e in enemies.values():
		if not e["alive"]:
			e["respawn"] = float(e["respawn"]) - delta
			if float(e["respawn"]) <= 0.0:
				_respawn_enemy(e)
			continue
		var def: Dictionary = D.ENEMIES[e["type"]]
		var pos: Vector3 = e["pos"]
		var home: Vector3 = e["home"]
		e["atk_cd"] = float(e["atk_cd"]) - delta
		e["special_cd"] = float(e["special_cd"]) - delta
		var aggro: float = def["aggro"]
		var speed: float = def["speed"]
		if float(e["slow_t"]) > 0.0:
			e["slow_t"] = float(e["slow_t"]) - delta
			speed *= 0.4
		var tid: int = e["target"]
		if tid != 0:
			var tp = _player(tid)
			if tp == null or tp["dead"] or _flat(tp["pos"], pos) > aggro * 2.0:
				tid = 0
		if tid == 0 and not e["returning"]:
			var best := aggro
			for pid in players:
				var pp = _player(pid)
				if pp == null or pp["dead"]:
					continue
				var d := _flat(pp["pos"], pos)
				if d < best:
					best = d
					tid = pid
		if _flat(pos, home) > float(def["leash"]):
			tid = 0
			e["returning"] = true
		e["target"] = tid

		if e["returning"]:
			pos = _move_toward(e, pos, home, speed * 1.5, delta)
			e["hp"] = e["maxhp"]
			if _flat(pos, home) < 1.0:
				e["returning"] = false
		elif tid != 0:
			var tp: Dictionary = players[tid]
			var tpos: Vector3 = tp["pos"]
			var d := _flat(pos, tpos)
			var reach: float = float(def["radius"]) + 0.9
			if d > reach:
				pos = _move_toward(e, pos, tpos, speed, delta)
			else:
				var dir := Vector3(tpos.x - pos.x, 0, tpos.z - pos.z)
				if dir.length() > 0.01:
					e["yaw"] = atan2(-dir.x, -dir.z)
				if float(e["atk_cd"]) <= 0.0:
					e["atk_cd"] = def["atk_rate"]
					_damage_player(tid, tp, float(def["dmg"]) * rng.randf_range(0.8, 1.2))
			if e["type"] == "golem" and float(e["special_cd"]) <= 0.0 and d < 6.0:
				e["special_cd"] = 7.0
				Game.rpc("fx", 1, pos)
				for pid in players:
					var pp = _player(pid)
					if pp != null and not pp["dead"] and _flat(pp["pos"], pos) < 4.5:
						_damage_player(pid, pp, float(def["dmg"]) * 1.3)
		else:
			e["wander_t"] = float(e["wander_t"]) - delta
			if float(e["wander_t"]) <= 0.0:
				e["wander_t"] = rng.randf_range(3.0, 7.0)
				e["wander"] = _random_point(home, 0.0 if e["type"] == "golem" else 5.0)
			var w: Vector3 = e["wander"]
			if _flat(pos, w) > 0.5:
				pos = _move_toward(e, pos, w, speed * 0.4, delta)
		e["pos"] = _ground(pos)


func _damage_enemy(e: Dictionary, dmg: int, pid: int) -> void:
	if not e["alive"]:
		return
	e["hp"] = int(e["hp"]) - dmg
	var attackers: Dictionary = e["attackers"]
	attackers[pid] = true
	if int(e["target"]) == 0 or e["returning"]:
		e["target"] = pid
		e["returning"] = false
	var def: Dictionary = D.ENEMIES[e["type"]]
	var pos: Vector3 = e["pos"]
	var center := pos + Vector3.UP * float(def["height"]) * 0.7
	Game.rpc("fx_damage", center, dmg, 0)
	if int(e["hp"]) <= 0:
		_kill_enemy(e, center)


func _kill_enemy(e: Dictionary, center: Vector3) -> void:
	var def: Dictionary = D.ENEMIES[e["type"]]
	e["alive"] = false
	e["hp"] = 0
	e["respawn"] = def["respawn"]
	e["target"] = 0
	Game.rpc("fx", 0, center)
	if e["type"] == "golem":
		Game.rpc("msg", "Der Steingolem wurde besiegt!")
	var attackers: Dictionary = e["attackers"]
	for apid in attackers:
		var p = _player(apid)
		if p == null:
			continue
		p["gold"] = int(p["gold"]) + int(def["gold"])
		Game.rpc_id(apid, "fx", 4, center)
		_add_xp(apid, p, int(def["xp"]))
		var qi := int(p["quest_idx"])
		if p["quest_active"] and qi < D.QUESTS.size():
			var q: Dictionary = D.QUESTS[qi]
			if q["target"] == e["type"] and int(p["quest_progress"]) < int(q["count"]):
				p["quest_progress"] = int(p["quest_progress"]) + 1
				if int(p["quest_progress"]) >= int(q["count"]):
					Game.rpc_id(apid, "msg", "Aufgabe erfüllt! Kehre zu Ältestem Bruno zurück.")
					Game.rpc_id(apid, "fx", 6, p["head"])
		p["dirty"] = true
	e["attackers"] = {}


func _tick_projectiles(delta: float) -> void:
	for id in projectiles.keys():
		var pr: Dictionary = projectiles[id]
		var dir: Vector3 = pr["dir"]
		var pos: Vector3 = pr["pos"]
		pos += dir * D.SPELL_SPEED * delta
		pr["life"] = float(pr["life"]) - delta
		var hit := false
		for e in enemies.values():
			if not e["alive"]:
				continue
			var def: Dictionary = D.ENEMIES[e["type"]]
			var ep: Vector3 = e["pos"]
			if _flat(pos, ep) < float(def["radius"]) + 0.35 and pos.y > ep.y - 0.3 and pos.y < ep.y + float(def["height"]) + 0.3:
				var p = _player(pr["owner"])
				var lvl: int = p["level"] if p != null else 1
				_damage_enemy(e, roundi(D.spell_damage(lvl) * rng.randf_range(0.9, 1.1)), pr["owner"])
				hit = true
				break
		if hit or pos.y < WG.height(pos.x, pos.z) or float(pr["life"]) <= 0.0:
			Game.rpc("fx_explode", id, pos)
			projectiles.erase(id)
		else:
			pr["pos"] = pos


# ======================= Spieler =======================

func on_peer_connected(pid: int) -> void:
	print("[Server] Verbindung von Peer %d" % pid)
	players[pid] = {"joined": false}


func on_peer_disconnected(pid: int) -> void:
	var p = players.get(pid)
	if p != null and p.get("joined", false):
		_save(p)
		print("[Server] %s hat das Spiel verlassen." % p["name"])
		Game.rpc("msg", "%s hat die Welt verlassen." % p["name"])
	players.erase(pid)
	for e in enemies.values():
		if int(e["target"]) == pid:
			e["target"] = 0
		(e["attackers"] as Dictionary).erase(pid)


func _sanitize(n: String) -> String:
	var out := ""
	for c in n.strip_edges():
		if c in " _-" or c.to_upper() != c.to_lower() or c.is_valid_int():
			out += c
	out = out.strip_edges().substr(0, 16)
	return out if out != "" else "Abenteurer"


func _save_path(pname: String) -> String:
	return "%s/%s.json" % [SAVE_DIR, pname.to_lower().validate_filename()]


func join(pid: int, pname: String, color: int) -> void:
	if not players.has(pid):
		return
	pname = _sanitize(pname)
	for other in players.values():
		if other.get("joined", false) and str(other["name"]).to_lower() == pname.to_lower():
			Game.rpc_id(pid, "join_failed", "Der Name '%s' ist schon online." % pname)
			return
	var sp := _ground(D.SPAWN)
	var p := {
		"joined": true, "name": pname, "color": clampi(color, 0, D.COLORS.size() - 1),
		"level": 1, "xp": 0, "gold": 0, "sword": 0,
		"quest_idx": 0, "quest_active": false, "quest_progress": 0,
		"hp": D.max_hp(1), "mana": D.MAX_MANA, "dead": false, "respawn_t": 0.0,
		"head": sp + Vector3(0, 1.6, 0), "head_q": Quaternion(),
		"lh": sp + Vector3(-0.3, 1.1, 0), "lh_q": Quaternion(),
		"rh": sp + Vector3(0.3, 1.1, 0), "rh_q": Quaternion(),
		"pos": sp, "last_swing": 0.0, "last_cast": 0.0, "last_hurt": -100.0,
		"last_recall": -100.0, "dirty": true, "cds": {}, "shield_t": 0.0,
	}
	var path := _save_path(pname)
	if FileAccess.file_exists(path):
		var data = JSON.parse_string(FileAccess.get_file_as_string(path))
		if data is Dictionary:
			for key in ["level", "xp", "gold", "sword", "quest_idx", "quest_progress"]:
				p[key] = int(data.get(key, p[key]))
			p["quest_active"] = bool(data.get("quest_active", false))
			p["hp"] = D.max_hp(int(p["level"]))
	players[pid] = p
	print("[Server] %s (Peer %d) betritt die Welt, Level %d." % [pname, pid, p["level"]])
	Game.rpc_id(pid, "joined", pid, _stats(p))
	Game.rpc_id(pid, "teleport", sp)
	Game.rpc("msg", "%s hat die Welt betreten." % pname)
	_save(p)


func _save(p: Dictionary) -> void:
	var data := {}
	for key in ["name", "level", "xp", "gold", "sword", "quest_idx", "quest_active", "quest_progress"]:
		data[key] = p[key]
	var f := FileAccess.open(_save_path(p["name"]), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))
		f.close()


func _stats(p: Dictionary) -> Dictionary:
	var lvl: int = p["level"]
	var qi: int = p["quest_idx"]
	var sw: Dictionary = D.SWORDS[int(p["sword"])]
	var d := {
		"name": p["name"], "level": lvl, "xp": p["xp"], "xp_need": D.xp_needed(lvl),
		"gold": p["gold"], "hp": int(ceilf(float(p["hp"]))), "max_hp": int(D.max_hp(lvl)),
		"mana": int(p["mana"]), "max_mana": int(D.MAX_MANA), "sword": p["sword"],
		"sword_name": sw["name"], "quest_title": "", "quest_progress": p["quest_progress"],
		"quest_count": 0, "quest_active": p["quest_active"], "quest_done": qi >= D.QUESTS.size(),
		"dead": p["dead"], "shield": float(p["shield_t"]) > 0.0,
	}
	if qi < D.QUESTS.size():
		var q: Dictionary = D.QUESTS[qi]
		d["quest_title"] = q["title"]
		d["quest_count"] = q["count"]
	return d


func on_pose(pid: int, h: Vector3, hq: Quaternion, l: Vector3, lq: Quaternion, r: Vector3, rq: Quaternion) -> void:
	var p = _player(pid)
	if p == null or not h.is_finite() or not l.is_finite() or not r.is_finite():
		return
	if Vector2(h.x, h.z).length() > 130.0:
		return
	p["head"] = h
	p["head_q"] = hq.normalized() if hq.is_finite() else Quaternion()
	p["lh"] = l
	p["lh_q"] = lq.normalized() if lq.is_finite() else Quaternion()
	p["rh"] = r
	p["rh_q"] = rq.normalized() if rq.is_finite() else Quaternion()
	p["pos"] = _ground(h)


func on_hit(pid: int, eid: int, power: float) -> void:
	var p = _player(pid)
	if p == null or p["dead"] or not enemies.has(eid):
		return
	var e: Dictionary = enemies[eid]
	if not e["alive"]:
		return
	var def: Dictionary = D.ENEMIES[e["type"]]
	if _flat(p["head"], e["pos"]) > float(def["radius"]) + 3.0:
		return
	var now := _now()
	if now - float(p["last_swing"]) < 0.22:
		return
	p["last_swing"] = now
	var dmg := D.sword_damage(int(p["level"]), int(p["sword"])) * clampf(power, 0.6, 1.6)
	_damage_enemy(e, roundi(dmg * rng.randf_range(0.9, 1.1)), pid)


func on_cast(pid: int, skill: int, o: Vector3, dir: Vector3) -> void:
	var p = _player(pid)
	if p == null or p["dead"] or skill < 0 or skill >= D.SKILLS.size():
		return
	if not o.is_finite() or not dir.is_finite() or dir.length() < 0.1:
		return
	if o.distance_to(p["head"]) > 1.8:
		return
	var sk: Dictionary = D.SKILLS[skill]
	var lvl: int = p["level"]
	if lvl < int(sk["level"]):
		Game.rpc_id(pid, "msg", "%s lernst du erst mit Level %d." % [sk["name"], sk["level"]])
		return
	var now := _now()
	var cds: Dictionary = p["cds"]
	if now < float(cds.get(skill, 0.0)) or float(p["mana"]) < float(sk["mana"]):
		return
	dir = dir.normalized()
	var used := true
	match str(sk["id"]):
		"fireball":
			var id := next_proj_id
			next_proj_id += 1
			projectiles[id] = {"pos": o, "dir": dir, "owner": pid, "life": 3.0}
			Game.rpc("fx_fireball", id, o, dir)
		"heal":
			_skill_heal(p)
		"frost":
			_skill_frost(pid, p)
		"whirl":
			_skill_whirl(pid, p)
		"lightning":
			used = _skill_lightning(pid, p, dir)
		"shield":
			p["shield_t"] = 6.0
			Game.rpc("fx", 11, p["head"])
	if not used:
		Game.rpc_id(pid, "msg", "Kein Ziel in Sicht.")
		return
	p["mana"] = float(p["mana"]) - float(sk["mana"])
	cds[skill] = now + float(sk["cd"])
	p["dirty"] = true


func _skill_heal(p: Dictionary) -> void:
	var amount := D.heal_amount(int(p["level"]))
	Game.rpc("fx", 7, p["head"])
	for pid in players:
		var other = _player(pid)
		if other == null or other["dead"] or _flat(other["pos"], p["pos"]) > 6.0:
			continue
		var mh := D.max_hp(int(other["level"]))
		var healed := minf(mh, float(other["hp"]) + amount) - float(other["hp"])
		other["hp"] = float(other["hp"]) + healed
		other["dirty"] = true
		var head: Vector3 = other["head"]
		Game.rpc("fx_damage", head + Vector3(0, 0.35, 0), roundi(healed), 2)


func _enemy_center(e: Dictionary) -> Vector3:
	var def: Dictionary = D.ENEMIES[e["type"]]
	var pos: Vector3 = e["pos"]
	return pos + Vector3.UP * float(def["height"]) * 0.6


func _skill_frost(pid: int, p: Dictionary) -> void:
	var pos: Vector3 = p["pos"]
	Game.rpc("fx", 8, pos)
	var dmg := D.spell_damage(int(p["level"])) * 0.7
	for e in enemies.values():
		if not e["alive"]:
			continue
		var def: Dictionary = D.ENEMIES[e["type"]]
		if _flat(e["pos"], pos) < 5.5 + float(def["radius"]):
			e["slow_t"] = 4.0
			_damage_enemy(e, roundi(dmg * rng.randf_range(0.9, 1.1)), pid)


func _skill_whirl(pid: int, p: Dictionary) -> void:
	var pos: Vector3 = p["pos"]
	Game.rpc("fx", 10, pos + Vector3(0, 1.0, 0))
	var dmg := D.sword_damage(int(p["level"]), int(p["sword"])) * 1.3
	for e in enemies.values():
		if not e["alive"]:
			continue
		var def: Dictionary = D.ENEMIES[e["type"]]
		if _flat(e["pos"], pos) < 2.8 + float(def["radius"]):
			_damage_enemy(e, roundi(dmg * rng.randf_range(0.9, 1.1)), pid)


func _skill_lightning(pid: int, p: Dictionary, dir: Vector3) -> bool:
	var head: Vector3 = p["head"]
	var first = null
	var best := 16.0
	for e in enemies.values():
		if not e["alive"]:
			continue
		var to := _enemy_center(e) - head
		var d := to.length()
		if d < best and dir.dot(to / maxf(d, 0.01)) > 0.85:
			best = d
			first = e
	if first == null:
		return false
	var dmg := D.spell_damage(int(p["level"])) * 1.3
	var hit: Array = []
	var cur: Dictionary = first
	var from := head
	for jump in 3:
		var c := _enemy_center(cur)
		Game.rpc("fx_line", from, c, 0)
		hit.append(cur)
		_damage_enemy(cur, roundi(dmg * rng.randf_range(0.9, 1.1)), pid)
		dmg *= 0.75
		from = c
		var nxt = null
		var nbest := 7.0
		for e in enemies.values():
			if not e["alive"] or hit.has(e):
				continue
			var d := _enemy_center(e).distance_to(c)
			if d < nbest:
				nbest = d
				nxt = e
		if nxt == null:
			break
		cur = nxt
	return true


func on_interact(pid: int, npc: String) -> void:
	var p = _player(pid)
	if p == null or not D.NPCS.has(npc):
		return
	if _flat(p["pos"], D.NPCS[npc]["pos"]) > 5.0:
		return
	if npc == "elder":
		_talk_elder(pid, p)
	elif npc == "smith":
		_talk_smith(pid, p)
	p["dirty"] = true


func _talk_elder(pid: int, p: Dictionary) -> void:
	var qi: int = p["quest_idx"]
	var text := ""
	if qi >= D.QUESTS.size():
		text = "Ihr habt unser Dorf gerettet, %s! Der Golem kehrt manchmal zurück – zeigt ihm, wer hier wohnt." % p["name"]
	else:
		var q: Dictionary = D.QUESTS[qi]
		if not p["quest_active"]:
			p["quest_active"] = true
			p["quest_progress"] = 0
			text = "Neue Aufgabe: %s\n%s" % [q["title"], q["text"]]
			Game.rpc_id(pid, "fx", 6, p["head"])
		elif int(p["quest_progress"]) >= int(q["count"]):
			p["quest_active"] = false
			p["quest_idx"] = qi + 1
			p["quest_progress"] = 0
			p["gold"] = int(p["gold"]) + int(q["gold"])
			text = "Großartig! Hier deine Belohnung: %d Erfahrung und %d Gold." % [q["xp"], q["gold"]]
			if qi + 1 < D.QUESTS.size():
				text += "\nSprich mich wieder an, ich habe noch eine Aufgabe."
			_add_xp(pid, p, int(q["xp"]))
			Game.rpc_id(pid, "fx", 4, p["head"])
			_save(p)
		else:
			text = "%s: Noch %d von %d. %s" % [q["title"], int(q["count"]) - int(p["quest_progress"]), q["count"], q["text"]]
	Game.rpc_id(pid, "dialog", "elder", text)


func _talk_smith(pid: int, p: Dictionary) -> void:
	var tier: int = p["sword"]
	var text := ""
	if tier >= D.SWORDS.size() - 1:
		text = "Dein Kristallschwert ist das Beste, was meine Esse hergibt!"
	else:
		var nxt: Dictionary = D.SWORDS[tier + 1]
		var cost: int = nxt["cost"]
		if int(p["gold"]) >= cost:
			p["gold"] = int(p["gold"]) - cost
			p["sword"] = tier + 1
			text = "Frisch geschmiedet: dein %s! (%d Gold)" % [nxt["name"], cost]
			Game.rpc("fx", 5, p["rh"])
			_save(p)
		else:
			text = "Ein %s kostet %d Gold. Du hast %d Gold. Komm wieder, wenn du mehr hast!" % [nxt["name"], cost, p["gold"]]
	Game.rpc_id(pid, "dialog", "smith", text)


func on_recall(pid: int) -> void:
	var p = _player(pid)
	if p == null or p["dead"]:
		return
	var now := _now()
	var wait: float = 20.0 - (now - float(p["last_recall"]))
	if wait > 0.0:
		Game.rpc_id(pid, "msg", "Heimkehr erst in %d Sekunden wieder möglich." % ceili(wait))
		return
	p["last_recall"] = now
	Game.rpc_id(pid, "teleport", _ground(D.SPAWN))
	Game.rpc_id(pid, "msg", "Du kehrst ins Dorf zurück.")


func _add_xp(pid: int, p: Dictionary, amount: int) -> void:
	p["xp"] = int(p["xp"]) + amount
	var old_level: int = p["level"]
	var leveled := false
	while int(p["xp"]) >= D.xp_needed(int(p["level"])):
		p["xp"] = int(p["xp"]) - D.xp_needed(int(p["level"]))
		p["level"] = int(p["level"]) + 1
		leveled = true
	if leveled:
		p["hp"] = D.max_hp(int(p["level"]))
		Game.rpc("fx", 2, p["head"])
		Game.rpc("msg", "%s hat Level %d erreicht!" % [p["name"], p["level"]])
		for sk in D.SKILLS:
			if int(sk["level"]) > old_level and int(sk["level"]) <= int(p["level"]):
				Game.rpc_id(pid, "msg", "Neue Fähigkeit: %s! %s" % [sk["name"], sk["desc"]])
				Game.rpc_id(pid, "fx", 6, p["head"])
		_save(p)
	p["dirty"] = true


func _damage_player(pid: int, p: Dictionary, amount: float) -> void:
	if p["dead"]:
		return
	if float(p["shield_t"]) > 0.0:
		amount *= 0.5
	var dmg := roundi(amount)
	p["hp"] = float(p["hp"]) - dmg
	p["last_hurt"] = _now()
	p["dirty"] = true
	var head: Vector3 = p["head"]
	Game.rpc("fx_damage", head + Vector3(0, 0.35, 0), dmg, 1)
	if float(p["hp"]) <= 0.0:
		p["hp"] = 0.0
		p["dead"] = true
		p["respawn_t"] = 4.0
		var lost := int(p["gold"]) / 10
		p["gold"] = int(p["gold"]) - lost
		Game.rpc("fx", 3, head)
		Game.rpc("msg", "%s wurde besiegt!" % p["name"])
		Game.rpc_id(pid, "msg", "Du bist gefallen und verlierst %d Gold. Du erwachst gleich im Dorf..." % lost)
		for e in enemies.values():
			if int(e["target"]) == pid:
				e["target"] = 0


func _tick_players(delta: float) -> void:
	var now := _now()
	for pid in players:
		var p = _player(pid)
		if p == null:
			continue
		if p["dead"]:
			p["respawn_t"] = float(p["respawn_t"]) - delta
			if float(p["respawn_t"]) <= 0.0:
				p["dead"] = false
				p["hp"] = D.max_hp(int(p["level"]))
				p["mana"] = D.MAX_MANA
				p["dirty"] = true
				var sp := _ground(D.SPAWN)
				p["pos"] = sp
				p["head"] = sp + Vector3(0, 1.6, 0)
				Game.rpc_id(pid, "teleport", sp)
			continue
		if float(p["shield_t"]) > 0.0:
			p["shield_t"] = float(p["shield_t"]) - delta
			if float(p["shield_t"]) <= 0.0:
				p["dirty"] = true
		var mh := D.max_hp(int(p["level"]))
		var regen := 0.0
		if now - float(p["last_hurt"]) > 6.0:
			regen = 2.0 + mh * 0.01
		if _flat(p["pos"], D.VILLAGE) < 6.0:
			regen += 15.0
		if float(p["hp"]) < mh and regen > 0.0:
			p["hp"] = minf(mh, float(p["hp"]) + regen * delta)
			p["dirty"] = true
		if float(p["mana"]) < D.MAX_MANA:
			p["mana"] = minf(D.MAX_MANA, float(p["mana"]) + 9.0 * delta)
			p["dirty"] = true


func _broadcast() -> void:
	if multiplayer.get_peers().is_empty():
		return
	var pl: Array = []
	for pid in players:
		var p = _player(pid)
		if p == null:
			continue
		var lvl: int = p["level"]
		pl.append([pid, p["name"], p["color"], p["head"], p["head_q"], p["lh"], p["lh_q"],
			p["rh"], p["rh_q"], int(ceilf(float(p["hp"]))), int(D.max_hp(lvl)), lvl, p["sword"], p["dead"],
			float(p["shield_t"]) > 0.0])
	var en: Array = []
	for e in enemies.values():
		en.append([e["id"], D.ENEMY_TYPES.find(e["type"]), e["pos"], e["yaw"], e["hp"], e["maxhp"], e["alive"],
			float(e["slow_t"]) > 0.0])
	Game.rpc("snapshot", pl, en)


func _physics_process(delta: float) -> void:
	_tick_players(delta)
	_tick_enemies(delta)
	_tick_projectiles(delta)
	snap_t -= delta
	if snap_t <= 0.0:
		snap_t = 0.1
		_broadcast()
	stats_t -= delta
	if stats_t <= 0.0:
		stats_t = 0.25
		for pid in players:
			var p = _player(pid)
			if p != null and p["dirty"]:
				p["dirty"] = false
				Game.rpc_id(pid, "stats", _stats(p))
	save_t -= delta
	if save_t <= 0.0:
		save_t = 30.0
		for p in players.values():
			if p.get("joined", false):
				_save(p)
