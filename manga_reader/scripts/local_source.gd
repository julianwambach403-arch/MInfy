extends RefCounted
## Liest Manga aus lokalen Ordnern: .cbz/.zip-Archive und Ordner mit Bildern.
## Alle Methoden, die Bytes liefern, sind thread-sicher (jeder Aufruf öffnet sein eigenes Archiv).

const IMG_EXT := ["jpg", "jpeg", "png", "webp", "bmp"]
const ARC_EXT := ["cbz", "zip"]

var name := "Auf dem Gerät"
var dirs: Array = []


func _init(p_dirs: Array) -> void:
	for d in p_dirs:
		var p := str(d)
		if p.begins_with("~/"):
			var home := OS.get_environment("HOME")
			if home == "":
				home = OS.get_environment("USERPROFILE")
			if home == "":
				continue
			p = home.path_join(p.substr(2))
		elif p.begins_with("user://"):
			DirAccess.make_dir_recursive_absolute(p)
			p = ProjectSettings.globalize_path(p)
		dirs.append(p)


static func natural_less(a: String, b: String) -> bool:
	return a.naturalnocasecmp_to(b) < 0


static func is_image(f: String) -> bool:
	return f.get_extension().to_lower() in IMG_EXT


static func is_archive(f: String) -> bool:
	return f.get_extension().to_lower() in ARC_EXT


static func _pretty(n: String) -> String:
	return n.get_basename().replace("_", " ").strip_edges() if n.get_extension().to_lower() in ARC_EXT else n.replace("_", " ")


## Liefert alle Serien: [{id, title, cover:{kind,path,entry}, source}]
func list_series(cb: Callable) -> void:
	var out: Array = []
	for root in dirs:
		if not DirAccess.dir_exists_absolute(root):
			continue
		var subdirs := Array(DirAccess.get_directories_at(root))
		subdirs.sort_custom(natural_less)
		for sd in subdirs:
			var path: String = root.path_join(sd)
			var chapters := _chapters_in(path)
			if chapters.is_empty():
				continue
			out.append({"id": path, "title": _pretty(sd), "source": self,
				"cover": _first_page_ref(chapters[0]), "count": chapters.size()})
		var files := Array(DirAccess.get_files_at(root))
		files.sort_custom(natural_less)
		for f in files:
			if is_archive(f):
				var path: String = root.path_join(f)
				var ch := {"id": path, "title": _pretty(f), "kind": "zip"}
				out.append({"id": path, "title": _pretty(f), "source": self,
					"cover": _first_page_ref(ch), "count": 1, "single": ch})
	cb.call(out)


func list_chapters(series: Dictionary, cb: Callable) -> void:
	if series.has("single"):
		cb.call([series.single])
	else:
		cb.call(_chapters_in(series.id))


## Kapitel einer Serie: Archive und Bilder-Unterordner. Liegen die Bilder direkt
## im Serienordner, ist der Ordner selbst ein Kapitel.
func _chapters_in(path: String) -> Array:
	var out: Array = []
	var files := Array(DirAccess.get_files_at(path))
	files.sort_custom(natural_less)
	var loose_images := false
	for f in files:
		if is_archive(f):
			out.append({"id": path.path_join(f), "title": _pretty(f), "kind": "zip"})
		elif is_image(f):
			loose_images = true
	var subdirs := Array(DirAccess.get_directories_at(path))
	subdirs.sort_custom(natural_less)
	for sd in subdirs:
		var p: String = path.path_join(sd)
		for f in DirAccess.get_files_at(p):
			if is_image(f):
				out.append({"id": p, "title": _pretty(sd), "kind": "dir"})
				break
	if loose_images:
		out.push_front({"id": path, "title": path.get_file().replace("_", " "), "kind": "dir"})
	out.sort_custom(func(a, b): return natural_less(a.title, b.title))
	return out


func _first_page_ref(ch: Dictionary) -> Dictionary:
	var pages := page_list_sync(ch)
	return pages[0] if not pages.is_empty() else {}


## Seitenliste eines Kapitels (sortiert).
func list_pages(chapter: Dictionary, cb: Callable) -> void:
	cb.call(page_list_sync(chapter))


func page_list_sync(chapter: Dictionary) -> Array:
	var out: Array = []
	if chapter.get("kind", "") == "zip":
		var zr := ZIPReader.new()
		if zr.open(chapter.id) != OK:
			push_warning("Archiv kann nicht geöffnet werden: " + str(chapter.id))
			return out
		var names: Array = []
		for f in zr.get_files():
			if is_image(f) and not f.get_file().begins_with(".") and not f.contains("__MACOSX"):
				names.append(f)
		zr.close()
		names.sort_custom(natural_less)
		for n in names:
			out.append({"kind": "zip", "path": chapter.id, "entry": n})
	else:
		var names := Array(DirAccess.get_files_at(chapter.id))
		names.sort_custom(natural_less)
		for n in names:
			if is_image(n):
				out.append({"kind": "file", "path": str(chapter.id).path_join(n)})
	return out


## Thread-sicher: Rohdaten einer Seite.
func read_bytes(ref: Dictionary) -> PackedByteArray:
	if ref.is_empty():
		return PackedByteArray()
	if ref.kind == "zip":
		var zr := ZIPReader.new()
		if zr.open(ref.path) != OK:
			return PackedByteArray()
		var b := zr.read_file(ref.entry)
		zr.close()
		return b
	return FileAccess.get_file_as_bytes(ref.path)


## Lokal geht alles im Hintergrund-Thread (siehe page_cache.gd).
func is_threaded() -> bool:
	return true
