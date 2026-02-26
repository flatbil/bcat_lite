# ui.gd — Google Maps-style UI (dark theme)
# 3-state bottom drawer: HOME → LIST → DETAIL
# Public API (signals + methods) is identical to the old version so main.gd is unchanged.

extends Control

# ── Signals ───────────────────────────────────────────────────────────────────
signal navigate_requested(room_id: String)
signal navigation_cleared
signal room_info_requested(room_id: String)
signal joy_input(dir: Vector2)
signal sensor_mode_toggled(on: bool)
signal calibrate_north_requested
signal reset_position_requested
signal building_selected(building_id: String)
signal floor_selected(floor_index: int)
signal recenter_requested

# ── Theme ─────────────────────────────────────────────────────────────────────
const C_BG     := Color(0.165, 0.165, 0.165)   # #2a2a2a  panel bg
const C_BG2    := Color(0.227, 0.227, 0.227)   # #3a3a3a  row hover
const C_HDR    := Color(0.133, 0.133, 0.133)   # #222222  top-bar / section
const C_TEXT   := Color(1.0,   1.0,   1.0  )   # white
const C_SUB    := Color(0.67,  0.67,  0.67 )   # #aaaaaa  muted
const C_ACCENT := Color(0.0,   0.659, 0.910)   # #00a8e8  blue
const C_GO     := Color(0.298, 0.686, 0.314)   # #4caf50  green
const C_BACK   := Color(0.333, 0.333, 0.333)   # #555555  back btn
const C_DIV    := Color(0.267, 0.267, 0.267)   # #444444  dividers

# ── Category definitions ──────────────────────────────────────────────────────
const CATS: Dictionary = {
	"food":     { "icon": "🍽",  "color": Color(0.898, 0.224, 0.208) },
	"coffee":   { "icon": "☕",  "color": Color(0.984, 0.549, 0.0  ) },
	"restroom": { "icon": "🚻",  "color": Color(0.118, 0.533, 0.898) },
	"gym":      { "icon": "🏀",  "color": Color(0.984, 0.549, 0.0  ) },
	"lab":      { "icon": "🔬",  "color": Color(0.263, 0.627, 0.278) },
	"library":  { "icon": "📚",  "color": Color(0.0,   0.541, 0.482) },
	"nurse":    { "icon": "⚕",   "color": Color(0.898, 0.224, 0.208) },
	"fitness":  { "icon": "💪",  "color": Color(0.557, 0.141, 0.667) },
	"office":   { "icon": "🏢",  "color": Color(0.118, 0.533, 0.898) },
	"storage":  { "icon": "📦",  "color": Color(0.329, 0.431, 0.478) },
	"default":  { "icon": "📍",  "color": Color(0.459, 0.459, 0.459) },
}
const POPULAR_CATS := ["food", "coffee", "restroom", "nurse", "gym", "fitness"]

# ── State ─────────────────────────────────────────────────────────────────────
enum UiState { HOME, LIST, DETAIL }
var _state:           UiState    = UiState.HOME
var _current_room_id: String     = ""
var _room_data:       Array      = []
var _availability:    Dictionary = {}
var _floors_data:     Array      = []
var _active_floor:    int        = 0
var _building_ids:    Array      = []
var _search_text:     String     = ""
var _status_dots:     Dictionary = {}   # room_id → ColorRect

# ── Node refs ─────────────────────────────────────────────────────────────────
var _top_bar:       PanelContainer  = null
var _back_btn:      Button          = null
var _title_lbl:     Label           = null
var _search_field:  LineEdit        = null
var _bld_picker:    OptionButton    = null
var _floor_strip:   HBoxContainer   = null
var _floor_btns:    Array           = []

var _home_panel:    PanelContainer  = null
var _list_panel:    PanelContainer  = null
var _detail_panel:  PanelContainer  = null
var _room_list_vb:  VBoxContainer   = null

var _det_name_lbl:  Label           = null
var _det_floor_lbl: Label           = null
var _det_eta_lbl:   Label           = null
var _det_facts_lbl: Label           = null

var _menu_btn:      Button          = null
var _dropdown:      PanelContainer  = null
var _sensor_btn:    Button          = null
var _calib_btn:     Button          = null
var _compass_lbl:   Label           = null
var _sensor_on:     bool            = false
var _orient_btn:    Button          = null
var _is_portrait:   bool            = true

var _joy_panel:     Control         = null
var _joy_thumb:     Control         = null
var _joy_active:    bool            = false
var _joy_finger:    int             = -1

const _JOY_R    := 70.0
const _JOY_DEAD := 5.0
const _JOY_TR   := 30.0


# ── Bootstrap ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_top_bar()
	_build_home_panel()
	_build_list_panel()
	_build_detail_panel()
	_build_dropdown()
	_build_joystick()
	_build_recenter_btn()
	_set_state(UiState.HOME)


