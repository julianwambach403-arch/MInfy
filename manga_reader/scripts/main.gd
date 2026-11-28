extends Node3D
## Manga VR – Hauptprogramm.
## Startet OpenXR (Quest 3) oder am PC einen Desktop-Testmodus, baut Lesezimmer,
## Bibliothek und Buch und verteilt die Hand-Eingaben.

const Cfg = preload("res://scripts/config.gd")
const Hands = preload("res://scripts/hands.gd")
const UI = preload("res://scripts/ui3d.gd")
const Book = preload("res://scripts/book.gd")
const PageCache = preload("res://scripts/page_cache.gd")
const LocalSource = preload("res://scripts/local_source.gd")
const KomgaSource = preload("res://scripts/komga_source.gd")

const PROGRESS_FILE := "user://fortschritt.json"
const GRID_COLS := 5
const GRID_ROWS := 2
const CH_ROWS := 8

var vr := false
var xr: XRInterface
var origin: XROrigin3D
var camera: Camera3D
var hands: Hands
var ui: UI
var cache: PageCache
var book: Book
var env: Environment
var room: Node3D
var passthrough := false

var sources: Array = []
var series: Array = []          # alle Serien aller Quellen
var lib_page := 0
var cur_series: Dictionary = {}
var chapters: Array = []
var ch_page := 0
var cur_chapter := -1
var progress := {}

var lib_root: Node3D           # Bibliothek-Panel
var lib_cells: Array = []
var lib_title: Label3D
var lib_status: Label3D
var ch_root: Node3D            # Kapitel-Liste
var ch_cells: Array = []
var ch_title: Label3D
var toolbar: Node3D
var tb_page: Label3D
var menu: Node3D               # Schnellmenü (Handfläche / Y-Taste)
var menu_buttons := {}
var toast: Label3D
var _toast_t := 0.0

# Buch festhalten
var _grab_hand = null
var _grab_offset := Transform3D()
var _two_hand := false
var _two_d0 := 1.0
var _two_s0 := 1.0
var _two_off := Transform3D()
var _book_scale := 1.0
var _flip_hand = null
var _menu_pinned := false
var _save_t := 0.0


func _ready() -> void:
	vr = _init_xr()
	_build_environment()
	_build_rig()
	cache = PageCache.new()
	add_child(cache)
	ui = UI.new()
	ui.hands = hands
	add_child(ui)
	book = Book.new()
	book.cache = cache
	book.rtl = Cfg.RIGHT_TO_LEFT
	add_child(book)
	book.visible = false
	cache.page_ready.connect(_on_page_ready)
	book.spread_changed.connect(_on_spread_changed)
	book.beyond_end.connect(_on_beyond_end)
	hands.mouse_surface = func(from: Vector3, dir: Vector3):
		if book.visible and not ui.pointer_over_ui(from, dir):
			return book.ray_point(from, dir)
		return null
	_build_toolbar()
	_build_library()
	_build_chapters()
	_build_menu()
	toast = ui.label(camera, "", 30, Vector3(0, 0.1, -0.7))
	toast.no_depth_test = true
	toast.render_priority = 10
	toast.outline_size = 8
	toast.outline_modulate = Color(0, 0, 0, 0.7)
	_load_progress()
	set_passthrough(Cfg.START_IN_PASSTHROUGH)
	_request_storage_permission()
	_setup_sources()
	await get_tree().process_frame
	_show_library()


# ================================================================ XR

func _init_xr() -> bool:
	if "--desktop" in OS.get_cmdline_user_args():
		return false
	xr = XRServer.find_interface("OpenXR")
	if xr != null and xr.is_initialized():
		get_viewport().use_xr = true
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		var oxr := xr as OpenXRInterface
		if oxr:
			oxr.session_begun.connect(_on_session_begun.bind(oxr))
			oxr.pose_recentered.connect(_on_recentered)
		print("[MangaVR] OpenXR aktiv.")
		return true
	print("[MangaVR] Keine VR-Brille – Desktop-Testmodus. Maus: Seite ziehen/klicken, Pfeiltasten blättern.")
	return false


