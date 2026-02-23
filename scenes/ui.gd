# ui.gd — all UI built in code
extends Control

signal navigate_requested(room_id: String)
signal navigation_cleared
signal room_info_requested(room_id: String)
signal joy_input(dir: Vector2)
signal sensor_mode_toggled(on: bool)
signal calibrate_north_requested
signal reset_position_requested

var _room_data:      Array        = []
var _status_dots:    Dictionary   = {}   # room_id -> ColorRect
var _room_list:      VBoxContainer
var _nav_panel:      PanelContainer
var _dest_label:     Label
var _steps_label:    RichTextLabel
var _popup:          Control      = null
var _popup_backdrop: ColorRect    = null
var _popup_room_id:  String       = ""

# ── Location bar state ────────────────────────────────────────────────────────
var _sensor_btn:  Button = null
var _calib_btn:   Button = null
var _compass_lbl: Label  = null
var _sensor_on:   bool   = false

# ── Joystick state ────────────────────────────────────────────────────────────
var _joy_panel:  Control = null
var _joy_thumb:  Control = null
var _joy_active: bool    = false
var _joy_finger: int     = -1   # active touch index (-1 = none, -2 = mouse)
const _JOY_R    := 70.0         # max thumb travel from centre
const _JOY_DEAD := 5.0          # dead-zone radius
const _JOY_TR   := 30.0         # thumb half-size (thumb = 60 × 60 px)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # let touch events reach 3D viewport
	_build_left_panel()
	_build_nav_panel()
	_build_joystick()
	_build_location_bar()

# ── Left panel ────────────────────────────────────────────────────────────────

func _build_left_panel() -> void:
	var panel = PanelContainer.new()
	panel.name = "LeftPanel"
	panel.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	panel.custom_minimum_size = Vector2(300, 0)
	add_child(panel)

	var vbox = VBoxContainer.new()
	panel.add_child(vbox)

	var header = Label.new()
	header.text = "Rooms & Spaces"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var hs = StyleBoxFlat.new()
	hs.bg_color = Color(0.11, 0.20, 0.40)
	hs.content_margin_top = 10.0; hs.content_margin_bottom = 10.0
	hs.content_margin_left = 6.0; hs.content_margin_right = 6.0
	header.add_theme_stylebox_override("normal", hs)
	header.add_theme_color_override("font_color", Color.WHITE)
	header.add_theme_font_size_override("font_size", 18)
	vbox.add_child(header)

	var hint = Label.new()
	hint.text = "ℹ = schedule   Go = navigate"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.60, 0.60, 0.60))
	vbox.add_child(hint)

	vbox.add_child(HSeparator.new())

	var scroll = ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	_room_list = VBoxContainer.new()
	_room_list.name = "RoomList"
	_room_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_room_list)

# ── Right nav panel ───────────────────────────────────────────────────────────

func _build_nav_panel() -> void:
	_nav_panel = PanelContainer.new()
	_nav_panel.name = "NavPanel"
	_nav_panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	_nav_panel.custom_minimum_size = Vector2(240, 0)
	_nav_panel.visible = false
	add_child(_nav_panel)

	var vbox = VBoxContainer.new()
	_nav_panel.add_child(vbox)

	var nh = Label.new()
	nh.text = "Navigation"
	nh.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var nhs = StyleBoxFlat.new()
	nhs.bg_color = Color(0.08, 0.30, 0.12)
	nhs.content_margin_top = 10.0; nhs.content_margin_bottom = 10.0
	nh.add_theme_stylebox_override("normal", nhs)
	nh.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(nh)

	_dest_label = Label.new()
	_dest_label.text = "Destination: —"
	_dest_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_dest_label)

	_steps_label = RichTextLabel.new()
	_steps_label.bbcode_enabled = true
	_steps_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_steps_label.fit_content = true
	_steps_label.scroll_active = false
	vbox.add_child(_steps_label)

	var clear_btn = Button.new()
	clear_btn.text = "✕  Clear Route"
	clear_btn.pressed.connect(_on_clear_pressed)
	vbox.add_child(clear_btn)

# ── Public API ────────────────────────────────────────────────────────────────

func set_room_data(rooms: Array) -> void:
	_room_data = rooms
	_rebuild_room_list()

