# main.gd
extends Node3D

@onready var building = $Building
@onready var simloc = $SimLocation
@onready var navigator = $Navigation
@onready var ui = $CanvasLayer.get_node("UI") # adjust path as needed
@onready var room_manager = Node.new()

func _ready():
	# add room_manager (for later Graph integration)
	room_manager = preload("res://scripts/room_manager.gd").new()
	add_child(room_manager)
	building.add_to_group("building")
	simloc.connect("location_changed", Callable(self, "_on_location_changed"))
	# load rooms on start
	room_manager.fetch_rooms()

func _on_location_changed(new_pos: Vector3):
	# update player marker (optional)
	# compute current route if a destination is set in UI
	if ui.has_method("get_target_room_id"):
		var rid = ui.get_target_room_id()
		if rid != "":
			var pts = navigator.route_to_room(new_pos, rid)
			ui.call("display_route", pts)
