# building_loader.gd
extends Node3D

@export var glb_path: String = "res://assets/models/building.glb"
@onready var model_container: Node3D = $ModelContainer
@onready var overlays: Node3D = $RoomOverlays

func _ready():
	load_model()
	create_room_overlays()

func load_model():
	var res = ResourceLoader.load(glb_path)
	if res == null:
		push_error("Failed to load glb: %s" % glb_path)
		return
	var inst = res.instantiate()
	model_container.add_child(inst)
	# Optionally, lower alpha for building to show overlays clearly
	# Search and register rooms by node name "room_" prefix
	register_rooms(inst)

func register_rooms(root: Node):
	# Recursively search for MeshInstance3D nodes whose name contains "room_"
	var stack = [root]
	while stack.size() > 0:
		var n = stack.pop_back()
		for c in n.get_children():
			stack.push_back(c)
		if n is MeshInstance3D and n.name.find("room_") != -1:
			# store room id on mesh for picking
			var id = n.name.replace("room_", "room_")
			n.set_meta("room_id", id)
			# add a simple overlay marker (a colored sphere) as child
			var marker = MeshInstance3D.new()
			marker.mesh = SphereMesh.new()
			marker.scale = Vector3.ONE * 0.3
			marker.translation = n.get_aabb().position + n.get_aabb().size * 0.5
			marker.name = "overlay_%s" % id
			overlays.add_child(marker)
			marker.visible = false
