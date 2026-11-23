extends Node
## Skill-Schmiede: Lässt bei jedem Erfolg von der Claude Code CLI eine eigene
## Fähigkeit (GDScript) programmieren, prüft den Code und lädt ihn.
## Läuft nur auf dem Server. Aufträge werden nacheinander abgearbeitet.

const D = preload("res://scripts/game_data.gd")
const Cfg = preload("res://scripts/config.gd")

const WORK_DIR := "user://claude_work"
const SKILL_DIR := "user://custom_skills"
const MAX_ATTEMPTS := 2

## Diese Wörter darf der erzeugte Code nicht enthalten (Sicherheit + Stabilität).
const FORBIDDEN := [
	"OS", "Engine", "FileAccess", "DirAccess", "ResourceLoader", "ResourceSaver", "ProjectSettings",
	"ClassDB", "load", "preload", "GDScript", "Script", "set_script", "get_script", "Expression",
	"JavaScriptBridge", "Thread", "Mutex", "Semaphore", "WorkerThreadPool", "HTTPRequest",
	"HTTPClient", "StreamPeerTCP", "PacketPeerUDP", "TCPServer", "UDPServer", "WebSocketPeer",
	"ENetConnection", "ENetMultiplayerPeer", "MultiplayerAPI", "multiplayer", "Game", "IP", "Input",
	"DisplayServer", "RenderingServer", "PhysicsServer3D", "Object", "Node", "SceneTree", "get_tree",
	"get_node", "instance_from_id", "str_to_var", "bytes_to_var", "bytes_to_var_with_objects",
	"call", "callv", "call_deferred", "get", "set", "get_meta", "set_meta", "get_indexed",
	"set_indexed", "emit_signal", "connect", "Callable", "while", "await", "class_name", "static",
	"weakref", "free", "queue_free", "Marshalls", "Crypto", "EditorInterface", "rpc", "rpc_id",
	"script", "source_code", "reload", "char", "new",
]

const API_DOC := """# MInfy – Schnittstelle für eigene Fähigkeiten

Eine Fähigkeit ist EINE Datei `skill.gd` mit genau diesem Aufbau:

```gdscript
extends RefCounted

const SKILL_NAME := "Kurzer Name"          # max. 28 Zeichen, deutsch
const DESCRIPTION := "Ein Satz, was sie tut." # max. 140 Zeichen, deutsch
const COLOR := Color(0.6, 0.2, 1.0)          # Leuchtfarbe der Fähigkeit
const MANA := 30.0                           # 10 bis 60
const COOLDOWN := 8.0                        # 3 bis 30 Sekunden

func cast(api, caster_id: int, origin: Vector3, direction: Vector3) -> void:
	# origin = linke Hand des Spielers, direction = Zielrichtung (normalisiert)
	pass
```

Die Welt: Y ist oben, Einheiten sind Meter. Gegner: Schleime (klein), Wölfe (schnell), ein Steingolem (Boss).
Die Fähigkeit läuft auf dem Server. Sie darf NUR über das Objekt `api` wirken.

## Informationen
- `api.caster_id() -> int`, `api.caster_level() -> int`
- `api.caster_position() -> Vector3` (Füße), `api.caster_head() -> Vector3`
- `api.caster_hp_ratio() -> float` (0..1)
- `api.base_damage() -> float` – normaler Zauberschaden für das Level
- `api.base_heal() -> float` – normale Heilmenge für das Level
- `api.random() -> float` (0..1)
- `api.ground_height(x: float, z: float) -> float`
- `api.enemies_in_radius(center: Vector3, radius: float) -> Array` (Gegner-IDs, Radius max. 15)
- `api.nearest_enemy(center: Vector3, max_dist: float) -> int` (-1 = keiner)
- `api.enemy_in_direction(origin: Vector3, direction: Vector3, max_dist: float) -> int` (-1 = keiner)
- `api.is_enemy_alive(id: int) -> bool`, `api.enemy_position(id: int) -> Vector3` (Körpermitte), `api.enemy_hp(id: int) -> int`
- `api.players_in_radius(center: Vector3, radius: float) -> Array` (Spieler-IDs inkl. Zaubernder)
- `api.player_position(id: int) -> Vector3`

## Aktionen (das Spiel begrenzt die Summe pro Einsatz automatisch!)
- `api.damage_enemy(id: int, amount: float)` – Gesamtschaden pro Einsatz max. 6 × base_damage()
- `api.slow_enemy(id: int, seconds: float)` – max. 6 s
- `api.knockback_enemy(id: int, from: Vector3, distance: float)` – max. 6 m
- `api.heal_player(id: int, amount: float)` – Gesamtheilung pro Einsatz max. 1,5 × base_heal()
- `api.shield_player(id: int, seconds: float)` – halber Schaden, max. 8 s
- `api.dash(direction: Vector3, distance: float)` – teleportiert den Zaubernden, max. 10 m, max. 2× pro Einsatz
- `api.spawn_projectile(origin: Vector3, direction: Vector3, speed: float, damage_mult: float, color: Color)` – Geschoss, speed 4..30, damage_mult 0.2..2 (verbraucht Schadensbudget)
- `api.after(seconds: float, fn)` – führt eine Lambda-Funktion später aus (0,05..5 s, max. 10×), z. B. `api.after(0.5, func(): api.effect_burst(p, COLOR, 1.0))`

## Effekte (nur Optik/Ton, max. 80 pro Einsatz)
- `api.effect_burst(pos: Vector3, color: Color, size: float = 1.0)` – Partikelexplosion
- `api.effect_ring(pos: Vector3, color: Color, radius: float = 3.0)` – sich ausbreitender Ring am Boden
- `api.effect_line(a: Vector3, b: Vector3, color: Color)` – Blitz/Strahl zwischen zwei Punkten
- `api.effect_text(pos: Vector3, text: String, color: Color = Color.WHITE)` – schwebender Text
- `api.play_sound(name: String, pos: Vector3)` – name: swing, hit, hurt, cast, explode, levelup, coin, quest, upgrade, die, slam

## Strenge Regeln
- Nur `extends RefCounted`, die 5 Konstanten und `func cast(...)`. Eigene Hilfsfunktionen sind erlaubt.
- KEINE `while`-Schleifen, KEIN `await`, keine Zahlen größer als 500, keine verschachtelten Schleifen mit mehr als 50 Durchläufen insgesamt.
- Verbotene Wörter (auch in Kommentaren): %s
- Kein Zugriff auf Mitglieder, die mit `_` beginnen, und kein Zugriff per `x["text"]`.
- Typen bei `var` mit `:=` nur, wenn der Typ eindeutig ist; Rückgaben von `api.*` mit expliziten Typen deklarieren, z. B. `var pos: Vector3 = api.caster_position()`.
- Gültiges Godot-4-GDScript mit Tabs als Einrückung.
"""

