extends RefCounted
## Die EINZIGE Schnittstelle, über die von Claude erzeugte eigene Fähigkeiten
## auf das Spiel wirken dürfen. Jeder Aufruf (ein "Cast") bekommt ein eigenes
## Objekt mit Budgets, damit keine Fähigkeit übermächtig werden kann.

const D = preload("res://scripts/game_data.gd")
const WG = preload("res://scripts/world_gen.gd")

const MAX_EFFECTS := 80
const MAX_TIMERS := 10
const MAX_RADIUS := 15.0

var _server
var _caster := 0
var _level := 1
var _damage_budget := 0.0
var _heal_budget := 0.0
var _effects := 0
var _timers := 0
var _dashes := 0


func _init(server, caster: int, level: int) -> void:
	_server = server
	_caster = caster
	_level = level
	_damage_budget = D.spell_damage(level) * 6.0
	_heal_budget = D.heal_amount(level) * 1.5


# ---------------- Informationen ----------------

func caster_id() -> int:
	return _caster


func caster_level() -> int:
	return _level


func caster_position() -> Vector3:
	var p = _server._player(_caster)
	return p["pos"] if p != null else Vector3.ZERO


func caster_head() -> Vector3:
	var p = _server._player(_caster)
	return p["head"] if p != null else Vector3.ZERO


func caster_hp_ratio() -> float:
	var p = _server._player(_caster)
	if p == null:
		return 0.0
	return float(p["hp"]) / D.max_hp(int(p["level"]))


func base_damage() -> float:
	return D.spell_damage(_level)


func base_heal() -> float:
	return D.heal_amount(_level)


func random() -> float:
	return _server.rng.randf()


func ground_height(x: float, z: float) -> float:
	return WG.height(x, z)


func enemies_in_radius(center: Vector3, radius: float) -> Array:
	radius = clampf(radius, 0.0, MAX_RADIUS)
	var out: Array = []
	for e in _server.enemies.values():
		if e["alive"] and _server._flat(e["pos"], center) < radius + float(D.ENEMIES[e["type"]]["radius"]):
			out.append(e["id"])
	return out


func nearest_enemy(center: Vector3, max_dist: float) -> int:
	max_dist = clampf(max_dist, 0.0, 25.0)
	var best := max_dist
	var found := -1
	for e in _server.enemies.values():
		if not e["alive"]:
			continue
		var d: float = _server._flat(e["pos"], center)
		if d < best:
			best = d
			found = e["id"]
	return found


func enemy_in_direction(origin: Vector3, direction: Vector3, max_dist: float) -> int:
	max_dist = clampf(max_dist, 0.0, 25.0)
	direction = direction.normalized()
	var best := max_dist
	var found := -1
	for e in _server.enemies.values():
		if not e["alive"]:
			continue
		var to: Vector3 = _server._enemy_center(e) - origin
		var d := to.length()
		if d < best and direction.dot(to / maxf(d, 0.01)) > 0.8:
			best = d
			found = e["id"]
	return found


func is_enemy_alive(eid: int) -> bool:
	return _server.enemies.has(eid) and _server.enemies[eid]["alive"]


func enemy_position(eid: int) -> Vector3:
	if not _server.enemies.has(eid):
		return Vector3.ZERO
	return _server._enemy_center(_server.enemies[eid])


func enemy_hp(eid: int) -> int:
	if not _server.enemies.has(eid):
		return 0
	return int(_server.enemies[eid]["hp"])


func players_in_radius(center: Vector3, radius: float) -> Array:
	radius = clampf(radius, 0.0, MAX_RADIUS)
	var out: Array = []
	for pid in _server.players:
		var p = _server._player(pid)
		if p != null and not p["dead"] and _server._flat(p["pos"], center) < radius:
			out.append(pid)
	return out


func player_position(pid: int) -> Vector3:
	var p = _server._player(pid)
	return p["pos"] if p != null else Vector3.ZERO


# ---------------- Aktionen (mit Obergrenzen) ----------------

