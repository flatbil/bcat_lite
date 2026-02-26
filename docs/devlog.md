# bcat_lite — Development Log

Chronological record of design decisions, architectural choices, and implementation notes from the AI-assisted development sessions.

---

## Session 1 — Initial skeleton to working POC

**Goal:** Take the non-functional Godot 4.6 skeleton (mixing Godot 3 and 4 APIs, mismatched scene/script references, no UI) and produce a working kiosk-style wayfinding demo.

### Architecture settled on

| Layer | Choice | Reason |
|---|---|---|
| Building model | Procedural GDScript (no GLB) | No binary assets needed; works immediately |
| Player position | Fixed at entrance or WASD/joystick | Kiosk-first; GPS/BLE noted for future |
| Path visual | BoxMesh segments + sphere dots | No plugins; clearly visible on floor |
| UI structure | All built in code in `_ready()` | Avoids error-prone hand-written `.tscn` hierarchy |
| Room picking | `.bind(room_id)` on `input_event` | Avoids closure-in-loop bug in for-loops |
| Pathfinding | A* on a hand-authored JSON nav graph | Simple, debuggable, no NavigationServer needed |

### Signal flow

```
3D room click  ──► building.room_clicked  ──► main._on_room_info_requested()
UI "Go" button ──► ui.navigate_requested  ──► main._navigate_to()
main._navigate_to() ──► navigator.route_to_room()
                    ──► main._draw_path()
                    ──► ui.show_navigation()
backend poll   ──► room_manager.rooms_updated ──► building.update_room_availability()
                                              ──► ui.update_availability()
```

### Key Godot 4 API fixes applied

- `JSON.parse(txt)` → `JSON.parse_string(txt)`
- `sort_custom(self, "_method", data)` → `sort_custom(func(a,b): return ...)`
- `http.request(url, [], false, ...)` → `http.request(url)` (Godot 4 defaults)
- `get_viewport().physics_object_picking = true` required for `StaticBody3D.input_event`
- Transform3D in `.tscn` is **row-major** — always prefer `position =` / `rotation =` properties

### Files written

| File | Notes |
|---|---|
| `scripts/navigator.gd` | A* on JSON nav graph; `find_nearest_node()` snaps player pos to graph |
| `scripts/room_manager.gd` | HTTPRequest node, `rooms_updated` signal, graceful HTTP failure |
| `scripts/building_loader.gd` | Procedural building; `select_room()`, `clear_selection()`, `update_room_availability()`, `get_room_data()` |
| `scripts/main.gd` | Scene glue; `_draw_path()` with BoxMesh segments + sphere dots |
| `scripts/sim_location.gd` | Stub; `signal location_changed(new_pos: Vector3)` — placeholder for GPS/BLE/UWB |
| `scenes/ui.gd` | Left room-list panel + right nav panel + meeting popup; all built in code |
| `scenes/UI.tscn` | Minimal — just root Control node; all children created at runtime |
| `scenes/Building.tscn` | Minimal — root Node3D with building_loader.gd |
| `scenes/Main.tscn` | Camera, DirectionalLight3D, Building, Navigator, RoomManager, PathDisplay, Player, CanvasLayer/Ui |
| `assets/nav_graph.json` | Nav graph (nodes, edges, room_node_map) |
| `backend_stub/mock_server.py` | FastAPI + CORS; `GET /rooms`, `GET /rooms/{id}`, `POST /rooms/{id}/toggle` |

---

## Session 2 — Android export + multi-touch camera

**Goal:** Deploy to Android; pinch/zoom and drag must be multi-touch enabled.

### Camera controller rewrite (`scripts/camera_controller.gd`)

Two independent control modes handled in `_unhandled_input`:

**Desktop:**
- Scroll-wheel → `_zoom_stepped(±1)` → `_zoom_by_factor(ZOOM_STEP^direction)`
- Right/middle button drag → `_pan_from_origin(delta)` (origin-anchored, no drift)

**Mobile (touch):**
- 1-finger drag → `_pan_delta(delta)` (incremental)
- 2-finger pinch → `_zoom_by_factor(dist_prev / dist_cur)`
- 2-finger drag (centroid) → `_pan_delta(centroid_delta)`