func _on_session_begun(oxr: OpenXRInterface) -> void:
	var rates := oxr.get_available_display_refresh_rates()
	if rates.has(90.0):
		oxr.display_refresh_rate = 90.0
	if Cfg.RENDER_SCALE != 1.0 and "render_target_size_multiplier" in oxr:
		oxr.set("render_target_size_multiplier", Cfg.RENDER_SCALE)
	set_passthrough(passthrough)


func _on_recentered() -> void:
	await get_tree().process_frame
	if book.visible:
		_place_book()
	if lib_root.visible or ch_root.visible:
		_place_panel(lib_root if lib_root.visible else ch_root)


func _build_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.09, 0.08, 0.08)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1.0, 0.92, 0.82)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	sun.light_energy = 0.5
	sun.light_color = Color(1.0, 0.95, 0.88)
	add_child(sun)
	room = _build_room()
	add_child(room)


## Gemütliches Lesezimmer aus einfachen Formen (nur sichtbar ohne Passthrough).
func _build_room() -> Node3D:
	var r := Node3D.new()
	var wood := Color(0.36, 0.23, 0.14)
	var wall := Color(0.55, 0.47, 0.38)
	_box(r, Vector3(6, 0.05, 6), Vector3(0, -0.025, 0), Color(0.3, 0.2, 0.13))           # Boden
	_box(r, Vector3(6, 3, 0.1), Vector3(0, 1.5, -2.6), wall)                              # Wand vorne
	_box(r, Vector3(6, 3, 0.1), Vector3(0, 1.5, 2.6), wall.darkened(0.1))
	_box(r, Vector3(0.1, 3, 6), Vector3(-2.6, 1.5, 0), wall.darkened(0.05))
	_box(r, Vector3(0.1, 3, 6), Vector3(2.6, 1.5, 0), wall.darkened(0.05))
	_box(r, Vector3(6, 0.05, 6), Vector3(0, 3.0, 0), Color(0.42, 0.38, 0.33))              # Decke
	_box(r, Vector3(2.0, 0.02, 1.4), Vector3(0, 0.005, -0.3), Color(0.45, 0.13, 0.12))     # Teppich
	# Bücherregal an der Wand mit bunten Buchrücken
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for shelf in 5:
		var y := 0.35 + shelf * 0.42
		_box(r, Vector3(2.4, 0.03, 0.3), Vector3(0, y, -2.4), wood)
		var x := -1.15
		while x < 1.12:
			var w := rng.randf_range(0.025, 0.06)
			var h := rng.randf_range(0.24, 0.36)
			var c := Color.from_hsv(rng.randf(), rng.randf_range(0.3, 0.7), rng.randf_range(0.3, 0.75))
			_box(r, Vector3(w, h, 0.2), Vector3(x + w * 0.5, y + 0.015 + h * 0.5, -2.38), c)
			x += w + 0.004
	_box(r, Vector3(0.04, 2.2, 0.3), Vector3(-1.22, 1.1, -2.4), wood)
	_box(r, Vector3(0.04, 2.2, 0.3), Vector3(1.22, 1.1, -2.4), wood)
	# Stehlampe mit warmem Licht
	_box(r, Vector3(0.03, 1.5, 0.03), Vector3(0.9, 0.75, -0.9), Color(0.15, 0.15, 0.15))
	var shade := _box(r, Vector3(0.32, 0.22, 0.32), Vector3(0.9, 1.6, -0.9), Color(1.0, 0.85, 0.6))
	(shade.material_override as StandardMaterial3D).emission_enabled = true
	(shade.material_override as StandardMaterial3D).emission = Color(1.0, 0.75, 0.45)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0.9, 1.55, -0.9)
	lamp.light_color = Color(1.0, 0.8, 0.55)
	lamp.light_energy = 1.6
	lamp.omni_range = 5.0
	r.add_child(lamp)
	# Fenster mit Abendhimmel
	var win := _box(r, Vector3(1.2, 0.9, 0.02), Vector3(-2.54, 1.6, -0.5), Color(0.35, 0.45, 0.75))
	win.rotation_degrees.y = 90
	(win.material_override as StandardMaterial3D).shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return r


func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	m.material_override = mat
	m.position = pos
	parent.add_child(m)
	return m


