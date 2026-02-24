# navigator.gd — Unified multi-floor A* navigation
extends Node

var _coords:        Dictionary = {}   # node_id -> [x, y, z]
var _graph:         Dictionary = {}   # node_id -> [neighbor_id, ...]
var _room_node_map: Dictionary = {}   # room_id -> node_id
var _floor_height:  float      = 4.0


func load_building_graph(building_data: Dictionary) -> void:
	_coords.clear()
	_graph.clear()
	_room_node_map.clear()
	_floor_height = float(building_data.get("floor_height", 4.0))

	var floors: Array  = building_data.get("floors", [])
	var vc_list: Array = building_data.get("vertical_connections", [])

	# ── 1. Load each floor with "f{index}_" prefix ────────────────────────────
	for floor_dict in floors:
		var fi: int      = int(floor_dict.get("index", 0))
		var y_off: float = fi * _floor_height
		var prefix       := "f%d_" % fi

		var nav: Dictionary    = floor_dict.get("nav", {})
		var nodes: Dictionary  = nav.get("nodes", {})
		var edges: Dictionary  = nav.get("edges", {})
		var rnm: Dictionary    = nav.get("room_node_map", {})

		for nid in nodes:
			var c            = nodes[nid]
			var pnid: String = prefix + nid
			_coords[pnid] = [float(c[0]), y_off + float(c[1]), float(c[2])]
			if not _graph.has(pnid):
				_graph[pnid] = []

		for nid in edges:
			var pnid: String = prefix + nid
			if not _graph.has(pnid):
				_graph[pnid] = []
			for nbr in edges[nid]:
				var pnbr: String = prefix + nbr
				if not _graph[pnid].has(pnbr):
					_graph[pnid].append(pnbr)

		for room_id in rnm:
			_room_node_map[room_id] = prefix + rnm[room_id]

	# ── 2. Add vertical connection nodes and inter/intra-floor edges ──────────
	for vc in vc_list:
		var vc_id: String       = vc["id"]
		var vp                  = vc.get("pos", [50, 0, 0])
		var x: float            = float(vp[0])
		var z: float            = float(vp[2])
		var connected: Array    = vc.get("connects_floors", [])

		# Create one node per connected floor
		var vc_nids: Array = []
		for fi in connected:
			var y: float = fi * _floor_height
			var nid      := "vc_%s_%d" % [vc_id, fi]
			_coords[nid] = [x, y, z]
			if not _graph.has(nid):
				_graph[nid] = []
			vc_nids.append(nid)

		# Inter-floor edges (consecutive pairs)
		for i in range(vc_nids.size() - 1):
			var a: String = vc_nids[i]
			var b: String = vc_nids[i + 1]
			if not _graph[a].has(b):
				_graph[a].append(b)
			if not _graph[b].has(a):
				_graph[b].append(a)

		# Auto-connect each vc node to the 2 nearest hallway nodes on its floor
		for fi in connected:
			var nid    := "vc_%s_%d" % [vc_id, fi]
			var prefix := "f%d_" % fi
			var candidates := _get_nodes_by_prefix(prefix)
			var nearest    := _find_n_nearest(nid, candidates, 2)
			for nbr in nearest:
				if not _graph[nid].has(nbr):
					_graph[nid].append(nbr)
				if not _graph[nbr].has(nid):
					_graph[nbr].append(nid)


# ── A* ─────────────────────────────────────────────────────────────────────────

func route_to_room(from_pos: Vector3, room_id: String) -> Array:
	if not _room_node_map.has(room_id):
		return []
	var start_node := find_nearest_node(from_pos)
	var end_node: String = _room_node_map[room_id]
	return find_route_between_nodes(start_node, end_node)


func find_route_between_nodes(start_node: String, end_node: String) -> Array:
	if not _graph.has(start_node) or not _graph.has(end_node):
		return []

	var open:      Array      = []
	var came_from: Dictionary = {}
	var gscore:    Dictionary = {}
	var fscore:    Dictionary = {}

	for k in _graph.keys():
		gscore[k] = 1e9
		fscore[k] = 1e9
	gscore[start_node] = 0.0
	fscore[start_node] = _heuristic(start_node, end_node)
	open.append(start_node)

	while open.size() > 0:
		open.sort_custom(func(a: String, b: String) -> bool: return fscore[a] < fscore[b])
		var current: String = open[0]
		if current == end_node:
			return _reconstruct_path(came_from, current)
		open.remove_at(0)
		for neighbor in _graph[current]:
			if not gscore.has(neighbor):
				gscore[neighbor] = 1e9
				fscore[neighbor] = 1e9
			var tentative: float = gscore[current] + _dist_between(current, neighbor)
			if tentative < gscore[neighbor]:
				came_from[neighbor] = current
				gscore[neighbor]    = tentative
				fscore[neighbor]    = tentative + _heuristic(neighbor, end_node)
				if neighbor not in open:
					open.append(neighbor)
	return []


func _reconstruct_path(came_from: Dictionary, current: String) -> Array:
	var total := [current]
	while came_from.has(current):
		current = came_from[current]
		total.insert(0, current)
	var pts: Array = []
	for n in total:
		var c = _coords[n]
		pts.append(Vector3(c[0], c[1], c[2]))
	return pts


func _heuristic(a: String, b: String) -> float:
	return _dist_between(a, b)


func _dist_between(a: String, b: String) -> float:
	var pa = _coords[a]
	var pb = _coords[b]
	return Vector3(pa[0], pa[1], pa[2]).distance_to(Vector3(pb[0], pb[1], pb[2]))


func find_nearest_node(pos: Vector3) -> String:
	var best  := ""
	var bestd := 1e9
	for k in _coords.keys():
		var c = _coords[k]
		var d := Vector3(c[0], c[1], c[2]).distance_to(pos)
		if d < bestd:
			bestd = d
			best  = k
	return best


# ── Helpers ───────────────────────────────────────────────────────────────────

func _get_nodes_by_prefix(prefix: String) -> Array:
	var result: Array = []
	for nid in _coords:
		if nid.begins_with(prefix):
			result.append(nid)
	return result


func _find_n_nearest(from_nid: String, candidates: Array, n: int) -> Array:
	var pc = _coords[from_nid]
	var pv := Vector3(pc[0], pc[1], pc[2])
	var sorted := candidates.duplicate()
	sorted.sort_custom(func(a: String, b: String) -> bool:
		var ca = _coords[a]
		var cb = _coords[b]
		return pv.distance_to(Vector3(ca[0], ca[1], ca[2])) < \
			   pv.distance_to(Vector3(cb[0], cb[1], cb[2]))
	)
	return sorted.slice(0, mini(n, sorted.size()))