const EXAMPLE := """extends RefCounted

const SKILL_NAME := "Sternenregen"
const DESCRIPTION := "Lässt drei Sterne auf den nächsten Gegner regnen, die Gegner in der Nähe zurückstoßen."
const COLOR := Color(1.0, 0.9, 0.4)
const MANA := 35.0
const COOLDOWN := 9.0


func cast(api, caster_id: int, origin: Vector3, direction: Vector3) -> void:
	var target: int = api.nearest_enemy(api.caster_position(), 15.0)
	if target < 0:
		api.effect_text(api.caster_head() + Vector3(0, 0.5, 0), "Kein Ziel", COLOR)
		return
	for i in 3:
		api.after(0.3 * i, func(): _star(api, target))


func _star(api, target: int) -> void:
	if not api.is_enemy_alive(target):
		return
	var pos: Vector3 = api.enemy_position(target)
	api.effect_line(pos + Vector3(0, 8, 0), pos, COLOR)
	api.effect_burst(pos, COLOR, 1.5)
	api.play_sound("explode", pos)
	for eid in api.enemies_in_radius(pos, 3.0):
		api.damage_enemy(eid, api.base_damage() * 0.8)
		api.knockback_enemy(eid, pos, 2.0)
"""

const PROMPT := """Du bist Spieldesigner und GDScript-Programmierer für das kleine VR-Rollenspiel MInfy (Godot 4).

Ein Spieler hat gerade einen Erfolg geschafft. Erfinde dafür eine EIGENE, einzigartige Fähigkeit,
die zum Erfolg UND zur Spielweise des Spielers passt, und programmiere sie.

1. Lies `CONTEXT.md` (was der Spieler geschafft hat und wie er spielt).
2. Lies `SKILL_API.md` (die einzige erlaubte Schnittstelle und die Regeln).
3. Sieh dir `example_skill.gd` als Beispiel an.
4. Schreibe deine Fähigkeit in die Datei `skill.gd` in diesem Ordner. Halte dich exakt an die Regeln.

Sei kreativ (Name, Effekte, Kombinationen), aber fair: Stark genug, um Spaß zu machen.
Name und Beschreibung auf Deutsch. Erstelle oder ändere keine anderen Dateien.
"""

var server
var queue: Array = []
var busy := false
var current: Dictionary = {}
var thread: Thread = null
var claude_cmd: String = Cfg.CLAUDE_COMMAND
var enabled: bool = Cfg.CLAUDE_ENABLED


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(WORK_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SKILL_DIR))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--claude="):
			claude_cmd = a.substr(9)
		elif a == "--no-claude":
			enabled = false
	print("[Skill-Schmiede] Claude Code: %s (%s)" % ["an" if enabled else "aus", claude_cmd])