## Passthrough: Du siehst dein echtes Zimmer, das Buch schwebt darin.
func set_passthrough(on: bool) -> void:
	if on and vr and xr != null:
		var modes: Array = xr.get_supported_environment_blend_modes()
		if XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND in modes:
			xr.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND
			get_viewport().transparent_bg = true
			env.background_mode = Environment.BG_COLOR
			env.background_color = Color(0, 0, 0, 0)
			passthrough = true
		else:
			_say("Passthrough wird nicht unterstützt (Meta-Plugin installiert?)")
			passthrough = false
	else:
		passthrough = false
		if vr and xr != null:
			xr.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_OPAQUE
		get_viewport().transparent_bg = false
		env.background_color = Color(0.09, 0.08, 0.08)
	room.visible = not passthrough
	if menu_buttons.has("pt"):
		UI.set_text(menu_buttons.pt, "Echtes Zimmer: " + ("an" if passthrough else "aus"))


func _build_rig() -> void:
	origin = XROrigin3D.new()
	add_child(origin)
	origin.current = true
	if vr:
		camera = XRCamera3D.new()
	else:
		camera = Camera3D.new()
		camera.position = Vector3(0, 1.45, 0)
		camera.rotation.x = -0.3
		camera.fov = 70
	camera.near = 0.03
	camera.far = 50.0
	origin.add_child(camera)
	camera.current = true
	hands = Hands.new()
	add_child(hands)
	hands.setup(origin, camera, vr)


## Kopfposition ohne Neigung (für Platzierung vor dem Leser).
func _head_flat() -> Transform3D:
	var t := camera.global_transform
	var fwd := -t.basis.z
	fwd.y = 0
	if fwd.length() < 0.01:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()
	return Transform3D(Basis.looking_at(fwd, Vector3.UP), t.origin)


func _place_panel(p: Node3D) -> void:
	var h := _head_flat()
	var pos := h.origin + (-h.basis.z) * 0.62 + Vector3(0, -0.12, 0)
	p.global_transform = Transform3D(_facing_basis(h.origin + Vector3(0, -0.05, 0) - pos), pos)


## Buch in Lesehaltung vor den Leser legen (wie in den Händen gehalten).
func _place_book() -> void:
	var h := _head_flat()
	var pos := h.origin + (-h.basis.z) * 0.42 + Vector3(0, -0.2, 0)
	# Buch-Vorderseite (+Z) zeigt zum Auge, wie in den Händen gehalten
	book.global_transform = Transform3D(_facing_basis(camera.global_position - pos), pos)
	book.scale = Vector3.ONE * _book_scale


static func _facing_basis(z_dir: Vector3) -> Basis:
	var z := z_dir.normalized()
	var x := Vector3.UP.cross(z).normalized()
	var y := z.cross(x).normalized()
	return Basis(x, y, z)


# ================================================================ Quellen

func _request_storage_permission() -> void:
	if OS.get_name() != "Android":
		return
	get_tree().on_request_permissions_result.connect(func(perm: String, granted: bool):
		print("[MangaVR] Berechtigung ", perm, ": ", granted)
		if granted:
			_setup_sources())
	OS.request_permissions()


func _setup_sources() -> void:
	sources.clear()
	sources.append(LocalSource.new(Cfg.LOCAL_DIRS))
	if Cfg.KOMGA_URL != "":
		sources.append(KomgaSource.new(self, Cfg.KOMGA_URL, Cfg.KOMGA_USER, Cfg.KOMGA_PASSWORD))
	series.clear()
	for src in sources:
		src.list_series(func(list: Array):
			series.append_array(list)
			series.sort_custom(func(a, b): return a.title.naturalnocasecmp_to(b.title) < 0)
			if lib_root and lib_root.visible:
				_fill_library())


# ================================================================ Bibliothek