# ── Top bar ───────────────────────────────────────────────────────────────────

func _build_top_bar() -> void:
	_top_bar = PanelContainer.new()
	_top_bar.name = "TopBar"
	_top_bar.anchor_left   = 0.0;  _top_bar.anchor_right  = 1.0
	_top_bar.anchor_top    = 0.0;  _top_bar.anchor_bottom = 0.0
	_top_bar.offset_bottom = 108
	_top_bar.add_theme_stylebox_override("panel", _flat(C_HDR, 0))
	add_child(_top_bar)

	var outer := MarginContainer.new()
	outer.add_theme_constant_override("margin_left",   8)
	outer.add_theme_constant_override("margin_right",  8)
	outer.add_theme_constant_override("margin_top",    6)
	outer.add_theme_constant_override("margin_bottom", 4)
	_top_bar.add_child(outer)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	outer.add_child(vbox)

	# Row 1 — navigation controls
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 6)
	row1.custom_minimum_size = Vector2(0, 48)
	vbox.add_child(row1)

	_back_btn = Button.new()
	_back_btn.text = "←"
	_back_btn.custom_minimum_size = Vector2(48, 48)
	_back_btn.add_theme_font_size_override("font_size", 26)
	_back_btn.add_theme_stylebox_override("normal",  _flat(C_BACK, 6))
	_back_btn.add_theme_stylebox_override("hover",   _flat(C_BACK.lightened(0.2), 6))
	_back_btn.add_theme_stylebox_override("pressed", _flat(C_BACK.darkened(0.1), 6))
	_back_btn.add_theme_stylebox_override("focus",   _flat(C_BACK, 6))
	_back_btn.add_theme_color_override("font_color", C_TEXT)
	_back_btn.pressed.connect(_on_back_pressed)
	row1.add_child(_back_btn)

	_title_lbl = Label.new()
	_title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_lbl.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
	_title_lbl.add_theme_font_size_override("font_size", 20)
	_title_lbl.add_theme_color_override("font_color", C_TEXT)
	row1.add_child(_title_lbl)

	_search_field = LineEdit.new()
	_search_field.placeholder_text = "🔍  Search destinations..."
	_search_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_field.custom_minimum_size = Vector2(0, 44)
	_search_field.add_theme_font_size_override("font_size", 18)
	_search_field.text_changed.connect(_on_search_changed)
	row1.add_child(_search_field)

	_menu_btn = Button.new()
	_menu_btn.text = "☰"
	_menu_btn.custom_minimum_size = Vector2(48, 44)
	_menu_btn.add_theme_font_size_override("font_size", 24)
	_menu_btn.add_theme_stylebox_override("normal",  _flat(C_BACK, 6))
	_menu_btn.add_theme_stylebox_override("hover",   _flat(C_BACK.lightened(0.2), 6))
	_menu_btn.add_theme_stylebox_override("pressed", _flat(C_BACK.darkened(0.1), 6))
	_menu_btn.add_theme_stylebox_override("focus",   _flat(C_BACK, 6))
	_menu_btn.add_theme_color_override("font_color", C_TEXT)
	_menu_btn.pressed.connect(_on_menu_btn_pressed)
	row1.add_child(_menu_btn)

	# Row 2 — floor tab strip
	_floor_strip = HBoxContainer.new()
	_floor_strip.name = "FloorStrip"
	_floor_strip.add_theme_constant_override("separation", 4)
	_floor_strip.custom_minimum_size = Vector2(0, 32)
	vbox.add_child(_floor_strip)


# ── HOME panel ────────────────────────────────────────────────────────────────

func _build_home_panel() -> void:
	_home_panel = PanelContainer.new()
	_home_panel.name = "HomePanel"
	_home_panel.anchor_left   = 0.0;  _home_panel.anchor_right  = 1.0
	_home_panel.anchor_top    = 1.0;  _home_panel.anchor_bottom = 1.0
	_home_panel.offset_top    = -72;  _home_panel.offset_bottom = 0
	_home_panel.add_theme_stylebox_override("panel", _flat(C_BG, 0))
	add_child(_home_panel)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 1)
	_home_panel.add_child(hbox)

	var dest_btn := _tab_button("🗺  Common Destinations")
	dest_btn.pressed.connect(func() -> void: _set_state(UiState.LIST))
	hbox.add_child(dest_btn)

	hbox.add_child(_v_sep())

	var saved_btn := _tab_button("⭐  Saved")
	hbox.add_child(saved_btn)


