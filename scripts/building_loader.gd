# building_loader.gd — School Building (H-plan schematic)
# 100 m wide × 80 m deep (X: 0→100, Z: -40→40)
# Main E-W hallway at Z=0  |  North hallway at Z=-24  |  South hallway at Z=24
# N-S connectors at X=5, X=50 (centre/entrance), X=95
# Player enters from south at (50, 0, 44)
extends Node3D

signal room_clicked(room_id: String)

var ROOMS = [
	# ── North wing classrooms (south face opens onto north hallway) ────────────
	{"id":"bay_747",    "name":"Gymnasium",           "capacity":200,
	 "pos":Vector3(18, 0,-32), "size":Vector3(30, 7, 12)},
	{"id":"bay_767",    "name":"Art Room",             "capacity": 50,
	 "pos":Vector3(64, 0,-31), "size":Vector3(18, 4, 10)},
	{"id":"bay_777",    "name":"Classroom Block",      "capacity": 80,
	 "pos":Vector3(80, 0,-31), "size":Vector3(18, 4, 10)},
	# ── North corridor rooms (main hallway, north side) ────────────────────────
	{"id":"visitor_ctr","name":"Main Office",          "capacity": 20,
	 "pos":Vector3(12, 0, -7), "size":Vector3(18, 4,  9)},
	{"id":"safety_ofc", "name":"Counselor's Office",   "capacity": 10,
	 "pos":Vector3(35, 0, -7), "size":Vector3(14, 4,  9)},
	{"id":"north_cafe", "name":"Staff Lounge",         "capacity": 40,
	 "pos":Vector3(63, 0, -7), "size":Vector3(18, 4,  9)},
	{"id":"quality_ctl","name":"Library",              "capacity": 60,
	 "pos":Vector3(82, 0, -7), "size":Vector3(16, 4,  9)},
	# ── South corridor rooms (main hallway, south side) ────────────────────────
	{"id":"final_asm",  "name":"Assembly Hall",        "capacity":150,
	 "pos":Vector3(20, 0,  7), "size":Vector3(26, 5,  9)},
	{"id":"med_center", "name":"Nurse's Office",       "capacity": 10,
	 "pos":Vector3(42, 0,  7), "size":Vector3(10, 4,  9)},
	{"id":"conf_777x",  "name":"Conference Room",      "capacity": 30,
	 "pos":Vector3(65, 0,  7), "size":Vector3(14, 4,  9)},
	{"id":"bay_777x",   "name":"Computer Lab",         "capacity": 40,
	 "pos":Vector3(84, 0,  7), "size":Vector3(16, 4,  9)},
	# ── South wing rooms (north face opens onto south hallway) ─────────────────
	{"id":"tool_crib",  "name":"Custodial Room",       "capacity": 10,
	 "pos":Vector3(10, 0, 31), "size":Vector3(12, 4, 10)},
	{"id":"engineering","name":"Science Lab",          "capacity": 60,
	 "pos":Vector3(37, 0, 31), "size":Vector3(18, 4, 10)},
	{"id":"south_cafe", "name":"Cafeteria",            "capacity":200,
	 "pos":Vector3(68, 0, 31), "size":Vector3(28, 5, 10)},
	{"id":"delivery",   "name":"Storage Room",         "capacity": 20,
	 "pos":Vector3(90, 0, 31), "size":Vector3(10, 4, 10)},
]

const DEFAULT_SIZE    = Vector3(4.0, 4.0, 4.0)
const COLOR_AVAILABLE = Color(0.22, 0.78, 0.22)
const COLOR_OCCUPIED  = Color(0.80, 0.20, 0.20)
const COLOR_SELECTED  = Color(0.20, 0.42, 0.90)

var _room_bodies:  Dictionary = {}
var _room_mats:    Dictionary = {}
var _selected_id:  String     = ""
var _availability: Dictionary = {}

func _ready() -> void:
	_build_structure()
	_build_rooms()
	_build_entrance_marker()

# ── Structure ──────────────────────────────────────────────────────────────────

