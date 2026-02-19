# navigator.gd
extends Node

var graph = {}
var coords = {}
var room_node_map = {}

func _ready():
	load_graph("res://assets/nav_graph.json")

func load_graph(path: String):
	var res = FileAccess.open(path, FileAccess.READ)
	if res:
		var txt = res.get_as_text()
		res.close()
		var root = JSON.parse_string(txt)
		if root != null:
			coords = root["nodes"]
			graph = root["edges"]
			if root.has("room_node_map"):
				room_node_map = root["room_node_map"]
		else:
			push_error("Invalid nav_graph JSON")

# A* on the nav graph
func find_route_between_nodes(start_node: String, end_node: String) -> Array:
	if not graph.has(start_node) or not graph.has(end_node):
		return []
	var open = []
	var came_from = {}
	var gscore = {}
	var fscore = {}
	for k in graph.keys():
		gscore[k] = 1e9
		fscore[k] = 1e9
	gscore[start_node] = 0
	fscore[start_node] = heuristic(start_node, end_node)
	open.append(start_node)
	while open.size() > 0:
		open.sort_custom(func(a, b): return fscore[a] < fscore[b])
		var current = open[0]
		if current == end_node:
			return reconstruct_path(came_from, current)
		open.remove_at(0)
		for neighbor in graph[current]:
			var tentative = gscore[current] + distance_between(current, neighbor)
			if tentative < gscore[neighbor]:
				came_from[neighbor] = current
				gscore[neighbor] = tentative
				fscore[neighbor] = tentative + heuristic(neighbor, end_node)
				if neighbor not in open:
					open.append(neighbor)
	return []

func reconstruct_path(came_from: Dictionary, current: String) -> Array:
	var total = [current]
	while came_from.has(current):
		current = came_from[current]
		total.insert(0, current)
	var pts = []
	for n in total:
		var c = coords[n]
		pts.append(Vector3(c[0], c[1], c[2]))
	return pts

func heuristic(a: String, b: String) -> float:
	return distance_between(a, b)

func distance_between(a: String, b: String) -> float:
	var pa = coords[a]
	var pb = coords[b]
	return Vector3(pa[0], pa[1], pa[2]).distance_to(Vector3(pb[0], pb[1], pb[2]))

func route_to_room(from_pos: Vector3, room_id: String) -> Array:
	if not room_node_map.has(room_id):
		return []
	var start_node = find_nearest_node(from_pos)
	var end_node = room_node_map[room_id]
	return find_route_between_nodes(start_node, end_node)

func find_nearest_node(pos: Vector3) -> String:
	var best = ""
	var bestd = 1e9
	for k in coords.keys():
		var c = coords[k]
		var d = Vector3(c[0], c[1], c[2]).distance_to(pos)
		if d < bestd:
			bestd = d
			best = k
	return best
