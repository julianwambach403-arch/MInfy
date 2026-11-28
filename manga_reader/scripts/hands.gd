extends Node3D
## Einheitliche Eingabe für beide Hände:
##   - Handtracking der Quest 3 (OpenXR XR_EXT_hand_tracking): Pinch = Daumen + Zeigefinger,
##     Greifen = Faust (Mittel-, Ring- und kleiner Finger eingerollt), Zeigefinger zum Antippen.
##   - Controller (Trigger = Pinch, Grip = Greifen), falls die Hände gerade nicht erkannt werden.
##   - Maus am PC (Linksklick = Pinch) zum Testen ohne Brille.
## Alle Positionen in Weltkoordinaten.

enum Mode { NONE, HAND, CONTROLLER, MOUSE }

const PINCH_ON := 0.018
const PINCH_OFF := 0.035
const GRAB_ON := 0.075
const GRAB_OFF := 0.095


class Hand:
	var side := "left"
	var mode := Mode.NONE
	var palm := Transform3D()       # Handfläche (−Y zeigt aus der Handfläche heraus)
	var pinch_pos := Vector3.ZERO   # Punkt zwischen Daumen und Zeigefinger
	var tip_pos := Vector3.ZERO     # Zeigefingerspitze (zum Antippen)
	var aim_from := Vector3.ZERO
	var aim_dir := Vector3.FORWARD
	var pinching := false
	var pinch_started := false
	var pinch_ended := false
	var grabbing := false
	var grab_started := false
	var grab_ended := false
	var vel := Vector3.ZERO         # geglättete Geschwindigkeit der Hand
	var palm_facing_head := false
	var joints: PackedVector3Array = PackedVector3Array()
	var controller: XRController3D
	var _last_pos := Vector3.ZERO
	var _has_last := false

	func tracked() -> bool:
		return mode != Mode.NONE

	func set_pinch(v: bool) -> void:
		pinch_started = v and not pinching
		pinch_ended = pinching and not v
		pinching = v

	func set_grab(v: bool) -> void:
		grab_started = v and not grabbing
		grab_ended = grabbing and not v
		grabbing = v

	func update_velocity(p: Vector3, delta: float) -> void:
		if _has_last and delta > 0.0:
			vel = vel.lerp((p - _last_pos) / delta, clampf(delta * 18.0, 0.0, 1.0))
		_last_pos = p
		_has_last = true

	func haptic(amp: float, dur: float) -> void:
		if mode == Mode.CONTROLLER and controller:
			controller.trigger_haptic_pulse(&"haptic", 0.0, amp, dur, 0.0)


var left := Hand.new()
var right := Hand.new()
var vr := false
var origin: XROrigin3D
var camera: Camera3D
## Am PC: Funktion, die für einen Mausstrahl (from, dir) einen Punkt liefert (z. B. auf dem Buch).
var mouse_surface: Callable

var _vis := {}


func setup(p_origin: XROrigin3D, p_camera: Camera3D, p_vr: bool) -> void:
	origin = p_origin
	camera = p_camera
	vr = p_vr
	left.side = "left"
	right.side = "right"
	if vr:
		for h in [left, right]:
			var c := XRController3D.new()
			c.tracker = &"left_hand" if h.side == "left" else &"right_hand"
			c.pose = &"aim"
			origin.add_child(c)
			h.controller = c
	for h in [left, right]:
		_vis[h.side] = _make_visual(h.side)


func hands() -> Array:
	return [left, right]


func other(h: Hand) -> Hand:
	return right if h == left else left


func _process(delta: float) -> void:
	if vr:
		for h in [left, right]:
			if not _update_hand_tracking(h):
				_update_controller(h)
			if h.tracked():
				h.update_velocity(h.pinch_pos, delta)
	else:
		_update_mouse(right, delta)
		left.mode = Mode.NONE
	for h in [left, right]:
		_update_visual(h)


# ---------------------------------------------------------------- Handtracking