func _tab_button(label: String) -> Button:
	var b := Button.new()
	b.text = label
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size   = Vector2(0, 64)
	b.add_theme_font_size_override("font_size", 17)
	b.add_theme_stylebox_override("normal",  _flat(C_BG2, 0))
	b.add_theme_stylebox_override("hover",   _flat(C_BG2.lightened(0.12), 0))
	b.add_theme_stylebox_override("pressed", _flat(C_BG2.darkened(0.08), 0))
	b.add_theme_stylebox_override("focus",   _flat(C_BG2, 0))
	b.add_theme_color_override("font_color", C_TEXT)
	return b


# ── LIST panel ────────────────────────────────────────────────────────────────

func _build_list_panel() -> void:
	_list_panel = PanelContainer.new()
	_list_panel.name = "ListPanel"
	_list_panel.anchor_left   = 0.0;  _list_panel.anchor_right  = 1.0
	_list_panel.anchor_top    = 0.38; _list_panel.anchor_bottom = 1.0
	_list_panel.visible       = false
	_list_panel.add_theme_stylebox_override("panel", _flat(C_BG, 0))
	add_child(_list_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	_list_panel.add_child(vbox)

	# Search bar inside list panel
	var search_margin := MarginContainer.new()
	search_margin.add_theme_constant_override("margin_left",   10)
	search_margin.add_theme_constant_override("margin_right",  10)
	search_margin.add_theme_constant_override("margin_top",    8)
	search_margin.add_theme_constant_override("margin_bottom", 6)
	vbox.add_child(search_margin)

	var list_search := LineEdit.new()
	list_search.placeholder_text = "🔍  Filter..."
	list_search.custom_minimum_size = Vector2(0, 38)
	list_search.add_theme_font_size_override("font_size", 17)
	list_search.text_changed.connect(_on_search_changed)
	search_margin.add_child(list_search)

	vbox.add_child(_h_sep())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	_room_list_vb = VBoxContainer.new()
	_room_list_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_room_list_vb.add_theme_constant_override("separation", 0)
	scroll.add_child(_room_list_vb)


# ── DETAIL panel ──────────────────────────────────────────────────────────────

func _build_detail_panel() -> void:
	_detail_panel = PanelContainer.new()
	_detail_panel.name = "DetailPanel"
	_detail_panel.anchor_left   = 0.0;  _detail_panel.anchor_right  = 1.0
	_detail_panel.anchor_top    = 1.0;  _detail_panel.anchor_bottom = 1.0
	_detail_panel.offset_top    = -234; _detail_panel.offset_bottom = 0
	_detail_panel.visible       = false
	var det_sty := _flat(C_BG, 0)
	det_sty.border_width_top = 2
	det_sty.border_color     = C_DIV
	_detail_panel.add_theme_stylebox_override("panel", det_sty)
	add_child(_detail_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	_detail_panel.add_child(vbox)

	# ── Rows 1 & 2 inside a margin ─────────────────────────────────────────
	var rows_wrap := MarginContainer.new()
	rows_wrap.add_theme_constant_override("margin_left",   14)
	rows_wrap.add_theme_constant_override("margin_right",  14)
	rows_wrap.add_theme_constant_override("margin_top",    10)
	rows_wrap.add_theme_constant_override("margin_bottom", 8)
	vbox.add_child(rows_wrap)

	var rows_vbox := VBoxContainer.new()
	rows_vbox.add_theme_constant_override("separation", 0)
	rows_wrap.add_child(rows_vbox)

	# Row 1 — star + name/floor
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 10)
	row1.custom_minimum_size = Vector2(0, 54)
	rows_vbox.add_child(row1)

	var fav_btn := Button.new()
	fav_btn.text = "☆"
	fav_btn.flat = true
	fav_btn.custom_minimum_size = Vector2(40, 40)
	fav_btn.add_theme_font_size_override("font_size", 31)
	fav_btn.add_theme_color_override("font_color", C_ACCENT)
	row1.add_child(fav_btn)

	var name_col := VBoxContainer.new()
	name_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_col.alignment = BoxContainer.ALIGNMENT_CENTER
	row1.add_child(name_col)

	_det_name_lbl = Label.new()
	_det_name_lbl.add_theme_font_size_override("font_size", 22)
	_det_name_lbl.add_theme_color_override("font_color", C_TEXT)
	_det_name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_col.add_child(_det_name_lbl)

	_det_floor_lbl = Label.new()
	_det_floor_lbl.add_theme_font_size_override("font_size", 14)
	_det_floor_lbl.add_theme_color_override("font_color", C_SUB)
	name_col.add_child(_det_floor_lbl)

	rows_vbox.add_child(_h_sep())

	# Row 2 — ETA | quick facts | save
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 0)
	row2.custom_minimum_size = Vector2(0, 48)
	rows_vbox.add_child(row2)

	var eta_box := HBoxContainer.new()
	eta_box.add_theme_constant_override("separation", 6)
	eta_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	eta_box.alignment = BoxContainer.ALIGNMENT_CENTER
	row2.add_child(eta_box)

	var walk_lbl := Label.new()
	walk_lbl.text = "🚶"
	walk_lbl.add_theme_font_size_override("font_size", 24)
	eta_box.add_child(walk_lbl)

	_det_eta_lbl = Label.new()
	_det_eta_lbl.text = "—"
	_det_eta_lbl.add_theme_font_size_override("font_size", 18)
	_det_eta_lbl.add_theme_color_override("font_color", C_TEXT)
	eta_box.add_child(_det_eta_lbl)

	row2.add_child(_v_sep())

	_det_facts_lbl = Label.new()
	_det_facts_lbl.text = "—"
	_det_facts_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_det_facts_lbl.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
	_det_facts_lbl.add_theme_font_size_override("font_size", 14)
	_det_facts_lbl.add_theme_color_override("font_color", C_SUB)
	row2.add_child(_det_facts_lbl)

	row2.add_child(_v_sep())

	var save_btn := Button.new()
	save_btn.text = "💾  Save"
	save_btn.flat = true
	save_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_btn.add_theme_font_size_override("font_size", 16)
	save_btn.add_theme_color_override("font_color", C_ACCENT)
	row2.add_child(save_btn)

	# ── Divider + full-width Go button ─────────────────────────────────────
	vbox.add_child(_h_sep())

	var go_btn := Button.new()
	go_btn.text = "  Go  →"
	go_btn.custom_minimum_size = Vector2(0, 58)
	go_btn.add_theme_font_size_override("font_size", 22)
	go_btn.add_theme_stylebox_override("normal",  _flat(C_GO, 0))
	go_btn.add_theme_stylebox_override("hover",   _flat(C_GO.lightened(0.1), 0))
	go_btn.add_theme_stylebox_override("pressed", _flat(C_GO.darkened(0.1), 0))
	go_btn.add_theme_stylebox_override("focus",   _flat(C_GO, 0))
	go_btn.add_theme_color_override("font_color", C_TEXT)
	go_btn.pressed.connect(_on_go_pressed)
	vbox.add_child(go_btn)


