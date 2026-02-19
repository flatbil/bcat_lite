# camera_controller.gd
# Google-Maps-style controls.
#   Desktop : scroll-wheel zoom  |  right/middle-drag pan
#   Mobile  : 1-finger drag pan  |  2-finger pinch zoom + 2-finger drag pan
# Attach to the Camera3D node in Main.tscn.
extends Camera3D

const MIN_HEIGHT   := 3.0    # closest zoom (metres above floor)
const MAX_HEIGHT   := 60.0   # farthest zoom
const ZOOM_STEP    := 1.18   # multiplier per scroll tick (desktop)
const PAN_SENS     := 0.002  # metres per pixel per metre of camera height

# ── Desktop state ─────────────────────────────────────────────────────────────

var _panning          := false
var _pan_origin_mouse := Vector2.ZERO
var _pan_origin_cam   := Vector3.ZERO

# ── Touch state ───────────────────────────────────────────────────────────────

var _touches:      Dictionary = {}   # finger_index -> current  screen Vector2
var _prev_touches: Dictionary = {}   # finger_index -> previous screen Vector2

# ── Input dispatcher ──────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:

	# ── Touch down / up ────────────────────────────────────────────────────────
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index]      = event.position
			_prev_touches[event.index] = event.position
		else:
			_touches.erase(event.index)
			_prev_touches.erase(event.index)
		get_viewport().set_input_as_handled()
		return

	# ── Touch move ─────────────────────────────────────────────────────────────
	if event is InputEventScreenDrag:
		_prev_touches[event.index] = _touches.get(event.index, event.position)
		_touches[event.index]      = event.position
		_handle_touch_gesture()
		get_viewport().set_input_as_handled()
		return

	# ── Mouse wheel (desktop zoom) ─────────────────────────────────────────────
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_zoom_stepped(-1)
				get_viewport().set_input_as_handled()
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_stepped(1)
				get_viewport().set_input_as_handled()
			MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT:
				_panning = event.pressed
				if event.pressed:
					_pan_origin_mouse = event.position
					_pan_origin_cam   = global_position
				get_viewport().set_input_as_handled()
		return

	# ── Mouse drag (desktop pan) ───────────────────────────────────────────────
	if event is InputEventMouseMotion and _panning:
		_pan_from_origin(event.position - _pan_origin_mouse)
		get_viewport().set_input_as_handled()

# ── Touch gesture handler ─────────────────────────────────────────────────────

func _handle_touch_gesture() -> void:
	var count := _touches.size()
	if count < 1:
		return

	var keys := _touches.keys()

	if count == 1:
		# ── Single-finger pan ─────────────────────────────────────────────────
		var idx: int = keys[0]
		var delta: Vector2 = _touches[idx] - _prev_touches.get(idx, _touches[idx])
		_pan_delta(delta)

	else:
		# ── Two-finger pinch-zoom + centroid pan ──────────────────────────────
		var a_cur: Vector2 = _touches[keys[0]]
		var b_cur: Vector2 = _touches[keys[1]]
		var a_prv: Vector2 = _prev_touches.get(keys[0], a_cur)
		var b_prv: Vector2 = _prev_touches.get(keys[1], b_cur)

		# Pinch: ratio of old span to new span  (>1 = zoom out, <1 = zoom in)
		var dist_cur := a_cur.distance_to(b_cur)
		var dist_prv := a_prv.distance_to(b_prv)
		if dist_prv > 4.0 and dist_cur > 4.0:
			_zoom_by_factor(dist_prv / dist_cur)

		# Centroid drag: move both fingers together = pan
		var centroid_delta := ((a_cur + b_cur) - (a_prv + b_prv)) * 0.5
		_pan_delta(centroid_delta)

# ── Zoom ──────────────────────────────────────────────────────────────────────

func _zoom_stepped(direction: int) -> void:
	_zoom_by_factor(pow(ZOOM_STEP, direction))

# Scale the camera's distance from the floor-intersection point.
# factor < 1.0 → move closer; factor > 1.0 → move farther.
func _zoom_by_factor(factor: float) -> void:
	var fwd := -global_transform.basis.z.normalized()
	if absf(fwd.y) < 0.01:
		return
	# Floor (Y=0) intersection along the camera's forward ray
	var t        := -global_position.y / fwd.y
	var floor_pt := global_position + fwd * t
	var new_pos  := floor_pt + (global_position - floor_pt) * factor
	if new_pos.y >= MIN_HEIGHT and new_pos.y <= MAX_HEIGHT:
		global_position = new_pos

# ── Pan ───────────────────────────────────────────────────────────────────────

# Origin-anchored pan (desktop right/middle drag) — no drift on release.
func _pan_from_origin(delta: Vector2) -> void:
	var right   := global_transform.basis.x
	var fwd_xz  := _flat_forward()
	var scale   := _pan_origin_cam.y * PAN_SENS
	global_position = _pan_origin_cam \
		- right  * delta.x * scale \
		+ fwd_xz * delta.y * scale

# Incremental pan applied each drag event (touch).
func _pan_delta(delta: Vector2) -> void:
	var right   := global_transform.basis.x
	var fwd_xz  := _flat_forward()
	var scale   := global_position.y * PAN_SENS
	global_position -= right  * delta.x * scale
	global_position += fwd_xz * delta.y * scale

# Camera's forward direction projected onto the XZ plane.
func _flat_forward() -> Vector3:
	return Vector3(
		-global_transform.basis.z.x,
		0.0,
		-global_transform.basis.z.z
	).normalized()