func _update_hand_tracking(h: Hand) -> bool:
	var tr := XRServer.get_tracker(&"/user/hand_tracker/left" if h.side == "left" else &"/user/hand_tracker/right") as XRHandTracker
	if tr == null or not tr.has_tracking_data:
		return false
	if tr.hand_tracking_source == XRHandTracker.HAND_TRACKING_SOURCE_CONTROLLER:
		return false  # Hand wird nur aus dem Controller geschätzt -> Controller-Modus
	var ot := origin.global_transform
	var flags := tr.get_hand_joint_flags(XRHandTracker.HAND_JOINT_PALM)
	if not (flags & XRHandTracker.HAND_JOINT_FLAG_POSITION_TRACKED):
		return false
	h.mode = Mode.HAND
	if h.joints.size() != XRHandTracker.HAND_JOINT_MAX:
		h.joints.resize(XRHandTracker.HAND_JOINT_MAX)
	for j in XRHandTracker.HAND_JOINT_MAX:
		h.joints[j] = ot * tr.get_hand_joint_transform(j).origin
	h.palm = ot * tr.get_hand_joint_transform(XRHandTracker.HAND_JOINT_PALM)
	var thumb: Vector3 = h.joints[XRHandTracker.HAND_JOINT_THUMB_TIP]
	var index: Vector3 = h.joints[XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP]
	h.tip_pos = index
	h.pinch_pos = (thumb + index) * 0.5
	var pd := thumb.distance_to(index)
	# Faust: Mittel-, Ring- und kleiner Finger nah an der Handfläche
	var curl := 0.0
	for j in [XRHandTracker.HAND_JOINT_MIDDLE_FINGER_TIP, XRHandTracker.HAND_JOINT_RING_FINGER_TIP, XRHandTracker.HAND_JOINT_PINKY_FINGER_TIP]:
		curl += h.joints[j].distance_to(h.palm.origin)
	curl /= 3.0
	var to_head := (camera.global_position - h.palm.origin).normalized()
	h.palm_facing_head = (-h.palm.basis.y).normalized().dot(to_head) > 0.55
	var grab := curl < GRAB_ON if not h.grabbing else curl < GRAB_OFF
	h.set_grab(grab)
	var pinch := pd < PINCH_ON if not h.pinching else pd < PINCH_OFF
	if h.grabbing:
		pinch = false
	# Meta-Systemgeste (Handfläche zum Gesicht + Pinch) nicht als Klick werten
	if h.palm_facing_head and not h.pinching and h.side == "left":
		pinch = false
	h.set_pinch(pinch)
	# Zeigestrahl wie im Quest-Menü: von der Schulter durch die Hand
	var head := camera.global_transform
	var shoulder := head.origin + Vector3(0, -0.17, 0) + head.basis.x.slide(Vector3.UP).normalized() * (0.17 if h.side == "right" else -0.17)
	h.aim_from = h.pinch_pos
	h.aim_dir = (h.pinch_pos - shoulder).normalized()
	return true


# ---------------------------------------------------------------- Controller

func _update_controller(h: Hand) -> void:
	var c := h.controller
	if c == null or not c.get_has_tracking_data():
		h.mode = Mode.NONE
		h.set_pinch(false)
		h.set_grab(false)
		return
	h.mode = Mode.CONTROLLER
	var t := c.global_transform
	h.palm = t
	h.aim_from = t.origin
	h.aim_dir = -t.basis.z
	h.pinch_pos = t.origin - t.basis.z * 0.04
	h.tip_pos = t.origin - t.basis.z * 0.06
	h.palm_facing_head = false
	var trig := c.get_float(&"trigger")
	var grip := c.get_float(&"grip")
	h.set_pinch(trig > 0.6 if not h.pinching else trig > 0.35)
	h.set_grab(grip > 0.6 if not h.grabbing else grip > 0.35)
	h.joints = PackedVector3Array()


# ---------------------------------------------------------------- Maus (PC)

func _update_mouse(h: Hand, delta: float) -> void:
	h.mode = Mode.MOUSE
	var vp := get_viewport()
	var mp := vp.get_mouse_position()
	h.aim_from = camera.project_ray_origin(mp)
	h.aim_dir = camera.project_ray_normal(mp)
	var p := h.aim_from + h.aim_dir * 0.5
	if mouse_surface.is_valid():
		var hit = mouse_surface.call(h.aim_from, h.aim_dir)
		if hit is Vector3:
			p = hit
	h.pinch_pos = p
	h.tip_pos = p
	h.palm = Transform3D(camera.global_basis, p)
	h.update_velocity(p, delta)
	h.set_pinch(Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT))
	h.set_grab(Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT))


