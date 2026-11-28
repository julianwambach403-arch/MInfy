extends RefCounted
## Liest Manga von einem eigenen Komga-Server (https://komga.org) über dessen REST-API.
## Komga ist kostenlos, läuft auf PC/NAS/Raspberry Pi und verwaltet deine eigenen CBZ-Dateien.

var name := "Komga-Server"
var base := ""
var auth_header := ""
var host: Node  # Elternknoten für die HTTPRequest-Knoten


func _init(p_host: Node, url: String, user: String, password: String) -> void:
	host = p_host
	base = url.strip_edges().trim_suffix("/")
	if user != "":
		auth_header = "Authorization: Basic " + Marshalls.utf8_to_base64(user + ":" + password)


func is_threaded() -> bool:
	return false


func _http(path: String, cb: Callable, raw := false) -> void:
	var req := HTTPRequest.new()
	req.timeout = 20.0
	host.add_child(req)
	req.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, body: PackedByteArray):
		req.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
			push_warning("Komga: Fehler %d/%d bei %s" % [result, code, path])
			cb.call(null)
			return
		if raw:
			cb.call(body)
		else:
			cb.call(JSON.parse_string(body.get_string_from_utf8())))
	var headers := PackedStringArray(["Accept: application/json, image/*"])
	if auth_header != "":
		headers.append(auth_header)
	if req.request(base + path, headers) != OK:
		req.queue_free()
		cb.call(null)


func list_series(cb: Callable) -> void:
	_http("/api/v1/series?size=1000&sort=metadata.titleSort,asc", func(data):
		var out: Array = []
		if data is Dictionary:
			for s in data.get("content", []):
				out.append({"id": s.id, "title": s.get("metadata", {}).get("title", s.get("name", "?")),
					"source": self, "count": int(s.get("booksCount", 0)),
					"cover": {"kind": "url", "path": "/api/v1/series/%s/thumbnail" % s.id}})
		cb.call(out))


func list_chapters(series: Dictionary, cb: Callable) -> void:
	_http("/api/v1/series/%s/books?size=2000&sort=metadata.numberSort,asc" % series.id, func(data):
		var out: Array = []
		if data is Dictionary:
			for b in data.get("content", []):
				out.append({"id": b.id, "title": b.get("metadata", {}).get("title", b.get("name", "?")),
					"pages": int(b.get("media", {}).get("pagesCount", 0))})
		cb.call(out))


func list_pages(chapter: Dictionary, cb: Callable) -> void:
	_http("/api/v1/books/%s/pages" % chapter.id, func(data):
		var out: Array = []
		if data is Array:
			for p in data:
				out.append({"kind": "url", "path": "/api/v1/books/%s/pages/%d" % [chapter.id, int(p.number)]})
		cb.call(out))


## Lädt die Bytes asynchron (Hauptthread), cb(bytes oder null).
func fetch_bytes(ref: Dictionary, cb: Callable) -> void:
	_http(ref.path, cb, true)
