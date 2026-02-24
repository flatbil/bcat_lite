# building_loader.gd — Data-driven multi-floor building renderer
extends Node3D

signal room_clicked(room_id: String)

const COLOR_AVAILABLE := Color(0.22, 0.78, 0.22)
const COLOR_OCCUPIED  := Color(0.80, 0.20, 0.20)
const COLOR_SELECTED  := Color(0.20, 0.42, 0.90)
const STAIR_COLOR     := Color(0.55, 0.50, 0.45)

var _building_type:  String     = ""
var _floor_height:   float      = 4.0
var _footprint:      Vector2    = Vector2(100, 80)
var _floors_data:    Array      = []   # raw floor dicts from JSON
var _all_rooms:      Array      = []   # flat list across all floors; each entry has "floor_index"
var _room_bodies:    Dictionary = {}   # room_id -> StaticBody3D (mesh/collision, NOT pickable)
var _label_bodies:   Dictionary = {}   # room_id -> StaticBody3D (label hit-area, pickable)
var _room_mats:      Dictionary = {}   # room_id -> StandardMaterial3D
var _floor_nodes:    Array      = []   # Node3D per floor (index = floor index)
var _active_floor:   int        = 0
var _selected_id:    String     = ""
var _availability:   Dictionary = {}
var _entrance:       Vector3    = Vector3(50, 0, 44)


# ── Public: load a building from a parsed JSON dict ───────────────────────────

func load_building(data: Dictionary) -> void:
	# Clear previous geometry
	for child in get_children():
		child.queue_free()
	_room_bodies.clear()
	_label_bodies.clear()
	_room_mats.clear()
	_floor_nodes.clear()
	_all_rooms.clear()
	_availability.clear()
	_selected_id  = ""
	_active_floor = 0

	_building_type = data.get("type", "generic")
	_floor_height  = float(data.get("floor_height", 4.0))
	var fp         = data.get("footprint", [100, 80])
	_footprint     = Vector2(float(fp[0]), float(fp[1]))
	var ent        = data.get("entrance", [50, 0, 44])
	_entrance      = Vector3(float(ent[0]), float(ent[1]), float(ent[2]))

	_floors_data   = data.get("floors", [])
	var vc_list: Array = data.get("vertical_connections", [])

	for floor_dict in _floors_data:
		var fi: int     = int(floor_dict.get("index", 0))
		var y_off: float = fi * _floor_height
		var fn := Node3D.new()
		fn.name = "floor_%d" % fi
		add_child(fn)
		while _floor_nodes.size() <= fi:
			_floor_nodes.append(null)
		_floor_nodes[fi] = fn
		_generate_floor(floor_dict, fi, y_off, fn)

	_generate_vertical_connections(vc_list)
	_build_entrance_marker()
	set_active_floor(0)


# ── Floor geometry ─────────────────────────────────────────────────────────────

func _generate_floor(floor_dict: Dictionary, fi: int, y_off: float, parent: Node3D) -> void:
	# Build structural geometry
	if _building_type == "school_h_plan" and fi == 0:
		_build_school_structure(parent, y_off)
	else:
		_build_simple_floor(parent, y_off)

	# Build rooms
	var rooms_list: Array = floor_dict.get("rooms", [])
	for rd in rooms_list:
		var id: String = rd["id"]
		var rp         = rd["pos"]
		var rs         = rd.get("size", [4, 4, 4])
		var sz         := Vector3(float(rs[0]), float(rs[1]), float(rs[2]))
		# Body center = floor level + local Y offset + half room height
		var pos        := Vector3(float(rp[0]), y_off + float(rp[1]) + sz.y * 0.5, float(rp[2]))

		var body := StaticBody3D.new()
		body.position = pos
		body.name     = "Room_" + id
		parent.add_child(body)

		var mi  := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = sz
		mi.mesh  = box
		var mat  := StandardMaterial3D.new()
		mat.albedo_color = COLOR_AVAILABLE
		mi.material_override = mat
		body.add_child(mi)
		_room_mats[id] = mat

		var col := CollisionShape3D.new()
		var shp := BoxShape3D.new()
		shp.size  = sz
		col.shape = shp
		body.add_child(col)

		# Room body is NOT ray-pickable — click target is the label hit-area below
		body.input_ray_pickable = false

		var lbl_y: float = sz.y * 0.65
		var lbl       := Label3D.new()
		var cap: int   = int(rd.get("capacity", 0))
		lbl.text       = "%s\n(cap %d)" % [rd["name"], cap]
		lbl.position   = Vector3(0, lbl_y, 0)
		lbl.billboard  = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.font_size  = 7
		lbl.fixed_size = true
		body.add_child(lbl)

		# Small flat hit-area at the label position — this is what the player clicks
		var lb_body := StaticBody3D.new()
		lb_body.position = Vector3(0, lbl_y, 0)
		lb_body.name     = "LabelHit_" + id
		var lb_col := CollisionShape3D.new()
		var lb_shp := BoxShape3D.new()
		lb_shp.size   = Vector3(maxf(sz.x * 0.55, 6.0), 0.5, maxf(sz.z * 0.55, 3.0))
		lb_col.shape  = lb_shp
		lb_body.add_child(lb_col)
		lb_body.input_event.connect(_on_room_input_event.bind(id))
		body.add_child(lb_body)
		_label_bodies[id] = lb_body

		_room_bodies[id] = body

		var entry = rd.duplicate()
		entry["floor_index"] = fi
		entry["available"]   = true
		_all_rooms.append(entry)