func _build_library() -> void:
	lib_root = Node3D.new()
	add_child(lib_root)
	var pw := 0.86
	var ph := 0.56
	ui.button(lib_root, "", Vector2(pw, ph), Vector3.ZERO, null, Color(0.07, 0.08, 0.11, 0.88))
	lib_title = ui.label(lib_root, "Bibliothek", 40, Vector3(0, ph * 0.5 - 0.03, 0.002))
	lib_status = ui.label(lib_root, "", 22, Vector3(0, -ph * 0.5 + 0.022, 0.002))
	lib_status.modulate = Color(0.75, 0.78, 0.85)
	var cw := 0.13
	var chh := 0.18
	for row in GRID_ROWS:
		for col in GRID_COLS:
			var x := (col - (GRID_COLS - 1) * 0.5) * (cw + 0.022)
			var y := 0.105 - row * (chh + 0.05)
			var i := row * GRID_COLS + col
			var cell := ui.image_button(lib_root, Vector2(cw, chh), Vector3(x, y, 0.003), func(): _open_series_slot(i))
			var name_l := ui.label(cell.node, "", 18, Vector3(0, -chh * 0.5 - 0.013, 0.001))
			name_l.width = cw / name_l.pixel_size
			name_l.autowrap_mode = TextServer.AUTOWRAP_OFF
			cell["name"] = name_l
			lib_cells.append(cell)
	ui.button(lib_root, "<", Vector2(0.06, 0.06), Vector3(-pw * 0.5 - 0.045, 0, 0.003), func(): _lib_scroll(-1))
	ui.button(lib_root, ">", Vector2(0.06, 0.06), Vector3(pw * 0.5 + 0.045, 0, 0.003), func(): _lib_scroll(1))
	ui.button(lib_root, "Neu laden", Vector2(0.14, 0.04), Vector3(pw * 0.5 - 0.09, ph * 0.5 - 0.03, 0.003), _setup_sources, Color(0.18, 0.22, 0.3, 0.95), 22)
	ui.button(lib_root, "Weiterlesen", Vector2(0.16, 0.04), Vector3(-pw * 0.5 + 0.1, ph * 0.5 - 0.03, 0.003), _continue_last, Color(0.35, 0.22, 0.12, 0.95), 22)
	lib_root.visible = false


func _show_library() -> void:
	book.visible = false
	toolbar.visible = false
	ch_root.visible = false
	lib_root.visible = true
	_place_panel(lib_root)
	_fill_library()


func _lib_scroll(d: int) -> void:
	var pages := maxi(1, ceili(series.size() / float(GRID_COLS * GRID_ROWS)))
	lib_page = clampi(lib_page + d, 0, pages - 1)
	_fill_library()


func _fill_library() -> void:
	var per := GRID_COLS * GRID_ROWS
	var pages := maxi(1, ceili(series.size() / float(per)))
	lib_page = clampi(lib_page, 0, pages - 1)
	for i in lib_cells.size():
		var cell: Dictionary = lib_cells[i]
		var si := lib_page * per + i
		var node: Node3D = cell.node
		node.visible = si < series.size()
		if not node.visible:
			continue
		var s: Dictionary = series[si]
		(cell.name as Label3D).text = _short(s.title, 20)
		var cover: Dictionary = s.get("cover", {})
		var tex: Texture2D = cache.get_texture(cover) if not cover.is_empty() else null
		if tex:
			UI.set_image(cell, tex, cache.get_aspect(cover))
		elif not cover.is_empty():
			cache.request(s.source, cover, 512)
	if series.is_empty():
		lib_status.text = "Keine Manga gefunden. Kopiere CBZ-Dateien oder Bilder-Ordner nach\n/sdcard/Download/Manga (siehe README) und tippe auf „Neu laden“."
	else:
		lib_status.text = "%d Serien · Seite %d/%d · Antippen oder zeigen + Finger zusammen" % [series.size(), lib_page + 1, pages]


static func _short(t: String, n: int) -> String:
	return t if t.length() <= n else t.substr(0, n - 1) + "…"


func _open_series_slot(i: int) -> void:
	var si := lib_page * GRID_COLS * GRID_ROWS + i
	if si >= series.size():
		return
	cur_series = series[si]
	ch_page = 0
	chapters = []
	ch_title.text = _short(cur_series.title, 32)
	lib_root.visible = false
	ch_root.global_transform = lib_root.global_transform
	ch_root.visible = true
	_fill_chapters()
	cur_series.source.list_chapters(cur_series, func(list: Array):
		chapters = list
		# zum zuletzt gelesenen Kapitel springen
		var last := _last_chapter_of_series()
		if last >= 0:
			ch_page = last / CH_ROWS
		_fill_chapters())