# ── Dropdown menu (☰ button) ──────────────────────────────────────────────────
# Contains: building picker + location/sensor controls.
# Drops down from top-bar right edge; z_index keeps it above all panels.

func _build_dropdown() -> void:
	_dropdown = PanelContainer.new()
	_dropdown.name = "DropdownMenu"
	_dropdown.anchor_left   = 1.0;  _dropdown.anchor_right  = 1.0
	_dropdown.anchor_top    = 0.0;  _dropdown.anchor_bottom = 0.0
	_dropdown.offset_left   = -280; _dropdown.offset_right  = 0
	_dropdown.offset_top    = 110;  _dropdown.offset_bottom = 110   # height set by content
	_dropdown.grow_vertical  = Control.GROW_DIRECTION_END
	_dropdown.z_index        = 20
	_dropdown.visible        = false
	var ds := _flat(C_HDR, 0)
	ds.border_width_left   = 1
	ds.border_width_bottom = 1
	ds.border_color        = C_DIV
	_dropdown.add_theme_stylebox_override("panel", ds)
	add_child(_dropdown)

	var outer := MarginContainer.new()
	outer.add_theme_constant_override("margin_left",   12)
	outer.add_theme_constant_override("margin_right",  12)
	outer.add_theme_constant_override("margin_top",    10)
	outer.add_theme_constant_override("margin_bottom", 12)
	_dropdown.add_child(outer)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	outer.add_child(vbox)

	# ── Building section ───────────────────────────────────────────────────
	var bld_lbl := Label.new()
	bld_lbl.text = "BUILDING"
	bld_lbl.add_theme_font_size_override("font_size", 13)
	bld_lbl.add_theme_color_override("font_color", C_SUB)
	vbox.add_child(bld_lbl)

	_bld_picker = OptionButton.new()
	_bld_picker.custom_minimum_size = Vector2(0, 40)
	_bld_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bld_picker.add_theme_font_size_override("font_size", 17)
	_bld_picker.item_selected.connect(_on_building_item_selected)
	vbox.add_child(_bld_picker)

	vbox.add_child(_h_sep())

	# ── Location section ───────────────────────────────────────────────────
	var loc_lbl := Label.new()
	loc_lbl.text = "LOCATION"
	loc_lbl.add_theme_font_size_override("font_size", 13)
	loc_lbl.add_theme_color_override("font_color", C_SUB)
	vbox.add_child(loc_lbl)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 6)
	vbox.add_child(btn_row)

	_sensor_btn = Button.new()
	_sensor_btn.text = "📍 Sensor OFF"
	_sensor_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sensor_btn.add_theme_font_size_override("font_size", 16)
	_sensor_btn.custom_minimum_size = Vector2(0, 40)
	_sensor_btn.pressed.connect(_on_sensor_btn_pressed)
	btn_row.add_child(_sensor_btn)

	_calib_btn = Button.new()
	_calib_btn.text = "⊙ Cal"
	_calib_btn.disabled = true
	_calib_btn.add_theme_font_size_override("font_size", 16)
	_calib_btn.custom_minimum_size = Vector2(0, 40)
	_calib_btn.pressed.connect(func() -> void: calibrate_north_requested.emit())
	btn_row.add_child(_calib_btn)

	var reset_btn := Button.new()
	reset_btn.text = "⌂"
	reset_btn.add_theme_font_size_override("font_size", 19)
	reset_btn.custom_minimum_size = Vector2(40, 40)
	reset_btn.pressed.connect(func() -> void: reset_position_requested.emit())
	btn_row.add_child(reset_btn)

	_compass_lbl = Label.new()
	_compass_lbl.text = "Compass: —"
	_compass_lbl.add_theme_font_size_override("font_size", 14)
	_compass_lbl.add_theme_color_override("font_color", Color(0.65, 0.70, 0.90))
	vbox.add_child(_compass_lbl)

	vbox.add_child(_h_sep())

	# ── Display section ────────────────────────────────────────────────────
	var disp_lbl := Label.new()
	disp_lbl.text = "DISPLAY"
	disp_lbl.add_theme_font_size_override("font_size", 13)
	disp_lbl.add_theme_color_override("font_color", C_SUB)
	vbox.add_child(disp_lbl)

	_orient_btn = Button.new()
	_orient_btn.text = "📱 Portrait  ✓"
	_orient_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_orient_btn.custom_minimum_size = Vector2(0, 40)
	_orient_btn.add_theme_font_size_override("font_size", 16)
	_orient_btn.pressed.connect(_toggle_orientation)
	vbox.add_child(_orient_btn)


