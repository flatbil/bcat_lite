# main.gd
extends Node3D

@onready var building:     Node3D  = $Building
@onready var navigator:    Node    = $Navigator
@onready var room_manager: Node    = $RoomManager
@onready var path_display: Node3D  = $PathDisplay
@onready var ui:           Control = $CanvasLayer/Ui
@onready var player:       Node3D  = $Player
@onready var sim_loc:      Node    = $SimLocation
@onready var campus_mgr:   Node    = $CampusManager

var _rooms_data:          Dictionary = {}
var _current_dest:        String     = ""
var _last_route_pos:      Vector3    = Vector3(1e9, 1e9, 1e9)
var _sensor_mode:         bool       = false
var _current_building_id: String     = ""
var _active_floor:        int        = 0
var _last_cam_y:          float      = -1.0   # track zoom for path/player scale


func _ready() -> void:
	get_viewport().physics_object_picking = true

	building.room_clicked.connect(_on_room_info_requested)
	room_manager.rooms_updated.connect(_on_rooms_updated)
	ui.navigate_requested.connect(_navigate_to)
	ui.navigation_cleared.connect(_clear_route)
	ui.room_info_requested.connect(_on_room_info_requested)
	ui.joy_input.connect(func(d: Vector2) -> void: player.joy_dir = d)
	ui.sensor_mode_toggled.connect(_on_sensor_mode_toggled)
	ui.calibrate_north_requested.connect(_on_calibrate_north)
	ui.reset_position_requested.connect(_on_reset_position)
	ui.building_selected.connect(load_building)
	ui.floor_selected.connect(switch_floor)

	sim_loc.location_changed.connect(_on_sim_location_changed)
	sim_loc.gps_fix.connect(_on_gps_fix)

	campus_mgr.building_list_loaded.connect(_on_building_list_loaded)
	campus_mgr.building_detected.connect(load_building)
	campus_mgr.load_campus()


func _on_building_list_loaded() -> void:
	ui.set_building_list(campus_mgr.get_building_list())
	# Auto-load first building
	var list: Array = campus_mgr.get_building_list()
	if list.size() > 0:
		load_building(list[0]["id"])


func load_building(building_id: String) -> void:
	if building_id == _current_building_id:
		return
	_current_building_id = building_id
	_clear_route()

	var data: Dictionary = campus_mgr.load_building_data(building_id)
	if data.is_empty():
		push_error("main: failed to load building data for " + building_id)
		return

	building.load_building(data)
	navigator.load_building_graph(data)

	var entrance: Vector3 = building.get_entrance()
	player.position = entrance
	sim_loc.set_start_position(entrance)

	_active_floor = 0
	ui.set_floors(building.get_floors(), _active_floor)
	ui.set_room_data(building.get_room_data())
	room_manager.set_building(building_id)
	room_manager.fetch_rooms()


func switch_floor(floor_index: int) -> void:
	if floor_index == _active_floor:
		return
	_active_floor = floor_index
	building.set_active_floor(floor_index)
	ui.set_active_floor(floor_index)
	var cam := get_node_or_null("Camera3D")
	if cam and cam.has_method("set_look_at_y"):
		cam.set_look_at_y(float(floor_index) * 4.0)


func _process(_delta: float) -> void:
	# Camera-height-driven scaling for player + path (constant apparent size)
	var cam := get_node_or_null("Camera3D")
	if cam and absf(cam.global_position.y - _last_cam_y) > 2.0:
		_last_cam_y = cam.global_position.y
		var s: float = _cam_scale()
		player.scale = Vector3(s, s, s)
		if not _current_dest.is_empty():
			var pts: Array = navigator.route_to_room(player.global_position, _current_dest)
			_draw_path(pts)
			ui.show_navigation(_current_dest, pts)

	if _current_dest.is_empty() or not is_instance_valid(player):
		return
	if player.position.distance_to(_last_route_pos) > 2.0:
		_last_route_pos = player.position
		var pts: Array = navigator.route_to_room(player.global_position, _current_dest)
		_draw_path(pts)
		ui.show_navigation(_current_dest, pts)

	if _sensor_mode:
		ui.update_compass(sim_loc.get_current_bearing_deg())