func _rebuild_room_list() -> void:
	if _room_list == null:
		return
	for child in _room_list.get_children():
		child.queue_free()
	_status_dots.clear()

	for room in _room_data:
		var id: String  = room["id"]
		var avail: bool = room.get("available", true)

		var row = HBoxContainer.new()
		row.name = "Row_" + id

		# Availability dot
		var dot = ColorRect.new()
		dot.custom_minimum_size = Vector2(12, 12)
		dot.color = Color.GREEN if avail else Color.RED
		_status_dots[id] = dot
		row.add_child(dot)

		# Name + capacity
		var info = Label.new()
		info.text = "%s (%d)" % [room["name"], room["capacity"]]
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_font_size_override("font_size", 14)
		row.add_child(info)

		# Info / schedule button
		var info_btn = Button.new()
		info_btn.text = "ℹ"
		info_btn.tooltip_text = "View schedule"
		info_btn.custom_minimum_size = Vector2(44, 44)
		info_btn.pressed.connect(_on_info_pressed.bind(id))
		row.add_child(info_btn)

		# Navigate button
		var go_btn = Button.new()
		go_btn.text = "Go"
		go_btn.custom_minimum_size = Vector2(50, 44)
		go_btn.pressed.connect(_on_go_pressed.bind(id))
		row.add_child(go_btn)

		_room_list.add_child(row)

func update_availability(data: Dictionary) -> void:
	for room_id in _status_dots:
		var avail = data.get(room_id, {}).get("available", true)
		_status_dots[room_id].color = Color.GREEN if avail else Color.RED

func show_navigation(room_id: String, points: Array) -> void:
	var room_name = room_id
	for r in _room_data:
		if r["id"] == room_id:
			room_name = r["name"]
			break
	_dest_label.text = "→  " + room_name
	_steps_label.text = _build_directions_bbcode(points)
	_nav_panel.visible = true

func clear_route() -> void:
	_nav_panel.visible = false
	_steps_label.text = ""

# ── Meeting popup ─────────────────────────────────────────────────────────────