# ── State machine ─────────────────────────────────────────────────────────────

func _set_state(new_state: UiState) -> void:
	_state = new_state

	var is_home   := (new_state == UiState.HOME)
	var is_list   := (new_state == UiState.LIST)
	var is_detail := (new_state == UiState.DETAIL)

	_dropdown.visible     = false   # always close dropdown on any state change
	_back_btn.visible     = not is_home
	_title_lbl.visible    = not is_home
	_search_field.visible = is_home

	_home_panel.visible   = is_home
	_list_panel.visible   = is_list
	_detail_panel.visible = is_detail

	if is_list:
		_title_lbl.text = "Common Destinations"


# ── Public API ────────────────────────────────────────────────────────────────

func set_building_list(buildings: Array) -> void:
	_bld_picker.clear()
	_building_ids.clear()
	for b in buildings:
		_bld_picker.add_item(b["display_name"])
		_building_ids.append(b["id"])


func set_floors(floors: Array, active_floor: int) -> void:
	_floors_data  = floors
	_active_floor = active_floor
	for child in _floor_strip.get_children():
		child.queue_free()
	_floor_btns.clear()

	for fd in floors:
		var fi: int = int(fd["index"])
		var btn     := Button.new()
		btn.text    = str(fd["name"])
		btn.add_theme_font_size_override("font_size", 14)
		btn.custom_minimum_size   = Vector2(0, 30)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_floor_btn_pressed.bind(fi))
		_floor_strip.add_child(btn)
		while _floor_btns.size() <= fi:
			_floor_btns.append(null)
		_floor_btns[fi] = btn

	_apply_floor_style(active_floor)
	_rebuild_room_list()


func set_active_floor(floor_index: int) -> void:
	_active_floor = floor_index
	_apply_floor_style(floor_index)
	_rebuild_room_list()


func set_room_data(rooms: Array) -> void:
	_room_data = rooms
	_rebuild_room_list()


func update_availability(data: Dictionary) -> void:
	_availability = data
	for room_id: String in _status_dots:
		var avail: bool = data.get(room_id, {}).get("available", true)
		(_status_dots[room_id] as ColorRect).color = Color.GREEN if avail else Color.RED


func show_room_popup(room_id: String, room_data: Dictionary) -> void:
	_show_detail(room_id, room_data)


func show_navigation(room_id: String, points: Array) -> void:
	if _det_eta_lbl:
		_det_eta_lbl.text = _calc_eta(points)
	if _state != UiState.DETAIL or _current_room_id != room_id:
		_show_detail(room_id)


func clear_route() -> void:
	if _det_eta_lbl:
		_det_eta_lbl.text = "—"


func on_map_deselect() -> void:
	if _state == UiState.DETAIL:
		_set_state(UiState.HOME)