Touch state kept in two dictionaries: `_touches` (current) and `_prev_touches` (previous frame).

**Constants:**
```gdscript
MIN_HEIGHT   := 5.0     # metres
MAX_HEIGHT   := 150.0   # metres
ZOOM_STEP    := 1.18    # per scroll tick
PAN_SENS     := 0.002   # metres/pixel/metre of camera height
```

**Type inference fixes (GDScript strict mode):**
```gdscript
# BAD  — Dictionary.keys() returns untyped Array
var idx   := keys[0]
var delta := _touches[idx] - ...

# GOOD
var idx:   int     = keys[0]
var delta: Vector2 = _touches[idx] - _prev_touches.get(idx, _touches[idx])
```

### Android export config

`project.godot` additions:
```ini
[display]
window/handheld/orientation=0           ; landscape
window/stretch/mode="canvas_items"
window/stretch/aspect="expand"

[input_devices]
pointing/emulate_touch_from_mouse=true  ; lets desktop test touch paths
```

`export_presets.cfg`: Android preset, `com.bcat.lite`, arm64, INTERNET permission.

> **Important for physical Android:** change `API_BASE` in `room_manager.gd` from `127.0.0.1` to your LAN IP before building.

---

## Session 3 — Player movement + live path re-routing

**Goal:** Walking character (WASD + virtual joystick); path trace updates as character moves.

### Player (`scripts/player.gd`)

- `extends Node3D`, `const SPEED := 15.0` (m/s — building is ~100 m wide)
- Glowing cyan cylinder (CylinderMesh) + "YOU" billboard Label3D built procedurally in `_ready()`
- `_process`: reads `Input.get_axis("ui_left","ui_right")` + `joy_dir` from UI joystick
- `signal moved(pos: Vector3)` emitted every 2 m (kept for potential future consumers)
- `position.y = 0.0` each frame — stays on floor

### Virtual joystick (in `scenes/ui.gd`)

110 × 110 px Control anchored bottom-right, clear of the nav panel.
`_on_joy_gui_input()` handles mouse; `_input()` handles real Android touches using `get_global_rect()` hit-test.
Emits `signal joy_input(dir: Vector2)` connected in `main.gd` via:
```gdscript
ui.joy_input.connect(func(d: Vector2) -> void: player.joy_dir = d)
```

### Live path re-routing fix

**Problem:** signal-based approach (`player.moved → _on_player_moved`) was unreliable.

**Fix:** `_process` poll in `main.gd`:
```gdscript
var _last_route_pos: Vector3 = Vector3(1e9, 1e9, 1e9)

func _process(_delta: float) -> void:
    if _current_dest.is_empty() or not is_instance_valid(player):
        return
    if player.position.distance_to(_last_route_pos) > 2.0:
        _last_route_pos = player.position
        var pts = navigator.route_to_room(player.global_position, _current_dest)
        _draw_path(pts)
        ui.show_navigation(_current_dest, pts)
```
`_last_route_pos` is reset to `player.global_position` on every new `_navigate_to()` call and to `Vector3(1e9,1e9,1e9)` on `_clear_route()`.

---

## Session 4 — School building layout

**Goal:** Redesign the map to look like a school with hallways and classrooms; keep all 15 room IDs; update schedules.

### Building layout (`scripts/building_loader.gd`)

**H-plan school, 100 m × 80 m (X: 0→100, Z: −40→40)**

```
Z = -40  ┌────────────────────────────────────────────────────────┐
         │  Gymnasium  │      Art Room      │   Classroom Block   │
         │  (bay_747)  │    (bay_767)       │     (bay_777)       │
Z = -26  ├═════════════════ NORTH HALLWAY ══════════════════════╡Z=-24
         │                                                        │
         │  Main Off.  │ Counselor │ Staff Lounge │   Library     │
Z = -7   ├─────────────┤───────────┤──────────────┤───────────────┤
Z =  0   ╠═════════════════ MAIN HALLWAY ═════════════════════════╣
Z =  7   ├─────────────┬───────────┬──────────────┬───────────────┤
         │ Assembly Hll│  Nurse    │ Conf. Room   │  Computer Lab │
         │                                                        │
Z = +22  ├═════════════════ SOUTH HALLWAY ══════════════════════╡Z=+24
         │  Custodial  │    Science Lab     │  Cafeteria  │ Storage│
Z = +36  └────────────────────────────────────────────────────────┘

N-S connectors at X=5 (west), X=50 (centre/entrance foyer), X=95 (east)
Player starts outside south entrance at (50, 0, 44)
```