func damage_enemy(eid: int, amount: float) -> void:
	amount = clampf(amount, 0.0, _damage_budget)
	if amount < 1.0 or not is_enemy_alive(eid):
		return
	_damage_budget -= amount
	_server._damage_enemy(_server.enemies[eid], roundi(amount), _caster)


func slow_enemy(eid: int, seconds: float) -> void:
	if is_enemy_alive(eid):
		var e: Dictionary = _server.enemies[eid]
		e["slow_t"] = maxf(float(e["slow_t"]), clampf(seconds, 0.0, 6.0))


func knockback_enemy(eid: int, from: Vector3, distance: float) -> void:
	if not is_enemy_alive(eid):
		return
	var e: Dictionary = _server.enemies[eid]
	if e["type"] == "golem":
		distance *= 0.2
	var pos: Vector3 = e["pos"]
	var dir := Vector3(pos.x - from.x, 0, pos.z - from.z)
	if dir.length() < 0.01:
		return
	var target := pos + dir.normalized() * clampf(distance, 0.0, 6.0)
	if WG.height(target.x, target.z) > -0.4:
		e["pos"] = Vector3(target.x, WG.height(target.x, target.z), target.z)


func heal_player(pid: int, amount: float) -> void:
	amount = clampf(amount, 0.0, _heal_budget)
	if amount < 1.0:
		return
	_heal_budget -= amount
	_server.heal_player(pid, amount, _caster)


func shield_player(pid: int, seconds: float) -> void:
	var p = _server._player(pid)
	if p != null and not p["dead"]:
		p["shield_t"] = maxf(float(p["shield_t"]), clampf(seconds, 0.0, 8.0))
		p["dirty"] = true


func dash(direction: Vector3, distance: float) -> void:
	if _dashes >= 2:
		return
	_dashes += 1
	var p = _server._player(_caster)
	if p == null:
		return
	direction.y = 0.0
	if direction.length() < 0.01:
		return
	var pos: Vector3 = p["pos"]
	var target := pos + direction.normalized() * clampf(distance, 0.0, 10.0)
	if WG.height(target.x, target.z) < -0.4 or Vector2(target.x, target.z).length() > 105.0:
		return
	target.y = WG.height(target.x, target.z)
	p["pos"] = target
	Game.rpc_id(_caster, "teleport", target)


func spawn_projectile(origin: Vector3, direction: Vector3, speed: float, damage_mult: float, color: Color) -> void:
	damage_mult = clampf(damage_mult, 0.2, 2.0)
	var cost := base_damage() * damage_mult
	if cost > _damage_budget or direction.length() < 0.01:
		return
	_damage_budget -= cost
	_server.spawn_projectile(_caster, origin, direction.normalized(), clampf(speed, 4.0, 30.0), damage_mult, color)


func after(seconds: float, fn: Callable) -> void:
	if _timers >= MAX_TIMERS:
		return
	_timers += 1
	_server.get_tree().create_timer(clampf(seconds, 0.05, 5.0)).timeout.connect(fn)


# ---------------- Effekte (nur Optik/Ton) ----------------

func _fx(kind: int, a: Vector3, b: Vector3, color: Color, size: float, text: String) -> void:
	if _effects >= MAX_EFFECTS:
		return
	_effects += 1
	Game.rpc("fx_custom", kind, a, b, color, clampf(size, 0.1, 15.0), text.substr(0, 40))


func effect_burst(pos: Vector3, color: Color, size: float = 1.0) -> void:
	_fx(0, pos, pos, color, size, "")


func effect_ring(pos: Vector3, color: Color, radius: float = 3.0) -> void:
	_fx(1, pos, pos, color, radius, "")


func effect_line(a: Vector3, b: Vector3, color: Color) -> void:
	_fx(2, a, b, color, 1.0, "")


func effect_text(pos: Vector3, text: String, color: Color = Color.WHITE) -> void:
	_fx(3, pos, pos, color, 1.0, text)


func play_sound(sound_name: String, pos: Vector3) -> void:
	_fx(4, pos, pos, Color.WHITE, 1.0, sound_name)
