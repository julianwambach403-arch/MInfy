extends RefCounted
## Alle Spielwerte an einem Ort: Gegner, Quests, Schwerter, Orte.

const VILLAGE := Vector3(0, 0, 0)
const SPAWN := Vector3(0, 0, 7)
const MEADOW := Vector3(-8, 0, 48)
const FOREST := Vector3(58, 0, 0)
const RUINS := Vector3(4, 0, -66)
## Gretas Schmiede mit Esse, Amboss und Wasserfass (zum Selberschmieden)
const FORGE := Vector3(9.2, 0, -0.6)

const MAX_MANA := 100.0
const SPELL_COST := 25.0
const SPELL_SPEED := 16.0

## Fähigkeiten: werden mit dem angegebenen Level freigeschaltet.
## Auswahl in VR mit X/Y (linke Hand), Auslösen mit dem linken Trigger.
const SKILLS := [
	{
		"id": "fireball", "name": "Feuerball", "level": 1, "mana": 25.0, "cd": 0.8,
		"color": Color(1.0, 0.5, 0.15), "desc": "Wirft einen Feuerball in Zielrichtung.",
	},
	{
		"id": "heal", "name": "Heilung", "level": 2, "mana": 35.0, "cd": 8.0,
		"color": Color(0.4, 1.0, 0.5), "desc": "Heilt dich und alle Mitspieler in 6 m Umkreis.",
	},
	{
		"id": "frost", "name": "Frostnova", "level": 3, "mana": 30.0, "cd": 10.0,
		"color": Color(0.5, 0.85, 1.0), "desc": "Eiswelle um dich herum: Schaden und Verlangsamung.",
	},
	{
		"id": "whirl", "name": "Wirbelwind", "level": 4, "mana": 20.0, "cd": 7.0,
		"color": Color(0.95, 0.95, 0.95), "desc": "Schwert-Rundumschlag gegen alle Gegner in der Nähe.",
	},
	{
		"id": "lightning", "name": "Kettenblitz", "level": 5, "mana": 40.0, "cd": 6.0,
		"color": Color(0.75, 0.65, 1.0), "desc": "Blitz springt auf bis zu 3 Gegner über.",
	},
	{
		"id": "shield", "name": "Schutzschild", "level": 6, "mana": 30.0, "cd": 20.0,
		"color": Color(1.0, 0.85, 0.3), "desc": "Halbiert 6 Sekunden lang jeden Schaden.",
	},
]

## Erfolge: Für jeden geschafften Erfolg programmiert Claude eine eigene Fähigkeit.
## "stat" bezieht sich auf die Spielstatistik des Spielers (siehe server.gd).
const ACHIEVEMENTS := [
	{"id": "first_blood", "name": "Erster Sieg", "desc": "Besiege deinen ersten Gegner.", "stat": "kills_total", "goal": 1},
	{"id": "slime_hunter", "name": "Schleimjäger", "desc": "Besiege 25 Schleime.", "stat": "kills_slime", "goal": 25},
	{"id": "wolf_slayer", "name": "Wolfsbezwinger", "desc": "Besiege 15 Wölfe.", "stat": "kills_wolf", "goal": 15},
	{"id": "golem_breaker", "name": "Golembrecher", "desc": "Besiege den Steingolem.", "stat": "kills_golem", "goal": 1},
	{"id": "village_hero", "name": "Retter des Dorfes", "desc": "Erfülle alle Aufgaben von Bruno.", "stat": "quests", "goal": 3},
	{"id": "level5", "name": "Erfahren", "desc": "Erreiche Level 5.", "stat": "level", "goal": 5},
	{"id": "level10", "name": "Veteran", "desc": "Erreiche Level 10.", "stat": "level", "goal": 10},
	{"id": "swordmaster", "name": "Schwertmeister", "desc": "Triff 300-mal mit dem Schwert.", "stat": "sword_hits", "goal": 300},
	{"id": "spellweaver", "name": "Zauberweber", "desc": "Setze 100 Fähigkeiten ein.", "stat": "casts", "goal": 100},
	{"id": "lifesaver", "name": "Lebensretter", "desc": "Heile insgesamt 1000 Lebenspunkte.", "stat": "healed", "goal": 1000},
	{"id": "phoenix", "name": "Stehaufmännchen", "desc": "Werde 5-mal besiegt und steh wieder auf.", "stat": "deaths", "goal": 5},
	{"id": "goldhoarder", "name": "Goldhamster", "desc": "Besitze 500 Gold auf einmal.", "stat": "gold", "goal": 500},
	{"id": "crystal_blade", "name": "Kristallklinge", "desc": "Schmiede eine Waffe aus Kristall.", "stat": "sword", "goal": 3},
	{"id": "first_forge", "name": "Lehrling der Esse", "desc": "Schmiede deine erste eigene Waffe.", "stat": "forged", "goal": 1},
	{"id": "master_smith", "name": "Meisterschmied", "desc": "Schmiede eine meisterhafte Waffe (Qualität 85 %+).", "stat": "masterwork", "goal": 1},
]