**Room ID → school name mapping:**

| Room ID | School Name | Location |
|---|---|---|
| `bay_747` | Gymnasium | North wing |
| `bay_767` | Art Room | North wing |
| `bay_777` | Classroom Block | North wing |
| `visitor_ctr` | Main Office | North corridor |
| `safety_ofc` | Counselor's Office | North corridor |
| `north_cafe` | Staff Lounge | North corridor |
| `quality_ctl` | Library | North corridor |
| `final_asm` | Assembly Hall | South corridor |
| `med_center` | Nurse's Office | South corridor |
| `conf_777x` | Conference Room | South corridor |
| `bay_777x` | Computer Lab | South corridor |
| `tool_crib` | Custodial Room | South wing |
| `engineering` | Science Lab | South wing |
| `south_cafe` | Cafeteria | South wing |
| `delivery` | Storage Room | South wing |

### Nav graph (`assets/nav_graph.json`)

32 nodes total:
- 5 main hallway nodes (`mh1`–`mh5`) at Z=0, X=5/25/50/75/95
- 5 north hallway nodes (`nh1`–`nh5`) at Z=−24
- 5 south hallway nodes (`sh1`–`sh5`) at Z=+24
- Entrance nodes: `n_start` (50,0,44), `n_ent` (50,0,30)
- 15 room door nodes on their respective hallways

Vertical connectors: `mh1↔nh1↔sh1` (west), `mh3↔nh3` + `mh3↔sh3↔n_ent↔n_start` (centre), `mh5↔nh5↔sh5` (east).

Each room door node sits on the hallway as an in-chain node (connected to the two nearest hallway chain nodes) rather than a pure leaf, ensuring clean path segments.

---

---

## Session 5 — Phone location tracking (dead reckoning + GPS corrections)

**Goal:** Drive the player marker from the phone's physical movement rather than WASD.
Primary: accelerometer step detection + magnetometer compass (dead reckoning).
Corrections: GPS from a companion browser page, smoothly blended like Google Maps.
Joystick kept as fallback/override.

### Architecture

```
[Phone browser — backend_stub/companion.html]
  navigator.geolocation.watchPosition() → POST /location/gps every 10 s

[backend_stub/mock_server.py]
  Stores latest lat/lon, converts to building X/Z via anchor mapping
  GET /location/building → {x, z, has_fix}

[scripts/sim_location.gd]
  Accelerometer LPF → step detection → dead reckoning (heading from magnetometer)
  HTTPRequest polls GET /location/building every 5 s
  GPS fix → accumulate _gps_correction; bleed in at GPS_BLEND_SPEED m/s each frame
  Emits location_changed(pos) each frame when enabled

[scripts/main.gd]
  _on_sim_location_changed(pos) → player.position = pos
  Joystick/WASD override still runs through player.gd
```

### Smooth GPS blending (key design decision)

Previous cell-tower approach teleported the marker on each fix (jumpy). Fix:

- `_gps_correction: Vector3` accumulates `gps_pos - _pos` on each fix
- Each frame: `move = min(GPS_BLEND_SPEED * delta, correction.length())`; advance `_pos` by that amount
- Correction is consumed gradually (3 m/s) — invisible to the user
- Fixes > 25 m away are discarded (`GPS_MAX_CORRECTION`) to reject wild readings
- Between fixes: pure dead reckoning; no drift accumulation from stale GPS

### Dead reckoning constants

```gdscript
const STRIDE_M       := 0.70   # metres per detected step
const STEP_THRESHOLD := 1.2    # low-pass accel magnitude threshold
const STEP_DEBOUNCE  := 0.30   # min seconds between steps
const LPF_ALPHA      := 0.12   # exponential low-pass factor
```

### GPS blending constants

