# ui.gd
extends Control

var target_room_id := ""

func _ready():
	$VBoxContainer/btn_route.pressed.connect(Callable(self, "_on_route_pressed"))

func _on_route_pressed():
	# For demo, route to room_101
	target_room_id = "room_101"
	get_tree().get_root().get_node("Main").call_deferred("_on_route_request", target_room_id)

func get_target_room_id() -> String:
	return target_room_id

func display_route(points: Array):
	# Clear existing Line3D if any, then draw a new Line3D under UI parent or in 3D world
	# For simplicity we update instruction label with a textual list
	var s = ""
	for i in range(points.size()):
		var p = points[i]
		s += "Step %d: (%.1f, %.1f) \n" % [i+1, p.x, p.z]
	$VBoxContainer/lbl_instruction.text = s
