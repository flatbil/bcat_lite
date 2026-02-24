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
	# Glowing cyan cylinder body
	var mi  = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.height        = 1.8
	cyl.top_radius    = 0.22
	cyl.bottom_radius = 0.22
	mi.mesh = cyl
	var mat = StandardMaterial3D.new()
	mat.albedo_color               = Color(0.0, 0.85, 1.0)
	mat.emission_enabled           = true
	mat.emission                   = Color(0.0, 0.45, 0.9)
	mat.emission_energy_multiplier = 1.4
	# Ghost pass: outline visible through walls at low opacity
	var ghost = StandardMaterial3D.new()
	ghost.albedo_color               = Color(0.0, 0.85, 1.0, 0.22)
	ghost.emission_enabled           = true
	ghost.emission                   = Color(0.0, 0.45, 0.9)
	ghost.emission_energy_multiplier = 0.6
	ghost.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost.no_depth_test              = true
	ghost.render_priority            = 1
	mat.next_pass = ghost
	mi.material_override = mat
	mi.position = Vector3(0, 0.9, 0)
	add_child(mi)

	# Billboard label — fixed screen size like a Google Maps pin
	var lbl = Label3D.new()
	lbl.text       = "YOU"
	lbl.font_size  = 9
	lbl.pixel_size = 0.010
	lbl.billboard  = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.modulate   = Color(0.0, 1.0, 1.0)
	lbl.position   = Vector3(0, 2.1, 0)
	add_child(lbl)

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