```gdscript
const GPS_POLL_INTERVAL  := 5.0    # seconds between /location/building polls
const GPS_BLEND_SPEED    := 3.0    # m/s correction drain rate
const GPS_MAX_CORRECTION := 25.0   # discard GPS fixes further than this
```

### Coordinate conversion (mock_server.py)

Equirectangular approximation — accurate within ~1 m for a 100 m building:
```python
dx = (lon - anchor_lon) * cos(radians(anchor_lat)) * 111319.5
dz = -(lat - anchor_lat) * 111319.5  # -z = north in building space
x  = anchor_bx + dx
z  = anchor_bz + dz
```

### Files changed

| File | Change |
|---|---|
| `scripts/sim_location.gd` | Full rewrite — extends Node; step detection, magnetometer heading, GPS poll + blend |
| `scripts/player.gd` | Added `var sensor_mode := false`; WASD skipped when true, joystick always active |
| `scripts/main.gd` | `@onready var sim_loc`; 4 new methods; compass update in `_process` |
| `scenes/ui.gd` | 3 new signals; `_build_location_bar()` — floating panel with Sensor/Calibrate/Reset; `update_compass()` |
| `scenes/Main.tscn` | Added `SimLocation` Node with `sim_location.gd` |
| `backend_stub/mock_server.py` | `POST /location/gps`, `GET /location/building`, `POST /location/anchor` |
| `backend_stub/companion.html` | New standalone page — GPS watch, 10 s POST, anchor setup, status display |

### Calibration flow

1. Run `python mock_server.py`; open `companion.html` on phone; set server URL to LAN IP
2. Stand at building entrance (X=50, Z=44)
3. In companion.html: **Set as Building Anchor** → maps current GPS to entrance coords
4. In app: **📍 Sensor ON** → player position seeded to current marker location
5. Point phone toward building north; tap **⊙ Calibrate ↑** → compass zero set
6. Walk — dead reckoning updates marker; GPS corrections blend in every 5–10 s
7. **⌂ Reset** anytime → returns marker + sim_loc to entrance (50, 0, 44)

### Notes

- In Godot editor (desktop), `Input.get_accelerometer()` and `Input.get_magnetometer()` return `Vector3.ZERO` — sensor mode will emit location_changed but position won't move (expected; no crash)
- `sim_location.gd` uses its own hardcoded `API_BASE = "http://127.0.0.1:8000"` — update alongside `room_manager.gd` for Android LAN deployment
- companion.html saves server URL to `localStorage` so it survives page reload

---

## Session 6 — OSM tile background + Google Maps UI redesign

**Goal:** Real-world scale OSM map tiles as ground plane; Google Maps-style dark-theme UI.

### OSM tile system (`scripts/tile_map.gd`)

- New `OsmTileMap` class (extends Node3D); call `setup(lat, lon, world_pos)` per building load
- Fetches 5×5 grid (GRID_R=2) of tiles at zoom 18 (~103 m/tile at lat 47°)
- 4 concurrent `HTTPRequest` pool; tiles at Y=−0.05 (floor slab at Y=0 covers inside, tiles show outside)
- Web Mercator math: `_lon_to_tx`, `_lat_to_ty`, `_calc_frac` → `_tile_center(tx, ty)`
- UV(0,0)=NW correct after QuadMesh −90° X rotation
- Added `campus_manager.get_building_gps_anchor(id)` helper

### UI redesign (`scenes/ui.gd`)

Full rewrite. Same public signal/method API — `main.gd` unchanged.