## Eigene Fähigkeiten haben Nummern ab CUSTOM_BASE (100, 101, ...).
const CUSTOM_BASE := 100

const ENEMY_TYPES := ["slime", "wolf", "golem"]

const ENEMIES := {
	"slime": {
		"name": "Schleim", "level": 1, "hp": 30, "dmg": 4, "atk_rate": 1.4,
		"xp": 12, "gold": 2, "speed": 1.8, "radius": 0.5, "height": 0.85,
		"aggro": 7.0, "leash": 22.0, "respawn": 12.0,
		"loot": [["iron", 0.3, 1]],
	},
	"wolf": {
		"name": "Wolf", "level": 3, "hp": 75, "dmg": 9, "atk_rate": 1.1,
		"xp": 30, "gold": 5, "speed": 4.0, "radius": 0.6, "height": 1.1,
		"aggro": 11.0, "leash": 28.0, "respawn": 18.0,
		"loot": [["iron", 0.6, 1], ["gold", 0.15, 1]],
	},
	"golem": {
		"name": "Steingolem", "level": 7, "hp": 700, "dmg": 20, "atk_rate": 2.0,
		"xp": 300, "gold": 80, "speed": 2.0, "radius": 1.3, "height": 3.4,
		"aggro": 13.0, "leash": 18.0, "respawn": 90.0,
		"loot": [["gold", 1.0, 3], ["crystal", 1.0, 2]],
	},
}

const SPAWNS := [
	{"type": "slime", "center": MEADOW, "radius": 16.0, "count": 10},
	{"type": "wolf", "center": FOREST, "radius": 16.0, "count": 8},
	{"type": "golem", "center": RUINS, "radius": 0.0, "count": 1},
]

const QUESTS := [
	{
		"title": "Schleimplage",
		"text": "Schleime fressen unsere Blumen! Besiege 6 Schleime auf der Wiese im Süden.",
		"target": "slime", "count": 6, "xp": 60, "gold": 20,
	},
	{
		"title": "Das Wolfsrudel",
		"text": "Im Dunkelwald im Osten heulen die Wölfe. Besiege 5 Wölfe. Lass dir vorher bei Greta ein besseres Schwert schmieden!",
		"target": "wolf", "count": 5, "xp": 150, "gold": 50,
	},
	{
		"title": "Der Steingolem",
		"text": "In den alten Ruinen im Norden ist ein Steingolem erwacht. Besiegt ihn gemeinsam! Achtung vor seinem Stampfangriff.",
		"target": "golem", "count": 1, "xp": 500, "gold": 200,
	},
]

const NPCS := {
	"elder": {"name": "Ältester Bruno", "pos": Vector3(-3.5, 0, -3.0)},
	"smith": {"name": "Schmiedin Greta", "pos": Vector3(7.5, 0, 1.5)},
}

const COLORS := [
	Color(0.2, 0.45, 0.9), Color(0.9, 0.3, 0.55), Color(0.3, 0.75, 0.35),
	Color(0.95, 0.65, 0.15), Color(0.6, 0.35, 0.85), Color(0.15, 0.75, 0.8),
]
const COLOR_NAMES := ["Blau", "Pink", "Grün", "Orange", "Lila", "Türkis"]

