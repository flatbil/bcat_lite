# room_labels.gd — screen-space room labels + structural overlays (RTS health-bar style)
#
# Each frame this node projects every active-floor room from 3D world space to
# screen coordinates, then runs a greedy collision pass: labels are placed top-
# to-bottom, and any label whose rect would overlap an already-placed one is
# hidden.  This is the same algorithm used by Google Maps / OSM renderers.
#
# Two label types:
#   • Room labels  — interactive (emit room_label_clicked), priority 1 (or 2 if selected)
#   • Overlays     — structural markers (ENTRANCE, STAIRS), non-interactive, priority 0
extends Control

signal room_label_clicked(room_id: String)

const FONT_SIZE   := 11
const OV_FONT     := 10    # overlay font size (slightly smaller)
const PAD_H       := 7
const PAD_V       := 3
const PIN_GAP     := 5.0   # px below label bottom to the projected world anchor
const OVERLAP_GAP := 4.0   # minimum clear gap between neighbouring rects

const C_BG   := Color(0.10, 0.10, 0.10, 0.80)
const C_SEL  := Color(0.20, 0.42, 0.90, 0.92)
const C_TEXT := Color(1.00, 1.00, 1.00, 1.00)
const C_OV_BG := Color(0.08, 0.08, 0.08, 0.65)   # overlay background

var _camera:       Camera3D   = null
var _rooms:        Array      = []       # room dicts — must contain "world_pos", "floor_index"
var _entries:      Dictionary = {}       # room_id → { panel, style, size }
var _active_floor: int        = 0
var _selected_id:  String     = ""

var _overlay_data:    Array      = []    # [{text, world_pos, floor_index, color}]
var _overlay_entries: Dictionary = {}    # "ov_N" → { panel, size, floor_index, world_pos }

# Placement is only recomputed when the camera actually moves or data changes,
# not on every frame — prevents jitter and unnecessary work.
var _last_cam_pos:   Vector3 = Vector3(1e9, 1e9, 1e9)
var _last_cam_basis: Basis   = Basis()
var _dirty:          bool    = true


# ── Public API ─────────────────────────────────────────────────────────────────

func setup(cam: Camera3D) -> void:
	_camera = cam
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_rooms(rooms: Array) -> void:
	_clear_all()
	_rooms = rooms
	for room in rooms:
		_make_entry(room)
	_dirty = true


func set_overlays(overlays: Array) -> void:
	# Remove old overlay panels without touching room labels.
	for key: String in _overlay_entries:
		(_overlay_entries[key]["panel"] as Control).queue_free()
	_overlay_entries.clear()
	_overlay_data = overlays
	var idx: int = 0
	for ov: Dictionary in _overlay_data:
		_make_overlay_entry("ov_%d" % idx, ov)
		idx += 1
	_dirty = true


func set_active_floor(fi: int) -> void:
	_active_floor = fi
	_dirty = true


func set_selected(room_id: String) -> void:
	if _selected_id == room_id:
		return
	_selected_id = room_id
	for id: String in _entries:
		(_entries[id]["style"] as StyleBoxFlat).bg_color = \
				C_SEL if id == _selected_id else C_BG
	_dirty = true


func clear_rooms() -> void:
	_clear_all()
	_rooms = []


# ── Private ────────────────────────────────────────────────────────────────────

func _clear_all() -> void:
	for c in get_children():
		c.queue_free()
	_entries.clear()
	_overlay_entries.clear()
	_overlay_data = []