func update_compass(deg: float) -> void:
	if _compass_lbl:
		_compass_lbl.text = "Compass: %.1f°" % deg


# ── Detail state helpers ──────────────────────────────────────────────────────

func _show_detail(room_id: String, data: Dictionary = {}) -> void:
	_current_room_id = room_id

	if data.is_empty():
		for r in _room_data:
			if r["id"] == room_id:
				data = r
				break

	var name_str: String = str(data.get("name", room_id))
	var fi:       int    = int(data.get("floor_index", 0))
	var cap:      int    = int(data.get("capacity", 0))
	var avail:    bool   = _availability.get(room_id, {}).get("available",
		data.get("available", true))

	var floor_name := ""
	for fd in _floors_data:
		if int(fd["index"]) == fi:
			floor_name = str(fd["name"])
			break
	if floor_name.is_empty():
		floor_name = "Floor %d" % fi

	_det_name_lbl.text  = name_str
	_title_lbl.text     = name_str
	_det_floor_lbl.text = floor_name
	_det_eta_lbl.text   = "—"

	var avail_str := "✅ Available" if avail else "🔴 In Use"
	var cap_str   := ("  ·  Cap %d" % cap) if cap > 0 else ""
	_det_facts_lbl.text = avail_str + cap_str

	_set_state(UiState.DETAIL)


# ── Room list builder ─────────────────────────────────────────────────────────

func _rebuild_room_list() -> void:
	if _room_list_vb == null:
		return
	for child in _room_list_vb.get_children():
		child.queue_free()
	_status_dots.clear()

	var floor_name_map: Dictionary = {}
	for fd in _floors_data:
		floor_name_map[int(fd["index"])] = str(fd["name"])

	var filter := _search_text.to_lower()
	var popular: Array = []
	var other:   Array = []

	for room in _room_data:
		var name_str: String = str(room.get("name", room["id"]))
		if filter != "" and not name_str.to_lower().contains(filter):
			continue
		var cat := _infer_category(name_str, str(room["id"]))
		if cat in POPULAR_CATS:
			popular.append(room)
		else:
			other.append(room)

	_add_section_header("Popular")
	for room in popular:
		_add_room_row(room, floor_name_map)

	if not other.is_empty():
		_add_section_header("Other")
		for room in other:
			_add_room_row(room, floor_name_map)


func _add_section_header(text: String) -> void:
	var bg := Panel.new()
	bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bg.mouse_filter = Control.MOUSE_FILTER_PASS
	bg.add_theme_stylebox_override("panel", _flat(C_HDR, 0))

	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left",   16)
	m.add_theme_constant_override("margin_top",    8)
	m.add_theme_constant_override("margin_bottom", 4)
	m.mouse_filter = Control.MOUSE_FILTER_PASS
	bg.add_child(m)

	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", C_SUB)
	lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	m.add_child(lbl)

	_room_list_vb.add_child(bg)


func _add_room_row(room: Dictionary, floor_name_map: Dictionary) -> void:
	var id:       String = str(room["id"])
	var name_str: String = str(room.get("name", id))
	var fi:       int    = int(room.get("floor_index", 0))
	var avail:    bool   = _availability.get(id, {}).get("available",
		room.get("available", true))
	var cat := _infer_category(name_str, id)

	# Full-width clickable button — MOUSE_FILTER_PASS lets drag events reach ScrollContainer
	var btn := Button.new()
	btn.text = ""
	btn.custom_minimum_size   = Vector2(0, 62)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.mouse_filter          = Control.MOUSE_FILTER_PASS
	btn.add_theme_stylebox_override("normal",  _flat(C_BG,  0))
	btn.add_theme_stylebox_override("hover",   _flat(C_BG2, 0))
	btn.add_theme_stylebox_override("pressed", _flat(C_BG.darkened(0.08), 0))
	btn.add_theme_stylebox_override("focus",   _flat(C_BG,  0))
	btn.pressed.connect(func() -> void: room_info_requested.emit(id))
	_room_list_vb.add_child(btn)

	# Content overlay — all children must MOUSE_FILTER_PASS so clicks reach button
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left",  12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.mouse_filter = Control.MOUSE_FILTER_PASS
	btn.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	margin.add_child(row)

	# Coloured emoji icon circle
	var icon := _make_icon(cat, 42.0)
	row.add_child(icon)

	# Name + floor badge
	var name_col := VBoxContainer.new()
	name_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_col.alignment   = BoxContainer.ALIGNMENT_CENTER
	name_col.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(name_col)

	var name_lbl := Label.new()
	name_lbl.text = name_str
	name_lbl.add_theme_font_size_override("font_size", 18)
	name_lbl.add_theme_color_override("font_color", C_TEXT)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	name_col.add_child(name_lbl)

	var fname: String = floor_name_map.get(fi, "Floor %d" % fi)
	var floor_lbl := Label.new()
	floor_lbl.text = fname
	floor_lbl.add_theme_font_size_override("font_size", 13)
	floor_lbl.add_theme_color_override("font_color",
		C_ACCENT if fi == _active_floor else C_SUB)
	floor_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	name_col.add_child(floor_lbl)

	# Availability dot
	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(10, 10)
	dot.color = Color.GREEN if avail else Color.RED
	dot.mouse_filter = Control.MOUSE_FILTER_PASS
	_status_dots[id] = dot
	row.add_child(dot)

	# Thin divider below row
	var div := Panel.new()
	div.custom_minimum_size = Vector2(0, 1)
	div.mouse_filter = Control.MOUSE_FILTER_PASS
	div.add_theme_stylebox_override("panel", _flat(C_DIV, 0))
	_room_list_vb.add_child(div)


