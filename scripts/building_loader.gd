# building_loader.gd — Boeing Everett Factory (simplified schematic)
# Real building: ~160 m wide × ~100 m deep, 4 parallel production bays (N–S).
# Layout (X 0→160, Z –50→50):
#   Bay 747  X=5–35   | Bay 767  X=46–74  | Bay 777  X=86–114 | Bay 777X X=125–155
#   North support corridor  Z=–38–(–50)
#   South support corridor  Z=38–50  (includes entrance plaza at Z=42–50)
#   Inter-bay N–S corridors at X=40, 80, 120
extends Node3D

signal room_clicked(room_id: String)

var ROOMS = [
	# ── Production bays (run N–S, tall ceilings) ─────────────────────────────
	{"id":"bay_747",    "name":"747 Bay (Legacy)",    "capacity":200,
	 "pos":Vector3( 20, 0, 0),   "size":Vector3(30, 12, 70)},
	{"id":"bay_767",    "name":"767 Bay (Tanker)",    "capacity":150,
	 "pos":Vector3( 60, 0, 0),   "size":Vector3(28, 11, 70)},
	{"id":"bay_777",    "name":"777 Bay (Freighter)", "capacity":150,
	 "pos":Vector3(100, 0, 0),   "size":Vector3(28, 11, 70)},
	{"id":"bay_777x",   "name":"777X Bay (WSD)",      "capacity":200,
	 "pos":Vector3(140, 0, 0),   "size":Vector3(30, 12, 70)},
	# ── North support wing ────────────────────────────────────────────────────
	{"id":"visitor_ctr","name":"Visitor Center",      "capacity": 50,
	 "pos":Vector3(  8, 0,-46),  "size":Vector3(14,  5,  8)},
	{"id":"safety_ofc", "name":"Safety & Training",   "capacity": 30,
	 "pos":Vector3( 35, 0,-46),  "size":Vector3(12,  5,  8)},
	{"id":"north_cafe", "name":"North Cafeteria",     "capacity": 80,
	 "pos":Vector3( 80, 0,-46),  "size":Vector3(24,  5,  8)},
	{"id":"quality_ctl","name":"Quality Control",     "capacity": 25,
	 "pos":Vector3(130, 0,-46),  "size":Vector3(16,  5,  8)},
	{"id":"delivery",   "name":"Delivery Center",     "capacity": 30,
	 "pos":Vector3(153, 0,-46),  "size":Vector3(12,  5,  8)},
	# ── South support wing ────────────────────────────────────────────────────
	{"id":"tool_crib",  "name":"Tool Crib",           "capacity": 20,
	 "pos":Vector3(  8, 0, 46),  "size":Vector3(14,  5,  8)},
	{"id":"engineering","name":"Engineering Office",  "capacity": 60,
	 "pos":Vector3( 42, 0, 46),  "size":Vector3(18,  5,  8)},
	{"id":"south_cafe", "name":"South Cafeteria",     "capacity": 80,
	 "pos":Vector3( 80, 0, 46),  "size":Vector3(24,  5,  8)},
	{"id":"final_asm",  "name":"Final Assembly Ctrl", "capacity":100,
	 "pos":Vector3(115, 0, 46),  "size":Vector3(18,  5,  8)},
	{"id":"conf_777x",  "name":"777X Design Conf",    "capacity": 20,
	 "pos":Vector3(148, 0, 46),  "size":Vector3(12,  5,  8)},
	{"id":"med_center", "name":"Medical Center",      "capacity": 15,
	 "pos":Vector3(155, 0, 10),  "size":Vector3( 8,  5, 12)},
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

# ── Structure ─────────────────────────────────────────────────────────────────

func _build_structure() -> void:
	# Main floor slab
	_slab(Vector3(80, -0.10,  0), Vector3(160, 0.20, 100), Color(0.52, 0.50, 0.48))

	# North support corridor strip
	_slab(Vector3(80,  0.01,-44), Vector3(160, 0.02,  12), Color(0.76, 0.74, 0.68))
	# South support corridor + entrance plaza
	_slab(Vector3(80,  0.01, 44), Vector3(160, 0.02,  12), Color(0.76, 0.74, 0.68))

	# Inter-bay N–S corridors (between each pair of bays)
	_slab(Vector3( 40, 0.01,  0), Vector3(6, 0.02, 70), Color(0.70, 0.68, 0.63))
	_slab(Vector3( 80, 0.01,  0), Vector3(6, 0.02, 70), Color(0.70, 0.68, 0.63))
	_slab(Vector3(120, 0.01,  0), Vector3(6, 0.02, 70), Color(0.70, 0.68, 0.63))

	# West and east perimeter walkways
	_slab(Vector3(  3, 0.01,  0), Vector3(4, 0.02, 70), Color(0.68, 0.66, 0.60))
	_slab(Vector3(157, 0.01,  0), Vector3(4, 0.02, 70), Color(0.68, 0.66, 0.60))

	# Bay door markings — yellow safety stripes at north openings of each bay
	for bx: int in [20, 60, 100, 140]:
		_slab(Vector3(bx, 0.015, -38), Vector3(22, 0.01, 5), Color(0.95, 0.85, 0.05))

	# Center-building overhead crane rail markers (thin lines along bay axes)
	for bx: int in [20, 60, 100, 140]:
		_slab(Vector3(bx, 0.015, 0), Vector3(2, 0.01, 68), Color(0.35, 0.35, 0.40))

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

# ── Rooms ─────────────────────────────────────────────────────────────────────

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
	# Glowing floor disk at south entrance (player start)
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
	mi.position = Vector3(80, 0.03, 50)
	add_child(mi)

	var lbl = Label3D.new()
	lbl.text       = "ENTRANCE"
	lbl.position   = Vector3(80, 2.0, 50)
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

# ── Public API ────────────────────────────────────────────────────────────────

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