func show_room_popup(room_id: String, room_data: Dictionary) -> void:
	_close_popup()
	_popup_room_id = room_id

	# Semi-transparent backdrop — clicking it closes the popup
	_popup_backdrop = ColorRect.new()
	_popup_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_popup_backdrop.color = Color(0, 0, 0, 0.42)
	_popup_backdrop.z_index = 9
	_popup_backdrop.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			_close_popup())
	add_child(_popup_backdrop)

	# Card panel
	var card = PanelContainer.new()
	card.z_index = 10
	card.custom_minimum_size = Vector2(340, 0)
	var card_style = StyleBoxFlat.new()
	card_style.bg_color = Color(0.09, 0.11, 0.17)
	card_style.corner_radius_top_left    = 8
	card_style.corner_radius_top_right   = 8
	card_style.corner_radius_bottom_left = 8
	card_style.corner_radius_bottom_right = 8
	card_style.content_margin_top    = 0.0
	card_style.content_margin_bottom = 0.0
	card_style.content_margin_left   = 0.0
	card_style.content_margin_right  = 0.0
	card.add_theme_stylebox_override("panel", card_style)
	# Centre the card
	card.anchor_left   = 0.5;  card.anchor_right  = 0.5
	card.anchor_top    = 0.5;  card.anchor_bottom = 0.5
	card.offset_left   = -170; card.offset_right  = 170
	card.offset_top    = -20;  card.offset_bottom = -20
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(card)
	_popup = card

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	card.add_child(vbox)

	# Header strip — green if available, red if in use
	var avail: bool = room_data.get("available", true)
	var hdr_bg = PanelContainer.new()
	var hbs = StyleBoxFlat.new()
	hbs.bg_color = Color(0.10, 0.36, 0.14) if avail else Color(0.38, 0.10, 0.10)
	hbs.corner_radius_top_left  = 8
	hbs.corner_radius_top_right = 8
	hbs.content_margin_top = 10.0; hbs.content_margin_bottom = 10.0
	hbs.content_margin_left = 14.0; hbs.content_margin_right = 14.0
	hdr_bg.add_theme_stylebox_override("panel", hbs)
	vbox.add_child(hdr_bg)

	var hdr_row = HBoxContainer.new()
	hdr_bg.add_child(hdr_row)

	var title_lbl = Label.new()
	title_lbl.text = room_data.get("name", room_id)
	title_lbl.add_theme_font_size_override("font_size", 18)
	title_lbl.add_theme_color_override("font_color", Color.WHITE)
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr_row.add_child(title_lbl)

	var close_btn = Button.new()
	close_btn.text = "✕"
	close_btn.flat = true
	close_btn.add_theme_color_override("font_color", Color.WHITE)
	close_btn.pressed.connect(_close_popup)
	hdr_row.add_child(close_btn)

	# Body with margin
	var body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 5)
	var body_margin = MarginContainer.new()
	body_margin.add_theme_constant_override("margin_left",   14)
	body_margin.add_theme_constant_override("margin_right",  14)
	body_margin.add_theme_constant_override("margin_top",    10)
	body_margin.add_theme_constant_override("margin_bottom", 14)
	body_margin.add_child(body)
	vbox.add_child(body_margin)

	# Status row
	var status_row = HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 8)
	body.add_child(status_row)

	var sdot = ColorRect.new()
	sdot.custom_minimum_size = Vector2(11, 11)
	sdot.color = Color(0.2, 0.9, 0.2) if avail else Color(0.9, 0.2, 0.2)
	status_row.add_child(sdot)

	var status_lbl = Label.new()
	status_lbl.text = ("● Available" if avail else "● In Use") + \
		"   ·   Capacity: %d" % room_data.get("capacity", 0)
	status_lbl.add_theme_color_override("font_color",
		Color(0.55, 1.0, 0.55) if avail else Color(1.0, 0.55, 0.55))
	status_lbl.add_theme_font_size_override("font_size", 12)
	status_row.add_child(status_lbl)

	body.add_child(HSeparator.new())

	var sched_hdr = Label.new()
	sched_hdr.text = "Today's Schedule"
	sched_hdr.add_theme_font_size_override("font_size", 13)
	sched_hdr.add_theme_color_override("font_color", Color(0.80, 0.82, 0.90))
	body.add_child(sched_hdr)

	var meetings: Array = room_data.get("meetings_today", [])
	if meetings.is_empty():
		var no_mtg = Label.new()
		no_mtg.text = "  No meetings scheduled today"
		no_mtg.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45))
		no_mtg.add_theme_font_size_override("font_size", 12)
		body.add_child(no_mtg)
	else:
		for mtg in meetings:
			var mrow = HBoxContainer.new()
			mrow.add_theme_constant_override("separation", 8)

			var time_lbl = Label.new()
			time_lbl.text = mtg.get("time", "")
			time_lbl.custom_minimum_size = Vector2(115, 0)
			time_lbl.add_theme_color_override("font_color", Color(0.65, 0.72, 0.95))
			time_lbl.add_theme_font_size_override("font_size", 12)
			mrow.add_child(time_lbl)

			var mtitle = Label.new()
			mtitle.text = mtg.get("title", "")
			mtitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			mtitle.add_theme_color_override("font_color", Color(0.88, 0.88, 0.88))
			mtitle.add_theme_font_size_override("font_size", 12)
			mtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			mrow.add_child(mtitle)

			body.add_child(mrow)

	body.add_child(HSeparator.new())

	# Navigate button
	var nav_btn = Button.new()
	nav_btn.text = "Navigate Here  →"
	nav_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav_btn.add_theme_font_size_override("font_size", 14)
	nav_btn.pressed.connect(_on_popup_navigate_pressed)
	body.add_child(nav_btn)

func _close_popup() -> void:
	if _popup_backdrop:
		_popup_backdrop.queue_free()
		_popup_backdrop = null
	if _popup:
		_popup.queue_free()
		_popup = null
	_popup_room_id = ""

func _on_popup_navigate_pressed() -> void:
	var rid = _popup_room_id
	_close_popup()
	navigate_requested.emit(rid)

# ── Direction helpers ─────────────────────────────────────────────────────────

func _build_directions_bbcode(points: Array) -> String:
	if points.size() < 2:
		return "[i]No route found.[/i]"
	var lines: Array[String] = []
	for i in range(points.size() - 1):
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		var dir  = b - a
		var dist = dir.length()
		lines.append("%d. Head %s  (%.1f m)" % [i + 1, _heading_name(dir), dist])
	lines.append("%d. Arrived ✓" % points.size())
	return "\n".join(lines)

