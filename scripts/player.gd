# player.gd
# Represents the operator walking through the building.
# Keyboard : WASD / arrow keys  (world-axis; matches the top-down camera view)
# Mobile   : joy_dir set each frame by the UI virtual joystick
# sensor_mode: when true, WASD is suppressed (sensor drives position via main.gd)
extends Node3D

signal moved(pos: Vector3)

const SPEED := 15.0  # metres per second (factory is ~160 m wide)

var joy_dir     := Vector2.ZERO   # fed by UI joystick each frame
var sensor_mode := false          # when true, skip WASD input
var _last_emit  := Vector3.ZERO

func _ready() -> void:
	_build_visual()

func _build_visual() -> void:
	var teal  := Color(0.0,  0.737, 0.831)  # #00bcd4
	var teal2 := Color(0.0,  0.40,  0.60)   # darker emission

	# Pin stem — thin cylinder from ground up to the head
	var stem_mi  := MeshInstance3D.new()
	var stem_cyl := CylinderMesh.new()
	stem_cyl.height        = 1.0
	stem_cyl.top_radius    = 0.07
	stem_cyl.bottom_radius = 0.07
	stem_mi.mesh = stem_cyl
	stem_mi.material_override = _pin_mat(teal, teal2)
	stem_mi.position = Vector3(0, 0.5, 0)
	add_child(stem_mi)

	# Pin head — sphere sitting on top of the stem
	var head_mi     := MeshInstance3D.new()
	var head_sphere := SphereMesh.new()
	head_sphere.radius = 0.38
	head_sphere.height = 0.76
	head_mi.mesh = head_sphere
	head_mi.material_override = _pin_mat(teal, teal2)
	head_mi.position = Vector3(0, 1.28, 0)
	add_child(head_mi)

	# Ground shadow disk
	var shd_mi  := MeshInstance3D.new()
	var shd_cyl := CylinderMesh.new()
	shd_cyl.height        = 0.04
	shd_cyl.top_radius    = 0.28
	shd_cyl.bottom_radius = 0.28
	shd_mi.mesh = shd_cyl
	var shd_mat := StandardMaterial3D.new()
	shd_mat.albedo_color = Color(0, 0, 0, 0.35)
	shd_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shd_mi.material_override = shd_mat
	shd_mi.position = Vector3(0, 0.02, 0)
	add_child(shd_mi)

	# Billboard "YOU" label
	var lbl       := Label3D.new()
	lbl.text       = "YOU"
	lbl.font_size  = 36
	lbl.pixel_size = 0.0025
	lbl.billboard  = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.modulate   = Color(1.0, 1.0, 1.0)
	lbl.position   = Vector3(0, 2.1, 0)
	add_child(lbl)


func _pin_mat(col: Color, emit: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color               = col
	mat.emission_enabled           = true
	mat.emission                   = emit
	mat.emission_energy_multiplier = 1.2
	var ghost := StandardMaterial3D.new()
	ghost.albedo_color               = Color(col.r, col.g, col.b, 0.18)
	ghost.emission_enabled           = true
	ghost.emission                   = emit
	ghost.emission_energy_multiplier = 0.4
	ghost.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost.no_depth_test              = true
	ghost.render_priority            = 1
	mat.next_pass = ghost
	return mat

func _process(delta: float) -> void:
	var dir := Vector3.ZERO

	# Keyboard (WASD / arrow keys, world-axis) — disabled in sensor mode
	if not sensor_mode:
		dir.x += Input.get_axis("ui_left", "ui_right")
		dir.z += Input.get_axis("ui_up",   "ui_down")

	# Virtual joystick always active (joy_dir.y negative = -Z = north)
	if joy_dir.length() > 0.05:
		dir.x += joy_dir.x
		dir.z += joy_dir.y

	if dir.length() > 1.0:
		dir = dir.normalized()

	position += dir * SPEED * delta
	position.y = 0.0   # stay on floor

	# Emit only when moved enough to justify a re-route
	if position.distance_to(_last_emit) > 2.0:
		_last_emit = position
		moved.emit(position)