| Old | New |
|---|---|
| Left sidebar room list | Full-screen map + bottom drawer |
| Right nav panel | DETAIL card at bottom |
| Light default theme | Dark `#2a2a2a` theme |
| Yellow 3D route boxes | Flat blue (#4285f4-ish) route line |
| Cyan cylinder player | Teal teardrop pin (sphere head + stem) |

**3-state bottom drawer:**
- `HOME` — "Common Destinations" | "Saved" tab bar (72 px)
- `LIST` — slides up to 62% height; rooms grouped Popular / Other; coloured emoji icon circles
- `DETAIL` — 234 px card: name, floor, 🚶 ETA, availability, Save, full-width green Go button

**Category → emoji + colour:**
food🍽(red) coffee☕(orange) restroom🚻(blue) gym🏀(orange) lab🔬(green) library📚(teal) nurse⚕(red) fitness💪(purple) office🏢(blue) storage📦(grey)

**ETA:** route point distances / 84 m·min⁻¹ walking pace → "X min"

**Player marker (`scripts/player.gd`):**
Teal pin: head SphereMesh (r=0.38) at Y=1.28 + stem CylinderMesh + shadow disk; ghost next_pass for visibility through walls.

---

## Session 7 — 2D room labels, infinite OSM tiles, UI polish

### 2D screen-space room labels (`scripts/room_labels.gd` — new file)

Replaced all `Label3D` nodes with a Control-based RTS health-bar system:

- `setup(cam)` → stores Camera3D ref, fills `PRESET_FULL_RECT`, sets `MOUSE_FILTER_IGNORE`
- `set_rooms(arr)` / `set_overlays(arr)` — build PanelContainer + Label nodes on load, pre-measure sizes with `ThemeDB.fallback_font.get_string_size()` so overlap checks are correct on frame 1
- `_update_labels()` — every call: hide all; project world_pos → screen via `camera.unproject_position()`; greedy placement: sort by priority (selected=2, room=1, overlay=0) then screen Y; place each only if `rect.grow(OVERLAP_GAP)` doesn't intersect any already-placed rect
- Only runs when camera actually moves (`_dirty` flag + transform cache) — no per-frame work while camera is static
- `room_label_clicked(room_id)` signal wired into `main._on_room_info_requested()`

**ENTRANCE / STAIRS overlays:** removed from `building_loader.gd` as Label3D; now collected in `_overlay_labels` array and exposed via `get_overlay_labels()`. Both render through the same greedy placement at priority 0 (always yield to room labels).

### Infinite procedural OSM tile streaming (`scripts/tile_map.gd` — rewritten)

| Before | After |
|---|---|
| Fixed 7×7 grid loaded at `setup()` | Procedural: load within `LOAD_R=2` tiles of camera, free beyond `UNLOAD_R=4` |
| 4 HTTP workers | 8 HTTP workers |
| Gray void beyond grid | `RenderingServer.set_default_clear_color()` fills everything beyond tiles — zero geometry, zero z-fighting |

Key change: `_process()` calls `_world_to_tile(cam.global_position)` → `Vector2i` each frame. Work only happens when the camera crosses a tile boundary. `_unload_far()` frees `MeshInstance3D` references; the callback `_tiles.has(key)` guard discards in-flight responses for freed tiles.

**Backdrop z-fighting fix:** previous session added a large quad 2 cm below the tile layer which depth-fought with tiles during camera movement. Removed entirely; `set_default_clear_color` replaces it with zero rendering cost.

### UI polish

- **Font sizes** — all `add_theme_font_size_override` values ×1.2 across `ui.gd`
- **Joystick** — hidden when sensor mode is ON; shown when OFF
- **Tap-to-deselect** — `_unhandled_input` tracks press position; on release checks `_room_clicked_this_tap` flag (set by the physics `input_event` callback which fires between press and release) before deselecting
- **Finger-scrollable list** — `MOUSE_FILTER_PASS` on row Buttons, dividers, and section headers so drag propagates to ScrollContainer
- **Recenter button** (`⊙`, bottom-left, accent blue) — `ui.recenter_requested` → `main._on_recenter()` positions camera so its fixed-pitch forward ray intersects the ground at the player: `cam_z = player_z + h * 0.876` (derived from pitch −0.852 rad)

## Pending / Future work

- **Satellite map overlay:** Godot cannot fetch tile imagery at runtime. To add an aerial floor texture, drop a PNG into `assets/` and apply it as an albedo texture on the main floor slab in `building_loader.gd`.
- **Microsoft Graph integration:** Replace `mock_server.py` with an endpoint that reads real room calendar data via Graph API + corporate SSO.
- **Real building model:** Export a floor-plan GLB and replace the procedural geometry in `building_loader.gd`.
- **Route persistence:** Save last route to `user://last_route.json` so it survives app restart.
- **Accessibility:** Add text-to-speech for turn-by-turn directions.
- **Android magnetometer calibration:** On-device figure-8 motion to compensate for hard/soft iron distortion.
