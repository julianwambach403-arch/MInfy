extends Node3D
## Zeichnet Zauberzeichen als leuchtende Spur in die Luft und sammelt den Strich
## für die Erkennung (glyphs.gd).
## VR: Punkte kommen von der linken Hand. PC: Mausbewegung auf einer Ebene vor der Kamera.

const G = preload("res://scripts/glyphs.gd")

const MAX_PTS := 400
const MIN_STEP := 0.008

var client
var drawing := false
var pts2d := PackedVector2Array()
var last3d := Vector3.ZERO
var count := 0
var plane_origin := Vector3.ZERO
var plane_right := Vector3.RIGHT
var plane_up := Vector3.UP
var mouse_pos := Vector2.ZERO
var mm: MultiMesh
var mat: StandardMaterial3D
var fade := 0.0
var color := Color(1.0, 0.85, 0.5)


func _ready() -> void:
	top_level = true
	mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var bm := SphereMesh.new()
	bm.radius = 0.009
	bm.height = 0.018
	bm.radial_segments = 6
	bm.rings = 3
	mm.mesh = bm
	mm.instance_count = MAX_PTS
	mm.visible_instance_count = 0
	mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func start(at: Vector3) -> void:
	drawing = true
	pts2d.clear()
	count = 0
	fade = 0.0
	mm.visible_instance_count = 0
	var cam: Camera3D = client.camera
	plane_right = cam.global_basis.x.normalized()
	plane_up = cam.global_basis.y.normalized()
	plane_origin = at
	mouse_pos = Vector2.ZERO
	color = Color(1.0, 0.85, 0.5)
	mat.albedo_color = color
	add_point(at)


func add_point(p: Vector3) -> void:
	if not drawing:
		return
	if count > 0 and p.distance_to(last3d) < MIN_STEP:
		return
	last3d = p
	var rel := p - plane_origin
	pts2d.append(Vector2(rel.dot(plane_right), rel.dot(plane_up)))
	if count < MAX_PTS:
		mm.set_instance_transform(count, Transform3D(Basis.IDENTITY, p))
		count += 1
		mm.visible_instance_count = count


## PC: Mausbewegung (Pixel) auf die Zeichenebene übertragen
func add_mouse(rel: Vector2) -> void:
	mouse_pos += Vector2(rel.x, -rel.y) * 0.0009
	add_point(plane_origin + plane_right * mouse_pos.x + plane_up * mouse_pos.y)


func stroke_length() -> float:
	return G.path_length(pts2d)


## Strich beenden und erkennen. allowed = Liste erlaubter Zeichen.
func finish(allowed: Array) -> Dictionary:
	drawing = false
	var res := G.recognize(pts2d, allowed)
	res["length"] = stroke_length()
	return res


## Spur aufleuchten lassen (Farbe des Zaubers) und ausblenden
func flash(c: Color) -> void:
	color = c
	mat.albedo_color = c
	fade = 1.0


func cancel() -> void:
	drawing = false
	mm.visible_instance_count = 0
	fade = 0.0


func _process(delta: float) -> void:
	if drawing:
		# sanftes Pulsieren während des Zeichnens
		mat.albedo_color = color.lerp(Color.WHITE, 0.3 + 0.3 * sin(Time.get_ticks_msec() * 0.01))
	elif fade > 0.0:
		fade -= delta * 1.4
		var c := color
		c.a = clampf(fade, 0.0, 1.0)
		mat.albedo_color = c
		if fade <= 0.0:
			mm.visible_instance_count = 0