func _make_entry(room: Dictionary) -> void:
	var id:   String = str(room["id"])
	var name: String = str(room.get("name", id))

	var sty := StyleBoxFlat.new()
	sty.bg_color                    = C_BG
	sty.corner_radius_top_left      = 4
	sty.corner_radius_top_right     = 4
	sty.corner_radius_bottom_left   = 4
	sty.corner_radius_bottom_right  = 4
	sty.content_margin_left   = float(PAD_H)
	sty.content_margin_right  = float(PAD_H)
	sty.content_margin_top    = float(PAD_V)
	sty.content_margin_bottom = float(PAD_V)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", sty)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.visible      = false

	var lbl := Label.new()
	lbl.text = name
	lbl.add_theme_font_size_override("font_size", FONT_SIZE)
	lbl.add_theme_color_override("font_color", C_TEXT)
	lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_child(lbl)

	panel.gui_input.connect(_on_panel_input.bind(id))
	add_child(panel)

	var font: Font    = ThemeDB.fallback_font
	var tsz:  Vector2 = font.get_string_size(
			name, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
	var sz: Vector2 = Vector2(tsz.x + float(PAD_H) * 2.0,
							  tsz.y + float(PAD_V) * 2.0)
	_entries[id] = {"panel": panel, "style": sty, "size": sz}


func _make_overlay_entry(key: String, ov: Dictionary) -> void:
	var text:  String  = str(ov.get("text", ""))
	var color: Color   = ov.get("color", Color(0.9, 0.85, 0.7))
	var fi:    int     = int(ov.get("floor_index", 0))
	var wp:    Vector3 = ov.get("world_pos", Vector3.ZERO)

	var sty := StyleBoxFlat.new()
	sty.bg_color                    = C_OV_BG
	sty.corner_radius_top_left      = 3
	sty.corner_radius_top_right     = 3
	sty.corner_radius_bottom_left   = 3
	sty.corner_radius_bottom_right  = 3
	sty.content_margin_left   = float(PAD_H - 2)
	sty.content_margin_right  = float(PAD_H - 2)
	sty.content_margin_top    = float(PAD_V - 1)
	sty.content_margin_bottom = float(PAD_V - 1)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", sty)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE   # not interactive
	panel.visible      = false

	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", OV_FONT)
	lbl.add_theme_color_override("font_color", color)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(lbl)
	add_child(panel)

	var font: Font    = ThemeDB.fallback_font
	var tsz:  Vector2 = font.get_string_size(
			text, HORIZONTAL_ALIGNMENT_LEFT, -1, OV_FONT)
	var sz: Vector2 = Vector2(tsz.x + float(PAD_H - 2) * 2.0,
							  tsz.y + float(PAD_V - 1) * 2.0)
	_overlay_entries[key] = {
		"panel":       panel,
		"size":        sz,
		"floor_index": fi,
		"world_pos":   wp,
	}


func _process(_delta: float) -> void:
	if _camera == null:
		return
	# Only re-run placement when the camera has moved/rotated or data changed.
	var pos_changed   := not _camera.global_position.is_equal_approx(_last_cam_pos)
	var basis_changed := not _camera.global_basis.is_equal_approx(_last_cam_basis)
	if not _dirty and not pos_changed and not basis_changed:
		return
	_last_cam_pos   = _camera.global_position
	_last_cam_basis = _camera.global_basis
	_dirty          = false
	_update_labels()


func _update_labels() -> void:

	# Hide everything; we re-show only successfully placed labels below.
	for id: String in _entries:
		(_entries[id]["panel"] as PanelContainer).visible = false
	for key: String in _overlay_entries:
		(_overlay_entries[key]["panel"] as PanelContainer).visible = false

	var vp: Rect2 = get_viewport_rect()

	# ── 1. Collect room candidates ───────────────────────────────────────────
	var cands: Array = []
	for room: Dictionary in _rooms:
		if int(room.get("floor_index", 0)) != _active_floor:
			continue
		var wp: Vector3 = room.get("world_pos", Vector3.ZERO)
		if _camera.is_position_behind(wp):
			continue
		var sp: Vector2 = _camera.unproject_position(wp)
		if not vp.has_point(sp):
			continue
		var id: String = str(room["id"])
		cands.append({"id": id, "sp": sp, "pri": 2 if id == _selected_id else 1,
					  "is_overlay": false})

	# ── 2. Collect overlay candidates (lower priority, placed after rooms) ───
	for key: String in _overlay_entries:
		var ov: Dictionary = _overlay_entries[key]
		if int(ov["floor_index"]) != _active_floor:
			continue
		var wp: Vector3 = ov["world_pos"]
		if _camera.is_position_behind(wp):
			continue
		var sp: Vector2 = _camera.unproject_position(wp)
		if not vp.has_point(sp):
			continue
		cands.append({"id": key, "sp": sp, "pri": 0, "is_overlay": true})

	# ── 3. Sort: priority desc, then top-to-bottom on screen ────────────────
	cands.sort_custom(_cand_sort)

	# ── 4. Greedy placement — skip anything that collides ───────────────────
	var placed: Array = []   # Array[Rect2]
	for c: Dictionary in cands:
		var id:    String     = c["id"]
		var entry: Dictionary = _overlay_entries.get(id, {}) \
				if c["is_overlay"] else _entries.get(id, {})
		if entry.is_empty():
			continue

		var sz:   Vector2 = entry["size"]
		var pos:  Vector2 = c["sp"] - Vector2(sz.x * 0.5, sz.y + PIN_GAP)
		var rect: Rect2   = Rect2(pos, sz)

		if not vp.grow(-2.0).encloses(rect):
			continue

		var ok: bool = true
		for pr: Rect2 in placed:
			if rect.grow(OVERLAP_GAP).intersects(pr):
				ok = false
				break

		if ok:
			(entry["panel"] as PanelContainer).position = pos
			(entry["panel"] as PanelContainer).visible  = true
			placed.append(rect)


func _cand_sort(a: Dictionary, b: Dictionary) -> bool:
	if a["pri"] != b["pri"]:
		return a["pri"] > b["pri"]
	return a["sp"].y < b["sp"].y


func _on_panel_input(event: InputEvent, room_id: String) -> void:
	var fired: bool = false
	if event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		fired = true
	elif event is InputEventScreenTouch and event.pressed:
		fired = true
	if fired:
		room_label_clicked.emit(room_id)
		get_viewport().set_input_as_handled()
