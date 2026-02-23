# main.gd
extends Node3D

@onready var building:     Node3D  = $Building
@onready var navigator:    Node    = $Navigator
@onready var room_manager: Node    = $RoomManager
@onready var path_display: Node3D  = $PathDisplay
@onready var ui:           Control = $CanvasLayer/Ui
@onready var player:       Node3D  = $Player
@onready var sim_loc:      Node    = $SimLocation

# Last rooms payload from backend (includes meetings_today per room)
var _rooms_data:     Dictionary = {}
var _current_dest:   String     = ""
var _last_route_pos: Vector3    = Vector3(1e9, 1e9, 1e9)
var _sensor_mode:    bool       = false

func _ready() -> void:
	get_viewport().physics_object_picking = true

	building.room_clicked.connect(_on_room_info_requested)
	room_manager.rooms_updated.connect(_on_rooms_updated)
	ui.navigate_requested.connect(_navigate_to)
	ui.navigation_cleared.connect(_clear_route)
	ui.room_info_requested.connect(_on_room_info_requested)
	ui.joy_input.connect(func(d: Vector2) -> void: player.joy_dir = d)

	# Sensor / location bar signals
	ui.sensor_mode_toggled.connect(_on_sensor_mode_toggled)
	ui.calibrate_north_requested.connect(_on_calibrate_north)
	ui.reset_position_requested.connect(_on_reset_position)
	sim_loc.location_changed.connect(_on_sim_location_changed)

	ui.set_room_data(building.get_room_data())
	room_manager.fetch_rooms()

func _process(delta: float) -> void:
	if _current_dest.is_empty() or not is_instance_valid(player):
		return
	if player.position.distance_to(_last_route_pos) > 2.0:
		_last_route_pos = player.position
		var pts = navigator.route_to_room(player.global_position, _current_dest)
		_draw_path(pts)
		ui.show_navigation(_current_dest, pts)

	# Update compass display while sensor mode is active
	if _sensor_mode:
		ui.update_compass(sim_loc.get_current_bearing_deg())

func _on_rooms_updated(data: Dictionary) -> void:
	_rooms_data = data
	building.update_room_availability(data)
	ui.update_availability(data)

# 3D click OR left-panel ℹ button → show meeting popup
func _on_room_info_requested(room_id: String) -> void:
	var data: Dictionary = _rooms_data.get(room_id, {})
	if data.is_empty():
		for r in building.get_room_data():
			if r["id"] == room_id:
				data = r
				break
	ui.show_room_popup(room_id, data)

# "Go" button or popup "Navigate Here" → route from player's current position
func _navigate_to(room_id: String) -> void:
	_current_dest    = room_id
	_last_route_pos  = player.global_position
	var pts = navigator.route_to_room(player.global_position, room_id)
	_draw_path(pts)
	building.select_room(room_id)
	ui.show_navigation(room_id, pts)

func _draw_path(points: Array) -> void:
	# Clear previous geometry only (do NOT reset _current_dest here)
	for child in path_display.get_children():
		child.queue_free()
	if points.size() < 2:
		return
	for i in range(points.size() - 1):
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		var dir    = b - a
		var length = dir.length()
		if length < 0.001:
			continue
		var mid = (a + b) * 0.5
		var seg = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = Vector3(0.45, 0.22, length)
		seg.mesh = box
		var mat = StandardMaterial3D.new()
		mat.albedo_color               = Color(1.0, 0.88, 0.0)
		mat.emission_enabled           = true
		mat.emission                   = Color(0.9, 0.65, 0.0)
		mat.emission_energy_multiplier = 1.8
		seg.material_override = mat
		seg.position  = Vector3(mid.x, 0.14, mid.z)
		seg.rotation.y = atan2(dir.x, dir.z)
		path_display.add_child(seg)

	for pt: Vector3 in points:
		var dot    = MeshInstance3D.new()
		var sphere = SphereMesh.new()
		sphere.radius = 0.28
		sphere.height = 0.56
		dot.mesh = sphere
		var mat = StandardMaterial3D.new()
		mat.albedo_color               = Color(1.0, 0.45, 0.0)
		mat.emission_enabled           = true
		mat.emission                   = Color(0.8, 0.25, 0.0)
		mat.emission_energy_multiplier = 1.8
		dot.material_override = mat
		dot.position = Vector3(pt.x, 0.28, pt.z)
		path_display.add_child(dot)

# Called when user clicks "✕ Clear Route"
func _clear_route() -> void:
	_current_dest   = ""
	_last_route_pos = Vector3(1e9, 1e9, 1e9)
	for child in path_display.get_children():
		child.queue_free()
	building.clear_selection()

# ── Sensor / location callbacks ────────────────────────────────────────────────

func _on_sim_location_changed(pos: Vector3) -> void:
	player.position = pos

func _on_sensor_mode_toggled(on: bool) -> void:
	_sensor_mode        = on
	player.sensor_mode  = on
	sim_loc.enable(on)
	if on:
		sim_loc.set_start_position(player.position)

func _on_calibrate_north() -> void:
	sim_loc.calibrate_north()

func _on_reset_position() -> void:
	var entrance := Vector3(50, 0, 44)
	player.position = entrance
	sim_loc.set_start_position(entrance)
