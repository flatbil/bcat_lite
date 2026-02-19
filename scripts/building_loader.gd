# building_loader.gd — procedural building, no GLB required
extends Node3D

signal room_clicked(room_id: String)

# Building: 28 m wide (X 0→28), 22 m deep (Z -11 to 11)
# Three E-W corridors connected by three N-S cross-corridors.
var ROOMS = [
	# ── North wing (behind north hall at Z = -5) ───────────────────────────
	{"id":"boardroom","name":"Boardroom",  "capacity":20,"pos":Vector3(6,  0,-9.5),"size":Vector3(8,2.8,5)},
	{"id":"conf_a",   "name":"Conf A",    "capacity":12,"pos":Vector3(14, 0,-9.5),"size":Vector3(5,2.4,4)},
	{"id":"conf_b",   "name":"Conf B",    "capacity":10,"pos":Vector3(21, 0,-9.5),"size":Vector3(5,2.4,4)},
	# ── South wing (behind south hall at Z = 5) ────────────────────────────
	{"id":"conf_c",   "name":"Conf C",    "capacity":10,"pos":Vector3(6,  0, 9.5),"size":Vector3(5,2.4,4)},
	{"id":"conf_d",   "name":"Conf D",    "capacity":12,"pos":Vector3(14, 0, 9.5),"size":Vector3(5,2.4,4)},
	{"id":"conf_e",   "name":"Conf E",    "capacity":10,"pos":Vector3(21, 0, 9.5),"size":Vector3(5,2.4,4)},
	# ── Focus rooms off main corridor ──────────────────────────────────────
	{"id":"focus_a",  "name":"Focus A",   "capacity": 4,"pos":Vector3(6,  0,-2.5),"size":Vector3(3,2.4,3)},
	{"id":"focus_b",  "name":"Focus B",   "capacity": 4,"pos":Vector3(19, 0,-2.5),"size":Vector3(3,2.4,3)},
	{"id":"focus_c",  "name":"Focus C",   "capacity": 4,"pos":Vector3(6,  0, 2.5),"size":Vector3(3,2.4,3)},
	{"id":"focus_d",  "name":"Focus D",   "capacity": 4,"pos":Vector3(19, 0, 2.5),"size":Vector3(3,2.4,3)},
	# ── East alcove rooms ─────────────────────────────────────────────────
	{"id":"east_a",   "name":"East Mtg A","capacity": 6,"pos":Vector3(26, 0,-3),  "size":Vector3(4,2.4,4)},
	{"id":"east_b",   "name":"East Mtg B","capacity": 6,"pos":Vector3(26, 0, 3),  "size":Vector3(4,2.4,4)},
]

const DEFAULT_SIZE    = Vector3(4.0, 2.4, 3.0)
const COLOR_AVAILABLE = Color(0.22, 0.78, 0.22)
const COLOR_OCCUPIED  = Color(0.80, 0.20, 0.20)
const COLOR_SELECTED  = Color(0.20, 0.42, 0.90)

var _room_bodies: Dictionary = {}
var _room_mats:   Dictionary = {}
var _selected_id: String     = ""
var _availability: Dictionary = {}

func _ready() -> void:
	_build_structure()
	_build_rooms()
	_build_entrance_marker()

# ── Structure ────────────────────────────────────────────────────────────────

func _build_structure() -> void:
	# Floor slab
	_slab(Vector3(13, -0.1,  0), Vector3(28, 0.2, 22), Color(0.60, 0.58, 0.56))
	# Main corridor  (Z = 0,  runs full width)
	_slab(Vector3(13, 0.01,  0), Vector3(28, 0.02, 2.2), Color(0.82, 0.80, 0.72))
	# North wing corridor (Z = -5, X 2→26)
	_slab(Vector3(14, 0.01, -5), Vector3(24, 0.02, 2.2), Color(0.80, 0.78, 0.70))
	# South wing corridor (Z = 5, X 2→26)
	_slab(Vector3(14, 0.01,  5), Vector3(24, 0.02, 2.2), Color(0.80, 0.78, 0.70))
	# West cross-connector  (X = 2,  Z -5→5)
	_slab(Vector3(2,  0.01,  0), Vector3(2.2, 0.02, 10), Color(0.76, 0.74, 0.68))
	# Mid  cross-connector  (X = 13, Z -5→5)
	_slab(Vector3(13, 0.01,  0), Vector3(2.2, 0.02, 10), Color(0.76, 0.74, 0.68))
	# East cross-connector  (X = 24, Z -5→5)
	_slab(Vector3(24, 0.01,  0), Vector3(2.2, 0.02, 10), Color(0.76, 0.74, 0.68))

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
		var id:   String  = rd["id"]
		var pos:  Vector3 = rd["pos"]
		var sz:   Vector3 = rd.get("size", DEFAULT_SIZE)

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
		shp.size   = sz
		col.shape  = shp
		body.add_child(col)

		var lbl = Label3D.new()
		lbl.text       = "%s\n(cap %d)" % [rd["name"], rd["capacity"]]
		lbl.position   = Vector3(0, sz.y * 0.65, 0)
		lbl.pixel_size = 0.012
		lbl.billboard  = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.font_size  = 26
		body.add_child(lbl)

		body.input_event.connect(_on_room_input_event.bind(id))
		_room_bodies[id] = body

func _build_entrance_marker() -> void:
	var mi  = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.height = 0.06; cyl.top_radius = 0.5; cyl.bottom_radius = 0.5
	mi.mesh   = cyl
	var mat   = StandardMaterial3D.new()
	mat.albedo_color = Color(0.0, 0.6, 1.0)
	mi.material_override = mat
	mi.position = Vector3(0, 0.03, 0)
	add_child(mi)

	var lbl = Label3D.new()
	lbl.text       = "ENTRANCE"
	lbl.position   = Vector3(0, 0.7, 0)
	lbl.pixel_size = 0.009
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