func _build_school_structure(parent: Node3D, y_off: float) -> void:
	# Main floor slab
	_slab(parent, Vector3(50, y_off - 0.10,  0), Vector3(100, 0.20, 80), Color(0.76, 0.74, 0.70))

	# Hallway strips
	var hall_col := Color(0.91, 0.89, 0.84)
	_slab(parent, Vector3(50, y_off + 0.01,   0), Vector3(100, 0.02,  5), hall_col)
	_slab(parent, Vector3(50, y_off + 0.01, -24), Vector3(100, 0.02,  4), hall_col)
	_slab(parent, Vector3(50, y_off + 0.01,  24), Vector3(100, 0.02,  4), hall_col)

	# N-S connecting corridors
	var con_col := Color(0.88, 0.86, 0.81)
	_slab(parent, Vector3( 5, y_off + 0.01,  0), Vector3( 4, 0.02, 44), con_col)
	_slab(parent, Vector3(50, y_off + 0.01,  8), Vector3( 4, 0.02, 64), con_col)
	_slab(parent, Vector3(95, y_off + 0.01,  0), Vector3( 4, 0.02, 44), con_col)

	# Perimeter walls
	var wall_col := Color(0.84, 0.82, 0.78)
	_slab(parent, Vector3(50, y_off + 1.5, -41), Vector3(100, 3.0,  2), wall_col)
	_slab(parent, Vector3(22, y_off + 1.5,  41), Vector3( 44, 3.0,  2), wall_col)
	_slab(parent, Vector3(78, y_off + 1.5,  41), Vector3( 44, 3.0,  2), wall_col)
	_slab(parent, Vector3( 0, y_off + 1.5,   0), Vector3(  2, 3.0, 80), wall_col)
	_slab(parent, Vector3(100,y_off + 1.5,   0), Vector3(  2, 3.0, 80), wall_col)

	# Entrance header
	_slab(parent, Vector3(50, y_off + 3.2, 41), Vector3(12, 0.8, 2), Color(0.72, 0.70, 0.66))

	# Locker dots
	for xi in range(8, 95, 6):
		_slab(parent, Vector3(xi, y_off + 0.02, -2.3), Vector3(0.8, 0.04, 0.25), Color(0.58, 0.60, 0.68))
		_slab(parent, Vector3(xi, y_off + 0.02,  2.3), Vector3(0.8, 0.04, 0.25), Color(0.58, 0.60, 0.68))


func _build_simple_floor(parent: Node3D, y_off: float) -> void:
	# Plain floor plate sized to this building's footprint
	var cx := _footprint.x * 0.5
	var cz := 0.0
	_slab(parent,
		Vector3(cx, y_off - 0.10, cz),
		Vector3(_footprint.x, 0.20, _footprint.y),
		Color(0.76, 0.74, 0.70))


func _generate_vertical_connections(vc_list: Array) -> void:
	for vc in vc_list:
		var vp          = vc.get("pos", [50, 0, 0])
		var x: float    = float(vp[0])
		var z: float    = float(vp[2])
		var fl: Array   = vc.get("connects_floors", [])
		for fi in fl:
			var fn: Node3D = _get_floor_node(fi)
			if fn == null:
				continue
			var y: float = fi * _floor_height
			# Grey stairwell box visible at each connected floor level
			_slab(fn, Vector3(x, y + 2.0, z), Vector3(4, 4, 4), STAIR_COLOR)
			# Small label
			var lbl       := Label3D.new()
			lbl.text       = "STAIRS"
			lbl.position   = Vector3(x, y + 4.5, z)
			lbl.billboard  = BaseMaterial3D.BILLBOARD_ENABLED
			lbl.font_size  = 6
			lbl.fixed_size = true
			lbl.modulate   = Color(0.9, 0.85, 0.7)
			fn.add_child(lbl)


