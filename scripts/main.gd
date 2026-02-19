# main.gd
extends Node3D

const START_POS = Vector3(0.0, 0.0, 0.0)

@onready var building:      Node3D  = $Building
@onready var navigator:     Node    = $Navigator
@onready var room_manager:  Node    = $RoomManager
@onready var path_display:  Node3D  = $PathDisplay
@onready var ui:            Control = $CanvasLayer/Ui

# Last rooms payload from backend (includes meetings_today per room)
var _rooms_data: Dictionary = {}

func _ready() -> void:
	get_viewport().physics_object_picking = true

	building.room_clicked.connect(_on_room_info_requested)
	room_manager.rooms_updated.connect(_on_rooms_updated)
	ui.navigate_requested.connect(_navigate_to)
	ui.navigation_cleared.connect(_clear_path)
	ui.room_info_requested.connect(_on_room_info_requested)
	ui.set_room_data(building.get_room_data())
	room_manager.fetch_rooms()

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

# Left-panel "Go" or popup "Navigate Here" → draw path
func _navigate_to(room_id: String) -> void:
	var pts = navigator.route_to_room(START_POS, room_id)
	_draw_path(pts)
	building.select_room(room_id)
	ui.show_navigation(room_id, pts)

func _draw_path(points: Array) -> void:
	_clear_path()
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
		mat.albedo_color             = Color(1.0, 0.88, 0.0)
		mat.emission_enabled         = true
		mat.emission                 = Color(0.9, 0.65, 0.0)
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
		mat.albedo_color             = Color(1.0, 0.45, 0.0)
		mat.emission_enabled         = true
		mat.emission                 = Color(0.8, 0.25, 0.0)
		mat.emission_energy_multiplier = 1.8
		dot.material_override = mat
		dot.position = Vector3(pt.x, 0.28, pt.z)
		path_display.add_child(dot)

func _clear_path() -> void:
	for child in path_display.get_children():
		child.queue_free()
	building.clear_selection()
