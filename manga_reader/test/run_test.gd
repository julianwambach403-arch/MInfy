extends SceneTree
## Automatischer Test im Desktop-Modus: Bibliothek -> Kapitel -> Blättern (+ Screenshots).
##   godot --path . -s res://test/run_test.gd -- --desktop

var main
var shots := OS.get_environment("SHOTS")

func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	_run()

func _wait(n: int) -> void:
	for i in n:
		await process_frame

func _shot(name: String) -> void:
	if shots == "":
		return
	await _wait(3)
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(shots.path_join(name + ".png"))
	print("shot ", name)

func check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		main.set_meta("failed", true)

func _run() -> void:
	await _wait(30)
	check(main.series.size() >= 1, "Serien gefunden: %d" % main.series.size())
	await _wait(60)
	await _shot("1_bibliothek")
	main._open_series_slot(0)
	await _wait(10)
	check(main.chapters.size() == 3, "Kapitel: %d" % main.chapters.size())
	await _shot("2_kapitel")
	main._open_chapter(0, 0)
	await _wait(120)
	var b = main.book
	check(b.visible, "Buch sichtbar")
	check(b.pages.size() == 17, "Seiten: %d" % b.pages.size())
	print("Doppelseiten: ", b.spreads)
	await _shot("3_buch")
	check(b.first_page() == 0, "Start Seite 0")
	b.turn(true)
	await _wait(8)
	await _shot("4_blaettern")
	await _wait(80)
	check(b.cur == 1, "nach Umblättern Doppelseite 1 (ist %d)" % b.cur)
	for i in 3:
		b.turn(true)
		await _wait(90)
	await _shot("5_doppelseite")
	print("cur=", b.cur, " spread=", b.spreads[b.cur])
	check(b.spreads[b.cur].wide >= 0, "Querformat-Bild als Doppelseite")
	b.turn(false)
	await _wait(90)
	check(b.cur == 3, "zurück blättern (ist %d)" % b.cur)
	# Hand-Pinch simulieren: linke Seite (RTL = weiter) greifen und nach rechts ziehen
	var H = load("res://scripts/hands.gd")
	var h = H.Hand.new()
	h.mode = H.Mode.HAND
	h.side = "right"
	h.pinch_pos = b.global_transform * Vector3(-0.15, 0, 0.01)
	h.set_pinch(true)
	check(b.try_pinch(h), "Pinch greift linke Seite")
	for i in 30:
		var a := PI * (1.0 - i / 29.0)
		h.pinch_pos = b.global_transform * Vector3(cos(a) * 0.17, 0, sin(a) * 0.17)
		await _wait(1)
		if i == 12:
			await _shot("6_hand_ziehen")
	h.set_pinch(false)
	await _wait(60)
	check(b.cur == 4, "Hand-Umblättern -> Doppelseite 4 (ist %d)" % b.cur)
	# Bis ans Ende -> nächstes Kapitel
	for i in 6:
		b.turn(true)
		await _wait(45)
	await _wait(60)
	check(main.cur_chapter == 1, "automatisch nächstes Kapitel (ist %d)" % main.cur_chapter)
	main._toggle_menu(true)
	await _wait(5)
	await _shot("7_menue")
	main._save_progress()
	check(FileAccess.file_exists("user://fortschritt.json"), "Fortschritt gespeichert")
	print("FERTIG", " MIT FEHLERN" if main.has_meta("failed") else " ohne Fehler")
	quit(1 if main.has_meta("failed") else 0)
