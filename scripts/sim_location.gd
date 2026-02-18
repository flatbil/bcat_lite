# sim_location.gd
extends Node3D

signal location_changed(new_pos: Vector3)

var dragging := false
@onready var camera := $"../Camera3D" setget _set_camera

func _set_camera(c):
	camera = c

func _input(event):
	if event is InputEventScreenTouch:
		if event.pressed:
			dragging = true
			_update_pos_from_screen(event.position)
		else:
			dragging = false
	elif event is InputEventScreenDrag and dragging:
		_update_pos_from_screen(event.position)

func _update_pos_from_screen(screen_pos: Vector2):
	if camera == null:
		return
	var from = camera.project_ray_origin(screen_pos)
	var to = from + camera.project_ray_normal(screen_pos) * 100.0
	var space = get_world_3d().direct_space_state
	var res = space.intersect_ray(from, to, [], 1)
	if res:
		var pt = res.position
		translation = Vector3(pt.x, pt.y + 0.1, pt.z) # place marker slightly above floor
		emit_signal("location_changed", translation)
