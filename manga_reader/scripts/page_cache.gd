extends Node
## Lädt Seitenbilder im Hintergrund (WorkerThreadPool), damit das Bild in VR nie ruckelt.
## Bilder werden dekodiert, auf MAX_PAGE_HEIGHT verkleinert und mit Mipmaps versehen
## (scharfe Schrift ohne Flimmern), dann im Hauptthread zur Textur gemacht.

signal page_ready(key: String)

const Cfg = preload("res://scripts/config.gd")
const MAX_TEXTURES := 28

var _mutex := Mutex.new()
var _done: Array = []         # [key, Image] aus den Threads
var _pending := {}            # key -> true
var _tex := {}                # key -> ImageTexture
var _aspect := {}             # key -> Breite/Höhe
var _order: Array = []        # LRU
var _tasks: Array = []


static func key_of(ref: Dictionary) -> String:
	return "%s|%s|%s" % [ref.get("kind", ""), ref.get("path", ""), ref.get("entry", "")]


func get_texture(ref: Dictionary) -> Texture2D:
	var k := key_of(ref)
	if _tex.has(k):
		_order.erase(k)
		_order.append(k)
		return _tex[k]
	return null


func get_aspect(ref: Dictionary) -> float:
	return _aspect.get(key_of(ref), 0.0)


func has_page(ref: Dictionary) -> bool:
	return _tex.has(key_of(ref))


## Fordert eine Seite an (doppelte Anfragen werden ignoriert).
func request(source, ref: Dictionary, max_h := Cfg.MAX_PAGE_HEIGHT) -> void:
	if ref.is_empty():
		return
	var k := key_of(ref)
	if _tex.has(k) or _pending.has(k):
		return
	_pending[k] = true
	if source.is_threaded():
		_tasks.append(WorkerThreadPool.add_task(_work_local.bind(source, ref, k, max_h), false, "Seite laden"))
	else:
		source.fetch_bytes(ref, func(bytes):
			if bytes == null:
				_pending.erase(k)
				return
			_tasks.append(WorkerThreadPool.add_task(_work_decode.bind(bytes, k, max_h), false, "Seite dekodieren")))


func _work_local(source, ref: Dictionary, k: String, max_h: int) -> void:
	_work_decode(source.read_bytes(ref), k, max_h)


func _work_decode(bytes: PackedByteArray, k: String, max_h: int) -> void:
	var img := decode(bytes, max_h)
	_mutex.lock()
	_done.append([k, img])
	_mutex.unlock()


## Erkennt das Format an den ersten Bytes (Dateiendungen lügen manchmal).
static func decode(bytes: PackedByteArray, max_h: int) -> Image:
	if bytes.size() < 12:
		return null
	var img := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	if bytes[0] == 0xFF and bytes[1] == 0xD8:
		err = img.load_jpg_from_buffer(bytes)
	elif bytes[0] == 0x89 and bytes[1] == 0x50:
		err = img.load_png_from_buffer(bytes)
	elif bytes[0] == 0x52 and bytes[1] == 0x49 and bytes[8] == 0x57:
		err = img.load_webp_from_buffer(bytes)
	elif bytes[0] == 0x42 and bytes[1] == 0x4D:
		err = img.load_bmp_from_buffer(bytes)
	if err != OK or img.is_empty():
		return null
	if img.get_height() > max_h:
		var w := int(round(img.get_width() * float(max_h) / img.get_height()))
		img.resize(maxi(w, 1), max_h, Image.INTERPOLATE_LANCZOS)
	if img.get_format() != Image.FORMAT_RGB8 and img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	img.generate_mipmaps()
	return img


func _process(_delta: float) -> void:
	for i in range(_tasks.size() - 1, -1, -1):
		if WorkerThreadPool.is_task_completed(_tasks[i]):
			WorkerThreadPool.wait_for_task_completion(_tasks[i])
			_tasks.remove_at(i)
	_mutex.lock()
	var batch := _done
	_done = []
	_mutex.unlock()
	var t0 := Time.get_ticks_msec()
	for idx in batch.size():
		var item: Array = batch[idx]
		# Höchstens ~4 ms pro Frame für Uploads, Rest im nächsten Frame.
		if Time.get_ticks_msec() - t0 > 4:
			_mutex.lock()
			_done = batch.slice(idx) + _done
			_mutex.unlock()
			break
		var k: String = item[0]
		_pending.erase(k)
		var img: Image = item[1]
		if img == null:
			img = Image.create(8, 12, false, Image.FORMAT_RGB8)
			img.fill(Color(0.9, 0.85, 0.85))
		_tex[k] = ImageTexture.create_from_image(img)
		_aspect[k] = float(img.get_width()) / img.get_height()
		_order.append(k)
		while _order.size() > MAX_TEXTURES:
			var old: String = _order.pop_front()
			_tex.erase(old)
		page_ready.emit(k)


## Nur Seiten behalten, die gerade gebraucht werden (aufräumen beim Kapitelwechsel).
func keep_only(refs: Array) -> void:
	var keep := {}
	for r in refs:
		keep[key_of(r)] = true
	for k in _tex.keys():
		if not keep.has(k):
			_tex.erase(k)
			_order.erase(k)


func _exit_tree() -> void:
	for t in _tasks:
		WorkerThreadPool.wait_for_task_completion(t)