# ── Category inference ────────────────────────────────────────────────────────

func _infer_category(room_name: String, room_id: String) -> String:
	var n := (room_name + " " + room_id).to_lower()
	if "cafe" in n or "cafeteria" in n or "food" in n or "lounge" in n or "kitchen" in n:
		return "food"
	if "coffee" in n:                                              return "coffee"
	if "restroom" in n or "bathroom" in n or "toilet" in n:       return "restroom"
	if "gym" in n or "gymnasium" in n:                            return "gym"
	if "lab" in n or "science" in n or "computer" in n:           return "lab"
	if "library" in n or "media" in n:                            return "library"
	if "nurse" in n or "medical" in n or "health" in n or "med_" in n: return "nurse"
	if "fitness" in n or "workout" in n:                          return "fitness"
	if "storage" in n or "custodial" in n or "delivery" in n:     return "storage"
	if "office" in n or "admin" in n or "visitor" in n \
			or "conf" in n or "seminar" in n or "assembly" in n:  return "office"
	return "default"


# ── ETA ───────────────────────────────────────────────────────────────────────

func _calc_eta(pts: Array) -> String:
	if pts.size() < 2:
		return "—"
	var dist := 0.0
	for i in range(pts.size() - 1):
		dist += (pts[i + 1] as Vector3).distance_to(pts[i] as Vector3)
	var minutes: int = max(1, int(dist / 84.0))   # 84 m/min walking pace
	return "%d min" % minutes


# ── Floor strip ───────────────────────────────────────────────────────────────

func _apply_floor_style(active: int) -> void:
	for fi in range(_floor_btns.size()):
		var btn: Button = _floor_btns[fi]
		if btn == null:
			continue
		if fi == active:
			btn.add_theme_color_override("font_color", C_ACCENT)
		else:
			btn.remove_theme_color_override("font_color")


# ── Style helpers ─────────────────────────────────────────────────────────────