# ================================================================ Kapitel

func _build_chapters() -> void:
	ch_root = Node3D.new()
	add_child(ch_root)
	var pw := 0.62
	var ph := 0.56
	ui.button(ch_root, "", Vector2(pw, ph), Vector3.ZERO, null, Color(0.07, 0.08, 0.11, 0.88))
	ch_title = ui.label(ch_root, "", 34, Vector3(0, ph * 0.5 - 0.03, 0.002))
	ch_title.width = (pw - 0.25) / ch_title.pixel_size
	for i in CH_ROWS:
		var y := ph * 0.5 - 0.085 - i * 0.052
		var b := ui.button(ch_root, "", Vector2(pw - 0.06, 0.044), Vector3(0, y, 0.003), func(): _open_chapter_slot(i), Color(0.15, 0.17, 0.23, 0.95), 22)
		ch_cells.append(b)
	ui.button(ch_root, "Zurück", Vector2(0.12, 0.04), Vector3(-pw * 0.5 + 0.08, ph * 0.5 - 0.03, 0.003), _show_library, Color(0.3, 0.18, 0.18, 0.95), 22)
	ui.button(ch_root, "<", Vector2(0.06, 0.06), Vector3(-pw * 0.5 - 0.045, 0, 0.003), func(): _ch_scroll(-1))
	ui.button(ch_root, ">", Vector2(0.06, 0.06), Vector3(pw * 0.5 + 0.045, 0, 0.003), func(): _ch_scroll(1))
	ch_root.visible = false


func _ch_scroll(d: int) -> void:
	var pages := maxi(1, ceili(chapters.size() / float(CH_ROWS)))
	ch_page = clampi(ch_page + d, 0, pages - 1)
	_fill_chapters()


func _fill_chapters() -> void:
	var pages := maxi(1, ceili(chapters.size() / float(CH_ROWS)))
	ch_page = clampi(ch_page, 0, pages - 1)
	for i in CH_ROWS:
		var b: Dictionary = ch_cells[i]
		var ci := ch_page * CH_ROWS + i
		(b.node as Node3D).visible = ci < chapters.size()
		if ci < chapters.size():
			var ch: Dictionary = chapters[ci]
			var p: Dictionary = progress.get(str(ch.id), {})
			var mark := ""
			if p.get("done", false):
				mark = "  (gelesen)"
			elif p.has("page"):
				mark = "  · S. %d" % (int(p.page) + 1)
			UI.set_text(b, _short(str(ch.title), 44) + mark)
	if chapters.is_empty():
		UI.set_text(ch_cells[0], "Lade …")
		(ch_cells[0].node as Node3D).visible = true


func _last_chapter_of_series() -> int:
	var best := -1
	var best_t := 0.0
	for i in chapters.size():
		var p: Dictionary = progress.get(str(chapters[i].id), {})
		if p.get("t", 0.0) > best_t:
			best_t = p.t
			best = i
	return best


func _open_chapter_slot(i: int) -> void:
	var ci := ch_page * CH_ROWS + i
	if ci < chapters.size():
		_open_chapter(ci, -1)


## start_page: -1 = gespeicherter Fortschritt, sonst diese Seite (-2 = letzte Seite)
func _open_chapter(ci: int, start_page: int) -> void:
	cur_chapter = ci
	var ch: Dictionary = chapters[ci]
	_say("Öffne " + str(ch.title) + " …")
	cur_series.source.list_pages(ch, func(list: Array):
		if list.is_empty():
			_say("Keine Bilder in diesem Kapitel gefunden.")
			return
		var p := start_page
		if p == -1:
			var pr: Dictionary = progress.get(str(ch.id), {})
			p = 0 if pr.get("done", false) else int(pr.get("page", 0))
		elif p == -2:
			p = list.size() - 1
		cache.keep_only([])
		lib_root.visible = false
		ch_root.visible = false
		var first_open := not book.visible
		book.visible = true
		toolbar.visible = true
		if first_open:
			_place_book()
		book.open_chapter(cur_series.source, list, clampi(p, 0, list.size() - 1))
		progress["_last"] = {"series": str(cur_series.id), "chapter": str(ch.id), "title": cur_series.title}
		_save_progress())