func _exit_tree() -> void:
	if thread != null and thread.is_started():
		thread.wait_to_finish()


static func skill_path(player_name: String, ach_id: String) -> String:
	return "%s/%s/%s.gd" % [SKILL_DIR, player_name.to_lower().validate_filename(), ach_id]


func is_queued(player_name: String, ach_id: String) -> bool:
	if busy and current.get("player") == player_name and current.get("ach") == ach_id:
		return true
	for j in queue:
		if j["player"] == player_name and j["ach"] == ach_id:
			return true
	return false


func is_forging_for(player_name: String) -> bool:
	if busy and current.get("player") == player_name:
		return true
	for j in queue:
		if j["player"] == player_name:
			return true
	return false


## Auftrag: eigene Fähigkeit für einen Erfolg erzeugen.
func request(player_name: String, ach: Dictionary, context: String) -> void:
	if is_queued(player_name, ach["id"]):
		return
	queue.append({"player": player_name, "ach": ach["id"], "ach_name": ach["name"],
		"context": context, "attempt": 0})
	_next()


func _next() -> void:
	if busy or queue.is_empty():
		return
	current = queue.pop_front()
	busy = true
	var dir := "%s/%s_%s" % [WORK_DIR, str(current["player"]).to_lower().validate_filename(), current["ach"]]
	var abs_dir := ProjectSettings.globalize_path(dir)
	current["dir"] = abs_dir
	if current["attempt"] == 0:
		DirAccess.make_dir_recursive_absolute(abs_dir)
		_write(abs_dir + "/PROMPT.md", PROMPT)
		_write(abs_dir + "/SKILL_API.md", API_DOC % ", ".join(PackedStringArray(FORBIDDEN)))
		_write(abs_dir + "/example_skill.gd", EXAMPLE)
		_write(abs_dir + "/CONTEXT.md", current["context"])
		if FileAccess.file_exists(abs_dir + "/skill.gd"):
			DirAccess.remove_absolute(abs_dir + "/skill.gd")
	if not enabled:
		_finish(null)
		return
	print("[Skill-Schmiede] Claude programmiert eine Fähigkeit für %s (%s), Versuch %d ..." % [
		current["player"], current["ach_name"], int(current["attempt"]) + 1])
	thread = Thread.new()
	thread.start(_run_claude.bind(abs_dir, int(current["attempt"]), claude_cmd))


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(text)
		f.close()


## Läuft im Hintergrund-Thread, damit der Server nicht stockt.
func _run_claude(abs_dir: String, attempt: int, cmd: String) -> void:
	var prompt := "Lies PROMPT.md und befolge die Anweisungen genau."
	if attempt > 0:
		prompt = "Lies PROMPT.md, SKILL_API.md und FEEDBACK.md. Die Datei skill.gd wurde abgelehnt. Korrigiere skill.gd."
	var flags := "-p \"%s\" --permission-mode acceptEdits --allowedTools \"Read,Write,Edit,Glob\" --disallowedTools \"Bash,WebFetch,WebSearch\" --max-turns 20" % prompt
	if Cfg.CLAUDE_MODEL != "":
		flags += " --model %s" % Cfg.CLAUDE_MODEL
	var out: Array = []
	var code := -1
	if OS.get_name() == "Windows":
		code = OS.execute("cmd.exe", ["/c", "cd /d \"%s\" && %s %s" % [abs_dir, cmd, flags]], out, true)
	else:
		var timeout := "timeout 600 " if OS.get_name() == "Linux" else ""
		code = OS.execute("/bin/sh", ["-c", "cd '%s' && %s%s %s" % [abs_dir, timeout, cmd, flags]], out, true)
	call_deferred("_on_claude_done", code, "\n".join(PackedStringArray(out)))


func _on_claude_done(code: int, output: String) -> void:
	if thread != null:
		thread.wait_to_finish()
		thread = null
	var abs_dir: String = current["dir"]
	var path := abs_dir + "/skill.gd"
	var src := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	if code != 0:
		print("[Skill-Schmiede] Claude Code beendet mit Code %d. Ausgabe:\n%s" % [code, output.right(1500)])
		if code == 127 or code == 9009 or code == -1:
			print("[Skill-Schmiede] 'claude' wurde nicht gefunden. Installiere die Claude Code CLI (siehe README) oder starte mit --claude=/pfad/zu/claude.")
	var result := validate(src)
	if result["ok"]:
		_finish(src)
		return
	print("[Skill-Schmiede] skill.gd abgelehnt: %s" % result["error"])
	if src != "" and int(current["attempt"]) + 1 < MAX_ATTEMPTS:
		_write(abs_dir + "/FEEDBACK.md", "Deine skill.gd wurde vom Spielserver abgelehnt:\n\n%s\n\nBitte korrigiere skill.gd. Halte dich strikt an SKILL_API.md.\n" % result["error"])
		current["attempt"] = int(current["attempt"]) + 1
		queue.push_front(current)
		busy = false
		_next()
		return
	_finish(null)