# Scale factor so path/player keep constant apparent size as camera zooms.
# Reference height 30 m → scale 1.0.
func _cam_scale() -> float:
	var cam := get_node_or_null("Camera3D")
	if cam == null:
		return 1.0
	return clampf(cam.global_position.y / 30.0, 0.3, 6.0)


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
	# Auto-switch floor if the target is on a different floor
	for r in building.get_room_data():
		if r["id"] == room_id:
			var fi: int = int(r.get("floor_index", 0))
			if fi != _active_floor:
				switch_floor(fi)
			break

	_current_dest   = room_id
	_last_route_pos = player.global_position
	var pts: Array = navigator.route_to_room(player.global_position, room_id)
	_draw_path(pts)
	building.select_room(room_id)
	ui.show_navigation(room_id, pts)


func _draw_path(points: Array) -> void:
	for child in path_display.get_children():
		child.queue_free()
	if points.size() < 2:
		return

	var s: float = _cam_scale()

	for i in range(points.size() - 1):
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		var dir    := b - a
		var length := dir.length()
		if length < 0.001:
			continue
		var mid := (a + b) * 0.5
		var seg  := MeshInstance3D.new()
		var box  := BoxMesh.new()
		box.size = Vector3(0.45 * s, 0.22 * s, length)
		seg.mesh = box
		seg.material_override = _path_mat(Color(1.0, 0.88, 0.0), Color(0.9, 0.65, 0.0))
		seg.position   = Vector3(mid.x, mid.y + 0.14 * s, mid.z)
		seg.rotation.y = atan2(dir.x, dir.z)
		path_display.add_child(seg)

	for pt: Vector3 in points:
		var dot    := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.28 * s
		sphere.height = 0.56 * s
		dot.mesh = sphere
		dot.material_override = _path_mat(Color(1.0, 0.45, 0.0), Color(0.8, 0.25, 0.0))
		dot.position = Vector3(pt.x, pt.y + 0.28 * s, pt.z)
		path_display.add_child(dot)


# Shared material factory for path elements.
# Primary pass: normal depth-tested render.
# next_pass: ghost outline visible through geometry at low opacity.
func _path_mat(col: Color, emit: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color               = col
	mat.emission_enabled           = true
	mat.emission                   = emit
	mat.emission_energy_multiplier = 1.8

	var ghost := StandardMaterial3D.new()
	ghost.albedo_color               = Color(col.r, col.g, col.b, 0.20)
	ghost.emission_enabled           = true
	ghost.emission                   = emit
	ghost.emission_energy_multiplier = 0.5
	ghost.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost.no_depth_test              = true
	ghost.render_priority            = 1
	mat.next_pass = ghost

	return mat


func _clear_route() -> void:
	_current_dest   = ""
	_last_route_pos = Vector3(1e9, 1e9, 1e9)
	for child in path_display.get_children():
		child.queue_free()
	building.clear_selection()


# ── Sensor / location callbacks ───────────────────────────────────────────────

func _on_sim_location_changed(pos: Vector3) -> void:
	player.position = pos


func _on_gps_fix(lat: float, lon: float) -> void:
	campus_mgr.detect_building(lat, lon)


func _on_sensor_mode_toggled(on: bool) -> void:
	_sensor_mode       = on
	player.sensor_mode = on
	sim_loc.enable(on)
	if on:
		sim_loc.set_start_position(player.position)


func _on_calibrate_north() -> void:
	sim_loc.calibrate_north()


func _on_reset_position() -> void:
	var entrance: Vector3 = building.get_entrance()
	player.position = entrance
	sim_loc.set_start_position(entrance)