func _continue_last() -> void:
	var last: Dictionary = progress.get("_last", {})
	if last.is_empty():
		_say("Noch nichts gelesen – wähle eine Serie.")
		return
	for s in series:
		if str(s.id) == last.series:
			cur_series = s
			s.source.list_chapters(s, func(list: Array):
				chapters = list
				for i in list.size():
					if str(list[i].id) == last.chapter:
						_open_chapter(i, -1)
						return
				_say("Kapitel nicht mehr gefunden."))
			return
	_say("Serie nicht mehr gefunden.")


func _on_beyond_end(forward: bool) -> void:
	if cur_chapter < 0:
		return
	var ni := cur_chapter + (1 if forward else -1)
	if forward:
		_mark_done()
	if ni < 0:
		_say("Das ist der Anfang der Serie.")
	elif ni >= chapters.size():
		_say("Ende – keine weiteren Kapitel.")
	else:
		_open_chapter(ni, 0 if forward else -2)


# ================================================================ Leiste am Buch

func _build_toolbar() -> void:
	toolbar = Node3D.new()
	book.add_child(toolbar)
	# Unter dem Buch, leicht zum Leser gekippt
	toolbar.position = Vector3(0, -Book.H * 0.5 - 0.055, 0.015)
	toolbar.rotation_degrees.x = -20
	var bw := 0.05
	var items := [
		["Bibl.", func(): _show_chapter_list()],
		["« Kap.", func(): _on_beyond_end(false)],
		["<", func(): book.turn(not book.rtl)],
		[">", func(): book.turn(book.rtl)],
		["Kap. »", func(): _on_beyond_end(true)],
		["–", func(): _resize_book(1.0 / 1.15)],
		["+", func(): _resize_book(1.15)],
		["Menü", func(): _toggle_menu()],
	]
	for i in items.size():
		var x := (i - (items.size() - 1) * 0.5) * (bw + 0.008)
		ui.button(toolbar, items[i][0], Vector2(bw, 0.032), Vector3(x, 0, 0), items[i][1], Color(0.12, 0.13, 0.17, 0.9), 20)
	toolbar.visible = false


func _show_chapter_list() -> void:
	_save_progress()
	book.visible = false
	toolbar.visible = false
	ch_root.visible = true
	_place_panel(ch_root)
	_fill_chapters()


func _resize_book(f: float) -> void:
	_book_scale = clampf(_book_scale * f, 0.6, 3.0)
	book.scale = Vector3.ONE * _book_scale


# ================================================================ Schnellmenü

func _build_menu() -> void:
	menu = Node3D.new()
	add_child(menu)
	ui.button(menu, "", Vector2(0.2, 0.25), Vector3.ZERO, null, Color(0.07, 0.08, 0.11, 0.9))
	var rows := [
		["lib", "Bibliothek", _menu_library],
		["here", "Buch zu mir", func(): _place_book()],
		["dir", "", _menu_dir],
		["off", "", _menu_offset],
		["pt", "", func(): set_passthrough(not passthrough)],
		["light", "", func(): _cycle_brightness()],
	]
	for i in rows.size():
		var b := ui.button(menu, rows[i][1], Vector2(0.18, 0.034), Vector3(0, 0.1 - i * 0.04, 0.003), rows[i][2], Color(0.16, 0.18, 0.25, 0.95), 18)
		menu_buttons[rows[i][0]] = b
	menu.visible = false
	_refresh_menu()


func _menu_library() -> void:
	_toggle_menu(false)
	_show_library()


func _menu_dir() -> void:
	book.set_rtl(not book.rtl)
	_refresh_menu()


func _menu_offset() -> void:
	book.set_offset(not book.offset)
	_refresh_menu()