## src == null -> Ersatz-Fähigkeit verwenden.
func _finish(src) -> void:
	var by_claude := src != null
	var code: String = src if by_claude else fallback_source(current["ach_name"])
	var path := skill_path(current["player"], current["ach"])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	_write(ProjectSettings.globalize_path(path), code)
	print("[Skill-Schmiede] Fähigkeit gespeichert: %s (%s)" % [path, "von Claude" if by_claude else "Ersatz"])
	server.on_custom_skill_ready(current["player"], current["ach"], by_claude)
	busy = false
	current = {}
	_next()


static func _strip_comments(src: String) -> String:
	var lines := []
	for line in src.split("\n"):
		var idx: int = line.find("#")
		lines.append(line if idx < 0 else line.substr(0, idx))
	return "\n".join(PackedStringArray(lines))


## Prüft Quelltext, kompiliert ihn und liest die Metadaten.
static func validate(src: String) -> Dictionary:
	var fail := func(msg: String) -> Dictionary: return {"ok": false, "error": msg}
	if src.strip_edges() == "":
		return fail.call("skill.gd fehlt oder ist leer.")
	if src.length() > 12000:
		return fail.call("skill.gd ist zu lang (max. 12000 Zeichen).")
	var scan := _strip_comments(src)
	var errors: Array = []
	for word in FORBIDDEN:
		var re := RegEx.create_from_string("\\b%s\\b" % word)
		if re.search(scan) != null:
			errors.append("Verbotenes Wort: '%s'" % word)
	if RegEx.create_from_string("\\[\\s*[\"'&^]").search(scan) != null:
		errors.append("Zugriff per [\"text\"] ist verboten (keine Dictionaries mit Text-Schlüsseln).")
	if RegEx.create_from_string("\\._").search(scan) != null:
		errors.append("Zugriff auf Mitglieder mit '_' ist verboten.")
	if RegEx.create_from_string("(?<![\\d.])\\d{4,}").search(scan) != null:
		errors.append("Zahlen größer als 500 sind verboten.")
	if not scan.contains("extends RefCounted"):
		errors.append("Die Datei muss mit 'extends RefCounted' beginnen.")
	if not errors.is_empty():
		return fail.call("\n".join(PackedStringArray(errors)))
	var gs := GDScript.new()
	gs.source_code = src
	if gs.reload() != OK:
		return fail.call("Kompilierfehler: Der GDScript-Code ist ungültig (Syntax/Typen prüfen, Tabs verwenden).")
	var consts := gs.get_script_constant_map()
	for k in ["SKILL_NAME", "DESCRIPTION", "COLOR", "MANA", "COOLDOWN"]:
		if not consts.has(k):
			return fail.call("Konstante %s fehlt." % k)
	if not (consts["COLOR"] is Color):
		return fail.call("COLOR muss ein Color sein.")
	var inst = gs.new()
	if inst == null or not inst.has_method("cast"):
		return fail.call("Funktion cast(api, caster_id, origin, direction) fehlt.")
	return {
		"ok": true, "error": "", "instance": inst,
		"meta": {
			"name": str(consts["SKILL_NAME"]).substr(0, 28),
			"desc": str(consts["DESCRIPTION"]).substr(0, 140),
			"color": consts["COLOR"],
			"mana": clampf(float(consts["MANA"]), 10.0, 60.0),
			"cd": clampf(float(consts["COOLDOWN"]), 3.0, 30.0),
		},
	}


## Ersatz, falls Claude nicht erreichbar ist oder zweimal ungültigen Code liefert.
static func fallback_source(ach_name: String) -> String:
	var h := absi(ach_name.hash())
	var col := Color.from_hsv(float(h % 360) / 360.0, 0.7, 1.0)
	var safe := ach_name.replace("\"", "").replace("\\", "")
	return """extends RefCounted

const SKILL_NAME := "Echo: %s"
const DESCRIPTION := "Entfesselt die Kraft deines Erfolgs in einer Schockwelle, die Gegner zurückstößt."
const COLOR := Color(%.2f, %.2f, %.2f)
const MANA := 30.0
const COOLDOWN := 9.0


func cast(api, caster_id: int, origin: Vector3, direction: Vector3) -> void:
	var center: Vector3 = api.caster_position()
	api.effect_ring(center, COLOR, 6.0)
	api.effect_burst(center + Vector3(0, 1, 0), COLOR, 2.0)
	api.play_sound("slam", center)
	for eid in api.enemies_in_radius(center, 6.0):
		api.damage_enemy(eid, api.base_damage() * 1.5)
		api.knockback_enemy(eid, center, 3.0)
""" % [safe.substr(0, 20), col.r, col.g, col.b]