func _flat(col: Color, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = col
	s.corner_radius_top_left     = radius
	s.corner_radius_top_right    = radius
	s.corner_radius_bottom_left  = radius
	s.corner_radius_bottom_right = radius
	return s


func _make_icon(cat: String, size: float) -> Panel:
	var cat_data: Dictionary = CATS.get(cat, CATS["default"])
	var r        := int(size / 2)
	var panel    := Panel.new()
	panel.custom_minimum_size = Vector2(size, size)
	panel.add_theme_stylebox_override("panel", _flat(cat_data["color"], r))
	panel.mouse_filter = Control.MOUSE_FILTER_PASS

	var lbl := Label.new()
	lbl.text = cat_data["icon"]
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", int(size * 0.44))
	lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_child(lbl)
	return panel


func _h_sep() -> HSeparator:
	var s := HSeparator.new()
	s.add_theme_color_override("color", C_DIV)
	return s


func _v_sep() -> VSeparator:
	var s := VSeparator.new()
	s.add_theme_color_override("color", C_DIV)
	return s


# ── Button callbacks ──────────────────────────────────────────────────────────

func _on_menu_btn_pressed() -> void:
	_dropdown.visible = not _dropdown.visible


func _toggle_orientation() -> void:
	_is_portrait = not _is_portrait
	if _is_portrait:
		_orient_btn.text = "📱 Portrait  ✓"
		DisplayServer.screen_set_orientation(DisplayServer.SCREEN_PORTRAIT)
		DisplayServer.window_set_size(Vector2i(540, 960))
	else:
		_orient_btn.text = "🖥 Landscape  ✓"
		DisplayServer.screen_set_orientation(DisplayServer.SCREEN_LANDSCAPE)
		DisplayServer.window_set_size(Vector2i(960, 540))


func _on_back_pressed() -> void:
	match _state:
		UiState.DETAIL:
			navigation_cleared.emit()
			_set_state(UiState.LIST)
		UiState.LIST:
			_set_state(UiState.HOME)


func _on_go_pressed() -> void:
	if not _current_room_id.is_empty():
		navigate_requested.emit(_current_room_id)


func _on_building_item_selected(idx: int) -> void:
	if idx >= 0 and idx < _building_ids.size():
		building_selected.emit(_building_ids[idx])


func _on_floor_btn_pressed(floor_index: int) -> void:
	floor_selected.emit(floor_index)


func _on_search_changed(text: String) -> void:
	_search_text = text
	_rebuild_room_list()


func _on_sensor_btn_pressed() -> void:
	_sensor_on = not _sensor_on
	_sensor_btn.text    = "📍 Sensor ON" if _sensor_on else "📍 Sensor OFF"
	_calib_btn.disabled = not _sensor_on
	if not _sensor_on:
		_compass_lbl.text = "Compass: —"
	_joy_panel.visible = not _sensor_on   # hide joystick when sensor drives movement
	sensor_mode_toggled.emit(_sensor_on)


# ── Virtual joystick (logic unchanged, repositioned) ─────────────────────────

func _build_joystick() -> void:
	var base := Control.new()
	base.name = "JoyBase"
	base.anchor_left   = 1.0;  base.anchor_right  = 1.0
	base.anchor_top    = 1.0;  base.anchor_bottom = 1.0
	base.offset_left   = -170; base.offset_right  = -10
	base.offset_top    = -185; base.offset_bottom = -80
	base.mouse_filter  = Control.MOUSE_FILTER_STOP
	_joy_panel = base
	add_child(base)

	var ring := PanelContainer.new()
	ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ring.mouse_filter = Control.MOUSE_FILTER_PASS
	var rs := _flat(Color(0.15, 0.15, 0.15, 0.55), 80)
	ring.add_theme_stylebox_override("panel", rs)
	base.add_child(ring)

	var hint := Label.new()
	hint.text = "MOVE"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.vertical_alignment   = VERTICAL_ALIGNMENT_BOTTOM
	hint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hint.offset_bottom = -4
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 0.6))
	hint.mouse_filter = Control.MOUSE_FILTER_PASS
	base.add_child(hint)

	var thumb := PanelContainer.new()
	thumb.custom_minimum_size = Vector2(_JOY_TR * 2, _JOY_TR * 2)
	thumb.mouse_filter = Control.MOUSE_FILTER_PASS
	thumb.add_theme_stylebox_override("panel",
		_flat(Color(0.85, 0.85, 0.85, 0.85), int(_JOY_TR)))
	_joy_thumb = thumb
	base.add_child(thumb)

	_reset_joy()
	base.gui_input.connect(_on_joy_gui_input)


# ── Recenter button ────────────────────────────────────────────────────────────

func _build_recenter_btn() -> void:
	var btn := Button.new()
	btn.text = "⊙"
	btn.anchor_left   = 0.0;  btn.anchor_right  = 0.0
	btn.anchor_top    = 1.0;  btn.anchor_bottom = 1.0
	btn.offset_left   = 10;   btn.offset_right  = 68
	btn.offset_top    = -140; btn.offset_bottom = -82
	btn.add_theme_font_size_override("font_size", 28)
	btn.add_theme_stylebox_override("normal",  _flat(Color(0.12, 0.12, 0.12, 0.88), 8))
	btn.add_theme_stylebox_override("hover",   _flat(Color(0.20, 0.20, 0.20, 0.92), 8))
	btn.add_theme_stylebox_override("pressed", _flat(Color(0.08, 0.08, 0.08, 0.95), 8))
	btn.add_theme_stylebox_override("focus",   _flat(Color(0.12, 0.12, 0.12, 0.88), 8))
	btn.add_theme_color_override("font_color", C_ACCENT)
	btn.pressed.connect(func() -> void: recenter_requested.emit())
	add_child(btn)


func _on_joy_gui_input(event: InputEvent) -> void:
	var center := Vector2(80.0, 80.0)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and _joy_finger == -1:
			_joy_finger = -2
			_joy_active = true
			_update_joy(event.position - center)
		elif not event.pressed and _joy_finger == -2:
			_joy_finger = -1
			_joy_active = false
			_reset_joy()
	elif event is InputEventMouseMotion and _joy_active and _joy_finger == -2:
		_update_joy(event.position - center)


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
	_joy_thumb.position = Vector2(80.0 - _JOY_TR, 80.0 - _JOY_TR) + clamped
	var dir := clamped / (_JOY_R - _JOY_TR) if clamped.length() > _JOY_DEAD else Vector2.ZERO
	joy_input.emit(dir)


func _reset_joy() -> void:
	if _joy_thumb:
		_joy_thumb.position = Vector2(80.0 - _JOY_TR, 80.0 - _JOY_TR)
	joy_input.emit(Vector2.ZERO)