func _heading_name(dir: Vector3) -> String:
	var angle = atan2(dir.x, dir.z) * 180.0 / PI
	if   angle >=  157.5 or angle < -157.5: return "north"
	elif angle >=  112.5:                   return "northeast"
	elif angle >=   67.5:                   return "east"
	elif angle >=   22.5:                   return "southeast"
	elif angle >=  -22.5:                   return "south"
	elif angle >=  -67.5:                   return "southwest"
	elif angle >= -112.5:                   return "west"
	else:                                   return "northwest"

# ── Button callbacks ──────────────────────────────────────────────────────────

func _on_info_pressed(room_id: String) -> void:
	room_info_requested.emit(room_id)

func _on_go_pressed(room_id: String) -> void:
	navigate_requested.emit(room_id)

func _on_clear_pressed() -> void:
	clear_route()
	navigation_cleared.emit()

# ── Location bar (sensor mode controls) ──────────────────────────────────────

func _build_location_bar() -> void:
	var panel = PanelContainer.new()
	panel.name = "LocationBar"
	# Anchor bottom-left, above the joystick dead-zone
	panel.anchor_left   = 0.0;  panel.anchor_right  = 0.0
	panel.anchor_top    = 1.0;  panel.anchor_bottom = 1.0
	panel.offset_left   = 4;    panel.offset_right  = 360
	panel.offset_top    = -140; panel.offset_bottom = -16
	var ps = StyleBoxFlat.new()
	ps.bg_color = Color(0.08, 0.10, 0.18, 0.88)
	ps.corner_radius_top_left    = 6
	ps.corner_radius_top_right   = 6
	ps.corner_radius_bottom_left = 6
	ps.corner_radius_bottom_right = 6
	ps.content_margin_top    = 6.0
	ps.content_margin_bottom = 6.0
	ps.content_margin_left   = 8.0
	ps.content_margin_right  = 8.0
	panel.add_theme_stylebox_override("panel", ps)
	add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	# Button row
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	vbox.add_child(hbox)

	_sensor_btn = Button.new()
	_sensor_btn.text = "📍 Sensor OFF"
	_sensor_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sensor_btn.add_theme_font_size_override("font_size", 14)
	_sensor_btn.custom_minimum_size = Vector2(0, 52)
	_sensor_btn.pressed.connect(_on_sensor_btn_pressed)
	hbox.add_child(_sensor_btn)

	_calib_btn = Button.new()
	_calib_btn.text = "⊙ Calibrate ↑"
	_calib_btn.disabled = true
	_calib_btn.add_theme_font_size_override("font_size", 14)
	_calib_btn.custom_minimum_size = Vector2(0, 52)
	_calib_btn.pressed.connect(func() -> void: calibrate_north_requested.emit())
	hbox.add_child(_calib_btn)

	var reset_btn = Button.new()
	reset_btn.text = "⌂ Reset"
	reset_btn.add_theme_font_size_override("font_size", 14)
	reset_btn.custom_minimum_size = Vector2(0, 52)
	reset_btn.pressed.connect(func() -> void: reset_position_requested.emit())
	hbox.add_child(reset_btn)

	# Compass label
	_compass_lbl = Label.new()
	_compass_lbl.text = "Compass: —"
	_compass_lbl.add_theme_font_size_override("font_size", 13)
	_compass_lbl.add_theme_color_override("font_color", Color(0.65, 0.70, 0.90))
	vbox.add_child(_compass_lbl)

func _on_sensor_btn_pressed() -> void:
	_sensor_on = not _sensor_on
	_sensor_btn.text = "📍 Sensor ON" if _sensor_on else "📍 Sensor OFF"
	_calib_btn.disabled = not _sensor_on
	if not _sensor_on:
		_compass_lbl.text = "Compass: —"
	sensor_mode_toggled.emit(_sensor_on)

func update_compass(deg: float) -> void:
	if _compass_lbl:
		_compass_lbl.text = "Compass: %.1f°" % deg

# ── Virtual joystick ──────────────────────────────────────────────────────────