func _refresh_menu() -> void:
	UI.set_text(menu_buttons.dir, "Richtung: " + ("rechts → links" if book.rtl else "links → rechts"))
	UI.set_text(menu_buttons.off, "Doppelseiten versetzen: " + ("an" if book.offset else "aus"))
	UI.set_text(menu_buttons.pt, "Echtes Zimmer: " + ("an" if passthrough else "aus"))
	UI.set_text(menu_buttons.light, "Helligkeit: %d %%" % roundi(book.brightness * 100))


func _cycle_brightness() -> void:
	var steps := [1.0, 0.85, 0.7, 0.55]
	var i := (steps.find(snappedf(book.brightness, 0.05)) + 1) % steps.size()
	book.set_brightness(steps[i])
	_refresh_menu()


func _toggle_menu(force = null) -> void:
	_menu_pinned = (not _menu_pinned) if force == null else bool(force)
	menu.visible = _menu_pinned
	if _menu_pinned:
		_refresh_menu()
		var h := _head_flat()
		var pos := h.origin + (-h.basis.z) * 0.45 + h.basis.x * 0.25 + Vector3(0, -0.1, 0)
		menu.global_transform = Transform3D(_facing_basis(camera.global_position - pos), pos)


## Handtracking: Linke Handfläche zum Gesicht drehen -> Menü erscheint über der Hand.
func _update_palm_menu() -> void:
	if _menu_pinned:
		return
	var l: Hands.Hand = hands.left
	var show_it: bool = l.mode == Hands.Mode.HAND and l.palm_facing_head and not l.pinching and not l.grabbing and l != _grab_hand
	if show_it:
		var pos := l.palm.origin + Vector3(0, 0.16, 0) + (camera.global_position - l.palm.origin).normalized() * 0.03
		var target := Transform3D(_facing_basis(camera.global_position - pos), pos)
		if not menu.visible:
			menu.global_transform = target
			_refresh_menu()
		else:
			menu.global_transform = menu.global_transform.interpolate_with(target, 0.3)
	menu.visible = show_it


# ================================================================ Eingabe

func _process(delta: float) -> void:
	var busy := ui.update(delta)
	_update_palm_menu()
	if book.visible:
		_update_book_grab()
		for h in hands.hands():
			if not h.tracked() or busy.has(h.side) or h == _grab_hand or _two_hand:
				continue
			if h.pinch_started:
				book.try_pinch(h)
			elif Cfg.SWIPE_TO_TURN and h.mode == Hands.Mode.HAND:
				book.try_swipe(h)
		_controller_buttons()
	if _toast_t > 0.0:
		_toast_t -= delta
		toast.modulate.a = clampf(_toast_t, 0.0, 1.0)
	_save_t += delta
	if _save_t > 10.0:
		_save_t = 0.0
		_save_progress()


## Buch greifen: Faust (oder Grip) am Buch. Mit beiden Händen: größer/kleiner ziehen.
func _update_book_grab() -> void:
	var l: Hands.Hand = hands.left
	var r: Hands.Hand = hands.right
	# Start
	for h in [l, r]:
		if h.grab_started and h.mode != Hands.Mode.MOUSE and book.can_grab(h.palm.origin if h.mode == Hands.Mode.HAND else h.pinch_pos):
			if _grab_hand == null:
				_grab_hand = h
				_grab_offset = _hand_frame(h).affine_inverse() * book.global_transform
				h.haptic(0.3, 0.05)
			elif _grab_hand != h and not _two_hand:
				_two_hand = true
				_two_d0 = maxf(_grip_point(l).distance_to(_grip_point(r)), 0.05)
				_two_s0 = _book_scale
				_two_off = _two_frame().affine_inverse() * book.global_transform
				h.haptic(0.3, 0.05)
	# Ende
	if _two_hand and (not l.grabbing or not r.grabbing):
		_two_hand = false
		var still = l if l.grabbing else (r if r.grabbing else null)
		_grab_hand = still
		if still:
			_grab_offset = _hand_frame(still).affine_inverse() * book.global_transform
	if _grab_hand != null and not _grab_hand.grabbing:
		_grab_hand = null
	# Bewegen
	if _two_hand:
		var d := _grip_point(l).distance_to(_grip_point(r))
		var s := clampf(_two_s0 * d / _two_d0, 0.6, 3.0)
		var t := _two_frame() * _two_off
		t.basis = t.basis.orthonormalized()
		book.global_transform = book.global_transform.interpolate_with(t, 0.5)
		_book_scale = s
		book.scale = Vector3.ONE * s
	elif _grab_hand != null:
		var t := _hand_frame(_grab_hand) * _grab_offset
		t.basis = t.basis.orthonormalized()
		book.global_transform = book.global_transform.interpolate_with(t, 0.45)
		book.scale = Vector3.ONE * _book_scale