func _get_floor_node(fi: int) -> Node3D:
	if fi >= 0 and fi < _floor_nodes.size():
		return _floor_nodes[fi]
	return null


func _build_entrance_marker() -> void:
	var mi  := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.height = 0.06; cyl.top_radius = 1.5; cyl.bottom_radius = 1.5
	mi.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color             = Color(0.0, 0.6, 1.0)
	mat.emission_enabled         = true
	mat.emission                 = Color(0.0, 0.3, 0.9)
	mat.emission_energy_multiplier = 1.2
	mi.material_override = mat
	mi.position = _entrance + Vector3(0, 0.03, 0)
	add_child(mi)

	var lbl       := Label3D.new()
	lbl.text       = "ENTRANCE"
	lbl.position   = _entrance + Vector3(0, 2.0, 0)
	lbl.billboard  = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.modulate   = Color(0.0, 0.6, 1.0)
	lbl.font_size  = 8
	lbl.fixed_size = true
	add_child(lbl)


func _slab(parent: Node3D, pos: Vector3, sz: Vector3, col: Color) -> void:
	var mi  := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = sz
	mi.mesh  = box
	var mat  := StandardMaterial3D.new()
	mat.albedo_color = col
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)


# ── Floor visibility ──────────────────────────────────────────────────────────

func set_active_floor(floor_index: int) -> void:
	_active_floor = floor_index
	for fi in range(_floor_nodes.size()):
		var fn: Node3D = _floor_nodes[fi]
		if fn == null:
			continue
		var is_active: bool = (fi == floor_index)
		var alpha: float    = 1.0 if is_active else 0.15
		_apply_alpha_to_floor(fn, alpha, is_active)

	# Update ray-pickability — only label hit-areas respond to clicks
	for room_id in _label_bodies:
		var fi_room: int = _get_room_floor(room_id)
		_label_bodies[room_id].input_ray_pickable = (fi_room == floor_index)


func _apply_alpha_to_floor(fn: Node3D, alpha: float, is_active: bool) -> void:
	_apply_alpha_recursive(fn, alpha, is_active)


func _apply_alpha_recursive(node: Node, alpha: float, is_active: bool) -> void:
	if node is MeshInstance3D:
		var mat = node.material_override
		if mat is StandardMaterial3D:
			var c: Color = mat.albedo_color
			c.a = alpha
			mat.albedo_color = c
			if is_active:
				mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			else:
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	elif node is Label3D:
		var c: Color = (node as Label3D).modulate
		c.a = 1.0 if is_active else 0.0
		(node as Label3D).modulate = c
	for child in node.get_children():
		_apply_alpha_recursive(child, alpha, is_active)


func _get_room_floor(room_id: String) -> int:
	for r in _all_rooms:
		if r["id"] == room_id:
			return int(r.get("floor_index", 0))
	return 0


# ── Input ──────────────────────────────────────────────────────────────────────

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
		var alpha: float = _room_mats[id].albedo_color.a
		var col: Color   = COLOR_SELECTED
		col.a     = alpha
		_room_mats[id].albedo_color = col


func clear_selection() -> void:
	if _selected_id != "" and _room_mats.has(_selected_id):
		var avail: bool   = _availability.get(_selected_id, true)
		var alpha: float  = _room_mats[_selected_id].albedo_color.a
		var col           := COLOR_AVAILABLE if avail else COLOR_OCCUPIED
		col.a             = alpha
		_room_mats[_selected_id].albedo_color = col
	_selected_id = ""


func update_room_availability(data: Dictionary) -> void:
	_availability.clear()
	for room_id in data:
		var avail: bool = data[room_id].get("available", true)
		_availability[room_id] = avail
		if _room_mats.has(room_id) and room_id != _selected_id:
			var alpha: float = _room_mats[room_id].albedo_color.a
			var col          := COLOR_AVAILABLE if avail else COLOR_OCCUPIED
			col.a            = alpha
			_room_mats[room_id].albedo_color = col


func get_room_data() -> Array:
	var result: Array = []
	for rd in _all_rooms:
		var d = rd.duplicate()
		d["available"] = _availability.get(rd["id"], true)
		result.append(d)
	return result


func get_floors() -> Array:
	var result: Array = []
	for fd in _floors_data:
		result.append({
			"index": int(fd.get("index", 0)),
			"name":  str(fd.get("name", "Floor %d" % int(fd.get("index", 0))))
		})
	return result


func get_entrance() -> Vector3:
	return _entrance
