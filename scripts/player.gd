# player.gd
# Represents the operator walking through the building.
# Keyboard : WASD / arrow keys  (world-axis; matches the top-down camera view)
# Mobile   : joy_dir set each frame by the UI virtual joystick
extends Node3D

signal moved(pos: Vector3)

const SPEED := 5.0   # metres per second

var joy_dir   := Vector2.ZERO   # fed by UI joystick each frame
var _last_emit := Vector3.ZERO

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
	mat.albedo_color             = Color(0.0, 0.85, 1.0)
	mat.emission_enabled         = true
	mat.emission                 = Color(0.0, 0.45, 0.9)
	mat.emission_energy_multiplier = 1.4
	mi.material_override = mat
	mi.position = Vector3(0, 0.9, 0)
	add_child(mi)

	# Billboard label
	var lbl = Label3D.new()
	lbl.text       = "YOU"
	lbl.pixel_size = 0.010
	lbl.font_size  = 30
	lbl.billboard  = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.modulate   = Color(0.0, 1.0, 1.0)
	lbl.position   = Vector3(0, 2.1, 0)
	add_child(lbl)

func _process(delta: float) -> void:
	var dir := Vector3.ZERO

	# Keyboard (WASD / arrow keys, world-axis)
	dir.x += Input.get_axis("ui_left", "ui_right")
	dir.z += Input.get_axis("ui_up",   "ui_down")

	# Virtual joystick (joy_dir.y is negative when pushed up → move in -Z = north)
	if joy_dir.length() > 0.05:
		dir.x += joy_dir.x
		dir.z += joy_dir.y

	if dir.length() > 1.0:
		dir = dir.normalized()

	position += dir * SPEED * delta
	position.y = 0.0   # stay on floor

	# Emit only when moved enough to justify a re-route
	if position.distance_to(_last_emit) > 0.5:
		_last_emit = position
		moved.emit(position)