func _grip_point(h) -> Vector3:
	return h.palm.origin if h.mode == Hands.Mode.HAND else h.pinch_pos


func _hand_frame(h) -> Transform3D:
	return Transform3D(h.palm.basis.orthonormalized(), _grip_point(h))


## Rahmen zwischen beiden Händen: x von links nach rechts, y nach oben.
func _two_frame() -> Transform3D:
	var a := _grip_point(hands.left)
	var b := _grip_point(hands.right)
	var x := (b - a)
	if x.length() < 0.01:
		x = Vector3.RIGHT
	x = x.normalized()
	var to_eye := camera.global_position - (a + b) * 0.5
	var z := to_eye.slide(x).normalized()
	var y := z.cross(x).normalized()
	return Transform3D(Basis(x, y, z), (a + b) * 0.5)


## Controller: Daumenstick/A/B blättern, Y öffnet das Menü.
var _stick_ready := true
func _controller_buttons() -> void:
	var r: Hands.Hand = hands.right
	var l: Hands.Hand = hands.left
	if r.mode == Hands.Mode.CONTROLLER and r.controller:
		var x := r.controller.get_vector2(&"primary").x
		if _stick_ready and absf(x) > 0.7:
			_stick_ready = false
			# Stick nach rechts = Seite, die rechts liegt, umblättern
			book.begin_flip("right" if x < 0.0 else "left")
		elif absf(x) < 0.3:
			_stick_ready = true


func _unhandled_input(event: InputEvent) -> void:
	if vr:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_LEFT:
				book.begin_flip("left")
			KEY_RIGHT:
				book.begin_flip("right")
			KEY_L:
				_show_library()
			KEY_M:
				_toggle_menu()
			KEY_R:
				_place_book()
			KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
				_resize_book(1.15)
			KEY_MINUS, KEY_KP_SUBTRACT:
				_resize_book(1.0 / 1.15)
			KEY_D:
				book.set_rtl(not book.rtl)
				_refresh_menu()
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_resize_book(1.05)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_resize_book(1.0 / 1.05)
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		camera.rotation.y -= event.relative.x * 0.004
		camera.rotation.x = clampf(camera.rotation.x - event.relative.y * 0.004, -1.3, 1.3)


func _on_page_ready(key: String) -> void:
	if book.visible:
		book.on_page_ready(key)
	if lib_root.visible:
		_fill_library()


func _on_spread_changed(first_page: int, total: int) -> void:
	if cur_chapter < 0 or cur_chapter >= chapters.size():
		return
	var id := str(chapters[cur_chapter].id)
	var p: Dictionary = progress.get(id, {})
	p["page"] = first_page
	p["total"] = total
	p["t"] = Time.get_unix_time_from_system()
	if book.at_end():
		p["done"] = true
	progress[id] = p


func _mark_done() -> void:
	if cur_chapter >= 0 and cur_chapter < chapters.size():
		var id := str(chapters[cur_chapter].id)
		var p: Dictionary = progress.get(id, {})
		p["done"] = true
		progress[id] = p
		_save_progress()


func _say(text: String) -> void:
	toast.text = text
	_toast_t = 3.0
	toast.modulate.a = 1.0
	print("[MangaVR] ", text)


# ================================================================ Fortschritt

func _load_progress() -> void:
	if FileAccess.file_exists(PROGRESS_FILE):
		var d = JSON.parse_string(FileAccess.get_file_as_string(PROGRESS_FILE))
		if d is Dictionary:
			progress = d


func _save_progress() -> void:
	var f := FileAccess.open(PROGRESS_FILE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(progress))


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		_save_progress()