## ---------------- Schmieden ----------------
const ORES := {"iron": "Eisenerz", "gold": "Golderz", "crystal": "Kristall"}
const ORE_PRICE := 15  # Greta verkauft Eisenerz für so viel Gold

## Waffentypen: Schaden-Multiplikator, Rückstoß, Grammatik für den Namen
const WEAPON_TYPES := [
	{"name": "Schwert", "suffix": "schwert", "ending": "es", "mult": 1.0, "knockback": 0.0},
	{"name": "Axt", "suffix": "axt", "ending": "e", "mult": 1.25, "knockback": 0.0},
	{"name": "Streitkolben", "suffix": "streitkolben", "ending": "er", "mult": 1.1, "knockback": 1.5},
]
const MATERIALS := ["Holz", "Eisen", "Gold", "Kristall"]

## Rezepte je Material (Index wie MATERIALS / SWORDS)
const RECIPES := [
	{},
	{"iron": 3},
	{"iron": 2, "gold": 4},
	{"gold": 3, "crystal": 3},
]

## Material-Stufen (Index 0..3). "mult" = Grundschaden, "color" = Klingenfarbe.
const SWORDS := [
	{"name": "Holzschwert", "color": Color(0.62, 0.44, 0.26), "glow": 0.0, "mult": 1.0, "cost": 0},
	{"name": "Eisenschwert", "color": Color(0.78, 0.8, 0.85), "glow": 0.0, "mult": 1.35, "cost": 40},
	{"name": "Goldschwert", "color": Color(1.0, 0.8, 0.25), "glow": 0.3, "mult": 1.8, "cost": 120},
	{"name": "Kristallschwert", "color": Color(0.4, 0.9, 1.0), "glow": 1.5, "mult": 2.5, "cost": 300},
]


static func xp_needed(level: int) -> int:
	return int(40.0 * pow(float(level), 1.5))


static func max_hp(level: int) -> float:
	return 80.0 + 20.0 * float(level - 1)


static func sword_damage(level: int, tier: int) -> float:
	var t: Dictionary = SWORDS[clampi(tier, 0, SWORDS.size() - 1)]
	return (8.0 + 3.0 * float(level - 1)) * float(t["mult"])


static func spell_damage(level: int) -> float:
	return 14.0 + 4.0 * float(level - 1)


static func enemy_def(type_name: String) -> Dictionary:
	return ENEMIES[type_name]


static func heal_amount(level: int) -> float:
	return 30.0 + 8.0 * float(level - 1)


static func recipe_text(mat: int) -> String:
	var r: Dictionary = RECIPES[clampi(mat, 0, RECIPES.size() - 1)]
	var parts: Array = []
	for k in r:
		parts.append("%d %s" % [r[k], ORES[k]])
	return ", ".join(PackedStringArray(parts)) if not parts.is_empty() else "nichts"


## Qualität 0..1 -> Schaden x0.8 .. x1.2
static func quality_mult(q: float) -> float:
	return 0.8 + 0.4 * clampf(q, 0.0, 1.0)


static func weapon_damage(level: int, tier: int, wtype: int, q: float) -> float:
	var wt: Dictionary = WEAPON_TYPES[clampi(wtype, 0, WEAPON_TYPES.size() - 1)]
	return sword_damage(level, tier) * float(wt["mult"]) * quality_mult(q)


static func weapon_name(wtype: int, tier: int, q: float) -> String:
	var wt: Dictionary = WEAPON_TYPES[clampi(wtype, 0, WEAPON_TYPES.size() - 1)]
	var n: String = MATERIALS[clampi(tier, 0, MATERIALS.size() - 1)] + str(wt["suffix"])
	var e: String = wt["ending"]
	if q >= 0.85:
		return "Meisterhaft%s %s" % [e, n]
	if q >= 0.65:
		return "Gut%s %s" % [e, n]
	if q < 0.35:
		return "Grob%s %s" % [e, n]
	return n