# ---------------------------------------------------------------- Darstellung

func _make_visual(side: String) -> Dictionary:
	var root := Node3D.new()
	add_child(root)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.9, 1.0, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var tip_mat := mat.duplicate() as StandardMaterial3D
	tip_mat.albedo_color = Color(1.0, 0.75, 0.35, 0.9)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var sph := SphereMesh.new()
	sph.radius = 0.006
	sph.height = 0.012
	sph.radial_segments = 8
	sph.rings = 4
	mm.mesh = sph
	mm.instance_count = XRHandTracker.HAND_JOINT_MAX
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mmi)
	# Controller-Ersatz: kleiner Griff
	var ctrl := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.035, 0.03, 0.09)
	ctrl.mesh = box
	ctrl.material_override = mat
	root.add_child(ctrl)
	# Cursor (Pinch-Punkt)
	var dot := MeshInstance3D.new()
	var ds := SphereMesh.new()
	ds.radius = 0.005
	ds.height = 0.01
	dot.mesh = ds
	dot.material_override = tip_mat
	root.add_child(dot)
	# Zeigestrahl (wird von ui3d.gd ein- und ausgeschaltet)
	var ray := MeshInstance3D.new()
	var rb := BoxMesh.new()
	rb.size = Vector3(0.002, 0.002, 1.0)
	ray.mesh = rb
	var rmat := mat.duplicate() as StandardMaterial3D
	rmat.albedo_color = Color(0.7, 0.85, 1.0, 0.45)
	ray.material_override = rmat
	ray.visible = false
	add_child(ray)
	var cursor := MeshInstance3D.new()
	var cs := SphereMesh.new()
	cs.radius = 0.006
	cs.height = 0.012
	cursor.mesh = cs
	cursor.material_override = tip_mat
	cursor.visible = false
	add_child(cursor)
	return {"root": root, "mm": mm, "mmi": mmi, "ctrl": ctrl, "dot": dot, "ray": ray, "cursor": cursor, "tip_mat": tip_mat}


func _update_visual(h: Hand) -> void:
	var v: Dictionary = _vis[h.side]
	var root: Node3D = v.root
	root.visible = h.mode == Mode.HAND or h.mode == Mode.CONTROLLER
	if not root.visible:
		return
	var mmi: MultiMeshInstance3D = v.mmi
	var ctrl: MeshInstance3D = v.ctrl
	mmi.visible = h.mode == Mode.HAND
	ctrl.visible = h.mode == Mode.CONTROLLER
	if h.mode == Mode.HAND:
		var mm: MultiMesh = v.mm
		for j in h.joints.size():
			var s := 1.4 if j in [XRHandTracker.HAND_JOINT_THUMB_TIP, XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP] else 1.0
			mm.set_instance_transform(j, Transform3D(Basis().scaled(Vector3.ONE * s), h.joints[j]))
	else:
		ctrl.global_transform = h.palm
	var dot: MeshInstance3D = v.dot
	dot.global_position = h.pinch_pos
	(v.tip_mat as StandardMaterial3D).albedo_color = Color(1.0, 0.55, 0.2, 1.0) if h.pinching else Color(1.0, 0.85, 0.5, 0.8)


## Zeigestrahl bis zum Punkt `hit` anzeigen (oder ausblenden, wenn hit == null).
func show_ray(h: Hand, hit) -> void:
	var v: Dictionary = _vis[h.side]
	var ray: MeshInstance3D = v.ray
	var cursor: MeshInstance3D = v.cursor
	var on: bool = hit is Vector3 and (h.mode == Mode.HAND or h.mode == Mode.CONTROLLER)
	ray.visible = on
	cursor.visible = on
	if not on:
		return
	var a := h.aim_from
	var b: Vector3 = hit
	var dist := a.distance_to(b)
	if dist < 0.01:
		ray.visible = false
		return
	var t := Transform3D().looking_at(b - a, Vector3.UP if absf((b - a).normalized().y) < 0.99 else Vector3.RIGHT)
	t.origin = (a + b) * 0.5
	t.basis = t.basis * Basis.from_scale(Vector3(1, 1, dist))
	ray.global_transform = t
	cursor.global_position = b
