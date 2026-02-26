# tile_map.gd
# OpenStreetMap tiles streamed procedurally as the camera moves.
# Tiles within LOAD_R of the camera tile are loaded; tiles beyond UNLOAD_R
# are freed.  The viewport clear-colour fills any gap beyond the loaded area,
# so the user never sees the grey void regardless of how far they pan.
#
# Call setup() once per building load with the building's GPS anchor lat/lon
# and the world-space Vector3 that anchor maps to (typically the entrance).
#
# Tile math: Web Mercator / Slippy Map convention (EPSG:3857).
#   - Tile X increases eastward  → world +X
#   - Tile Y increases southward → world +Z
#   - UV (0,0) = NW corner, UV (1,1) = SE corner  (OSM standard)
#
# OSM tile usage policy: provide a descriptive User-Agent; do not hammer the
# servers. For production, self-host tiles (e.g. openstreetmap-tile-server).

class_name OsmTileMap
extends Node3D

const EARTH_R    := 6378137.0
const ZOOM       := 18
const LOAD_R     := 2          # load tiles within this radius of camera tile
const UNLOAD_R   := 4          # free tiles farther than this from camera tile
const TILE_Y     := -0.05      # metres below building floor
const OSM_URL    := "https://tile.openstreetmap.org/%d/%d/%d.png"
const USER_AGENT := "bcat_lite/1.0 (open-source indoor wayfinding demo)"
const POOL_SIZE  := 8          # concurrent HTTP requests

# GPS + projection state (populated by setup())
var _anchor_lat   := 0.0
var _anchor_lon   := 0.0
var _anchor_world := Vector3.ZERO
var _center_tx    := 0
var _center_ty    := 0
var _tile_m       := 0.0           # physical tile side-length in metres at this lat
var _frac         := Vector2.ZERO  # sub-tile fractional offset of GPS anchor

# Runtime state
var _tiles:    Dictionary         = {}   # "tx_ty" → MeshInstance3D
var _pool:     Array[HTTPRequest] = []
var _queue:    Array[Dictionary]  = []   # pending {tx, ty} to download
var _camera:   Camera3D           = null
var _cam_tile: Vector2i           = Vector2i(-999999, -999999)


func _ready() -> void:
	for _i in POOL_SIZE:
		var h := HTTPRequest.new()
		h.use_threads = true
		add_child(h)
		_pool.append(h)


## Call after a building is loaded.
##   lat / lon          – GPS anchor from campus.json
##   anchor_world_pos   – world-space position the anchor maps to
func setup(lat: float, lon: float, anchor_world_pos: Vector3) -> void:
	# Remove old tile meshes; leave HTTPRequest children in the pool
	for child in get_children():
		if child is MeshInstance3D:
			child.queue_free()
	_tiles.clear()
	_queue.clear()
	_cam_tile = Vector2i(-999999, -999999)

	_anchor_lat   = lat
	_anchor_lon   = lon
	_anchor_world = anchor_world_pos
	_tile_m       = _calc_tile_m(lat)
	_center_tx    = _lon_to_tx(lon)
	_center_ty    = _lat_to_ty(lat)
	_frac         = _calc_frac()

	# Every viewport pixel with no geometry (sky, horizon, beyond loaded tiles)
	# becomes the same warm grey as placeholder tiles — no geometry needed,
	# zero z-fighting.
	RenderingServer.set_default_clear_color(Color(0.88, 0.88, 0.86))

	# Seed initial load around the GPS anchor
	_load_around(_center_tx, _center_ty)


# ── Streaming update ──────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	if _tile_m <= 0.0:
		return
	# Lazy-fetch the active camera (tile_map doesn't need a direct reference)
	if _camera == null:
		_camera = get_viewport().get_camera_3d()
	if _camera == null:
		return

	var ct := _world_to_tile(_camera.global_position)
	if ct == _cam_tile:
		return   # camera hasn't crossed a tile boundary — nothing to do
	_cam_tile = ct
	_unload_far(ct)
	_load_around(ct.x, ct.y)


# Spawn placeholders and queue downloads for every tile within LOAD_R that
# isn't already in _tiles.
func _load_around(cx: int, cy: int) -> void:
	for dy in range(-LOAD_R, LOAD_R + 1):
		for dx in range(-LOAD_R, LOAD_R + 1):
			var tx  := cx + dx
			var ty  := cy + dy
			var key := _tile_key(tx, ty)
			if not _tiles.has(key):
				_spawn_placeholder(tx, ty)
				_queue.append({tx = tx, ty = ty})
	_pump()