func _build_structure() -> void:
	# Main floor slab
	_slab(Vector3(50, -0.10,  0), Vector3(100, 0.20, 80), Color(0.76, 0.74, 0.70))

	# Hallway strips (lighter colour for walkable areas)
	var hall_col := Color(0.91, 0.89, 0.84)
	_slab(Vector3(50, 0.01,   0), Vector3(100, 0.02,  5), hall_col)  # main E-W
	_slab(Vector3(50, 0.01, -24), Vector3(100, 0.02,  4), hall_col)  # north E-W
	_slab(Vector3(50, 0.01,  24), Vector3(100, 0.02,  4), hall_col)  # south E-W

	# N-S connecting corridors at X=5, 50, 95
	var con_col := Color(0.88, 0.86, 0.81)
	_slab(Vector3( 5, 0.01,  0), Vector3( 4, 0.02, 44), con_col)    # west (Z:-22 to 22)
	_slab(Vector3(50, 0.01,  8), Vector3( 4, 0.02, 64), con_col)    # centre (Z:-24 to 40, entrance)
	_slab(Vector3(95, 0.01,  0), Vector3( 4, 0.02, 44), con_col)    # east

	# Perimeter walls (height = 3 m, not interactive)
	var wall_col := Color(0.84, 0.82, 0.78)
	_slab(Vector3(50, 1.5, -41), Vector3(100, 3.0,  2), wall_col)   # north wall
	_slab(Vector3(22, 1.5,  41), Vector3( 44, 3.0,  2), wall_col)   # south-west wall
	_slab(Vector3(78, 1.5,  41), Vector3( 44, 3.0,  2), wall_col)   # south-east wall
	_slab(Vector3( 0, 1.5,   0), Vector3(  2, 3.0, 80), wall_col)   # west wall
	_slab(Vector3(100,1.5,   0), Vector3(  2, 3.0, 80), wall_col)   # east wall

	# Entrance header above the gap in the south wall
	_slab(Vector3(50, 3.2,  41), Vector3( 12, 0.8,  2), Color(0.72, 0.70, 0.66))

	# Hallway centre-line dots (locker suggestion, every 6 m along main hall)
	for xi in range(8, 95, 6):
		_slab(Vector3(xi, 0.02, -2.3), Vector3(0.8, 0.04, 0.25), Color(0.58, 0.60, 0.68))
		_slab(Vector3(xi, 0.02,  2.3), Vector3(0.8, 0.04, 0.25), Color(0.58, 0.60, 0.68))

func _slab(pos: Vector3, sz: Vector3, col: Color) -> void:
	var mi  = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = sz
	mi.mesh  = box
	var mat  = StandardMaterial3D.new()
	mat.albedo_color = col
	mi.material_override = mat
	mi.position = pos
	add_child(mi)

# ── Rooms ──────────────────────────────────────────────────────────────────────

func _build_rooms() -> void:
	for rd in ROOMS:
		var id:  String  = rd["id"]
		var pos: Vector3 = rd["pos"]
		var sz:  Vector3 = rd.get("size", DEFAULT_SIZE)

		var body = StaticBody3D.new()
		body.position = pos + Vector3(0, sz.y * 0.5, 0)
		body.name     = "Room_" + id
		add_child(body)

		var mi  = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = sz
		mi.mesh  = box
		var mat  = StandardMaterial3D.new()
		mat.albedo_color = COLOR_AVAILABLE
		mi.material_override = mat
		body.add_child(mi)
		_room_mats[id] = mat

		var col = CollisionShape3D.new()
		var shp = BoxShape3D.new()
		shp.size  = sz
		col.shape = shp
		body.add_child(col)

		var lbl = Label3D.new()
		lbl.text       = "%s\n(cap %d)" % [rd["name"], rd["capacity"]]
		lbl.position   = Vector3(0, sz.y * 0.65, 0)
		lbl.pixel_size = 0.014
		lbl.billboard  = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.font_size  = 24
		body.add_child(lbl)

		body.input_event.connect(_on_room_input_event.bind(id))
		_room_bodies[id] = body

func _build_entrance_marker() -> void:
	var mi  = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.height = 0.06; cyl.top_radius = 1.5; cyl.bottom_radius = 1.5
	mi.mesh = cyl
	var mat = StandardMaterial3D.new()
	mat.albedo_color             = Color(0.0, 0.6, 1.0)
	mat.emission_enabled         = true
	mat.emission                 = Color(0.0, 0.3, 0.9)
	mat.emission_energy_multiplier = 1.2
	mi.material_override = mat
	mi.position = Vector3(50, 0.03, 44)
	add_child(mi)

	var lbl = Label3D.new()
	lbl.text       = "ENTRANCE"
	lbl.position   = Vector3(50, 2.0, 44)
	lbl.pixel_size = 0.012
	lbl.billboard  = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.modulate   = Color(0.0, 0.6, 1.0)
	lbl.font_size  = 28
	add_child(lbl)

func _on_room_input_event(_cam, event, _pos, _normal, _idx, room_id: String) -> void:
	if event is InputEventMouseButton \
			and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		room_clicked.emit(room_id)

# ── Public API ─────────────────────────────────────────────────────────────────

func select_room(id: String) -> void:
	clear_selection()
	_selected_id = id
	if _room_mats.has(id):
		_room_mats[id].albedo_color = COLOR_SELECTED

func clear_selection() -> void:
	if _selected_id != "" and _room_mats.has(_selected_id):
		var avail = _availability.get(_selected_id, true)
		_room_mats[_selected_id].albedo_color = \
			COLOR_AVAILABLE if avail else COLOR_OCCUPIED
	_selected_id = ""

func update_room_availability(data: Dictionary) -> void:
	_availability.clear()
	for room_id in data:
		var avail = data[room_id].get("available", true)
		_availability[room_id] = avail
		if _room_mats.has(room_id) and room_id != _selected_id:
			_room_mats[room_id].albedo_color = \
				COLOR_AVAILABLE if avail else COLOR_OCCUPIED

func get_room_data() -> Array:
	var result = []
	for rd in ROOMS:
		var d = rd.duplicate()
		d["available"] = _availability.get(rd["id"], true)
		result.append(d)
	return result