func _build_joystick() -> void:
	# Outer base — 110 × 110 px, positioned bottom-right clear of the nav panel
	var base = Control.new()
	base.name = "JoyBase"
	base.anchor_left   = 1.0;  base.anchor_right  = 1.0
	base.anchor_top    = 1.0;  base.anchor_bottom = 1.0
	base.offset_left   = -470; base.offset_right  = -310
	base.offset_top    = -185; base.offset_bottom = -25
	base.mouse_filter  = Control.MOUSE_FILTER_STOP
	_joy_panel = base
	add_child(base)

	# Outer ring (circle illusion via fully-rounded StyleBox)
	var ring = PanelContainer.new()
	ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ring.mouse_filter = Control.MOUSE_FILTER_PASS
	var rs = StyleBoxFlat.new()
	rs.bg_color = Color(0.15, 0.15, 0.15, 0.55)
	rs.corner_radius_top_left    = 80
	rs.corner_radius_top_right   = 80
	rs.corner_radius_bottom_left = 80
	rs.corner_radius_bottom_right = 80
	ring.add_theme_stylebox_override("panel", rs)
	base.add_child(ring)

	# "MOVE" hint label inside the ring
	var hint = Label.new()
	hint.text = "MOVE"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.vertical_alignment   = VERTICAL_ALIGNMENT_BOTTOM
	hint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hint.offset_bottom = -6
	hint.add_theme_font_size_override("font_size", 9)
	hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 0.7))
	hint.mouse_filter = Control.MOUSE_FILTER_PASS
	base.add_child(hint)

	# Thumb circle
	var thumb = PanelContainer.new()
	thumb.custom_minimum_size = Vector2(_JOY_TR * 2, _JOY_TR * 2)
	thumb.mouse_filter = Control.MOUSE_FILTER_PASS
	var ts = StyleBoxFlat.new()
	ts.bg_color = Color(0.85, 0.85, 0.85, 0.85)
	ts.corner_radius_top_left    = int(_JOY_TR)
	ts.corner_radius_top_right   = int(_JOY_TR)
	ts.corner_radius_bottom_left = int(_JOY_TR)
	ts.corner_radius_bottom_right = int(_JOY_TR)
	thumb.add_theme_stylebox_override("panel", ts)
	_joy_thumb = thumb
	base.add_child(thumb)

	_reset_joy()
	base.gui_input.connect(_on_joy_gui_input)

# Handle mouse events (desktop + emulated touch on desktop)
func _on_joy_gui_input(event: InputEvent) -> void:
	var center := Vector2(80.0, 80.0)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and _joy_finger == -1:
			_joy_finger = -2   # mouse sentinel
			_joy_active = true
			_update_joy(event.position - center)
		elif not event.pressed and _joy_finger == -2:
			_joy_finger = -1
			_joy_active = false
			_reset_joy()
	elif event is InputEventMouseMotion and _joy_active and _joy_finger == -2:
		_update_joy(event.position - center)


# Handle real screen-touch events (Android)
func _input(event: InputEvent) -> void:
	if _joy_panel == null:
		return
	var rect   := _joy_panel.get_global_rect()
	var center := rect.position + Vector2(80.0, 80.0)
	if event is InputEventScreenTouch:
		if event.pressed and _joy_finger == -1 and rect.has_point(event.position):
			_joy_finger = event.index
			_joy_active = true
			_update_joy(event.position - center)
			get_viewport().set_input_as_handled()
		elif not event.pressed and event.index == _joy_finger:
			_joy_finger = -1
			_joy_active = false
			_reset_joy()
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index == _joy_finger:
		_update_joy(event.position - center)
		get_viewport().set_input_as_handled()

func _update_joy(delta: Vector2) -> void:
	var clamped := delta.limit_length(_JOY_R - _JOY_TR)
	var c55     := Vector2(80.0, 80.0)
	_joy_thumb.position = c55 + clamped - Vector2(_JOY_TR, _JOY_TR)
	var dir := clamped / (_JOY_R - _JOY_TR) if clamped.length() > _JOY_DEAD else Vector2.ZERO
	joy_input.emit(dir)

func _reset_joy() -> void:
	if _joy_thumb:
		_joy_thumb.position = Vector2(80.0 - _JOY_TR, 80.0 - _JOY_TR)
	joy_input.emit(Vector2.ZERO)