# Free MeshInstances for tiles that are too far from the current camera tile.
func _unload_far(cam_tile: Vector2i) -> void:
	var to_remove: PackedStringArray = []
	for key: String in _tiles:
		var sep := key.find("_")
		var tx  := int(key.left(sep))
		var ty  := int(key.right(key.length() - sep - 1))
		if abs(tx - cam_tile.x) > UNLOAD_R or abs(ty - cam_tile.y) > UNLOAD_R:
			to_remove.append(key)
	for key: String in to_remove:
		(_tiles[key] as MeshInstance3D).queue_free()
		_tiles.erase(key)


# ── Web Mercator tile math ─────────────────────────────────────────────────────

func _calc_tile_m(lat: float) -> float:
	return 2.0 * PI * EARTH_R * cos(deg_to_rad(lat)) / pow(2.0, ZOOM)

func _lon_to_tx(lon: float) -> int:
	return int(floor((lon + 180.0) / 360.0 * pow(2.0, ZOOM)))

func _lat_to_ty(lat: float) -> int:
	var lr := deg_to_rad(lat)
	return int(floor((1.0 - log(tan(lr) + 1.0 / cos(lr)) / PI) / 2.0 * pow(2.0, ZOOM)))

# Fractional position of the GPS anchor within its containing tile [0, 1]
func _calc_frac() -> Vector2:
	var n  := pow(2.0, ZOOM)
	var fx := ((_anchor_lon + 180.0) / 360.0 * n) - float(_center_tx)
	var lr := deg_to_rad(_anchor_lat)
	var fy := ((1.0 - log(tan(lr) + 1.0 / cos(lr)) / PI) / 2.0 * n) - float(_center_ty)
	return Vector2(fx, fy)

# World-space centre of tile (tx, ty), lying at TILE_Y
func _tile_center(tx: int, ty: int) -> Vector3:
	var dx := (float(tx - _center_tx) - _frac.x + 0.5) * _tile_m
	var dz := (float(ty - _center_ty) - _frac.y + 0.5) * _tile_m
	return Vector3(_anchor_world.x + dx, TILE_Y, _anchor_world.z + dz)

# Convert a world-space XZ position to the tile coordinates it falls within.
func _world_to_tile(world_pos: Vector3) -> Vector2i:
	var dx := world_pos.x - _anchor_world.x
	var dz := world_pos.z - _anchor_world.z
	var tx := int(floor(float(_center_tx) + _frac.x + dx / _tile_m))
	var ty := int(floor(float(_center_ty) + _frac.y + dz / _tile_m))
	return Vector2i(tx, ty)

func _tile_key(tx: int, ty: int) -> String:
	return "%d_%d" % [tx, ty]


# ── Tile mesh management ───────────────────────────────────────────────────────

func _spawn_placeholder(tx: int, ty: int) -> void:
	var key := _tile_key(tx, ty)
	if _tiles.has(key):
		return

	var mi   := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(_tile_m, _tile_m)
	mi.mesh   = quad
	# QuadMesh default faces +Z; -90° around X lays it in XZ plane,
	# normal +Y, UV(0,0) at NW corner — matches OSM tile orientation.
	mi.rotation_degrees.x = -90.0
	mi.position           = _tile_center(tx, ty)

	var mat          := StandardMaterial3D.new()
	mat.albedo_color  = Color(0.88, 0.88, 0.86)   # warm grey placeholder
	mat.shading_mode  = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat

	add_child(mi)
	_tiles[key] = mi


# ── HTTP tile download pool ────────────────────────────────────────────────────

func _pump() -> void:
	for http: HTTPRequest in _pool:
		if _queue.is_empty():
			return
		if http.get_http_client_status() == HTTPClient.STATUS_DISCONNECTED:
			var item: Dictionary = _queue.pop_front()
			# Skip tiles that were unloaded while sitting in the queue
			if not _tiles.has(_tile_key(item.tx, item.ty)):
				continue
			http.request_completed.connect(
				_make_cb(item.tx, item.ty),
				CONNECT_ONE_SHOT
			)
			http.request(
				OSM_URL % [ZOOM, item.tx, item.ty],
				["User-Agent: " + USER_AGENT]
			)

func _make_cb(tx: int, ty: int) -> Callable:
	return func(result: int, code: int, _hdrs: PackedStringArray, body: PackedByteArray) -> void:
		_pump()   # start next queued tile on the now-idle node

		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			push_warning("tile_map: %d/%d/%d failed (result=%d http=%d)" \
				% [ZOOM, tx, ty, result, code])
			return

		var img := Image.new()
		if img.load_png_from_buffer(body) != OK:
			push_warning("tile_map: PNG decode failed %d/%d/%d" % [ZOOM, tx, ty])
			return

		var key := _tile_key(tx, ty)
		if not _tiles.has(key):
			return   # tile was unloaded while in flight

		var mat           := StandardMaterial3D.new()
		mat.albedo_texture = ImageTexture.create_from_image(img)
		mat.shading_mode   = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
		(_tiles[key] as MeshInstance3D).material_override = mat
