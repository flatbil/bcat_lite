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

## Pending / Future work

- **Satellite map overlay:** Godot cannot fetch tile imagery at runtime. To add an aerial floor texture, drop a PNG into `assets/` and apply it as an albedo texture on the main floor slab in `building_loader.gd`.
- **Native Android positioning:** Add an Android plugin to feed real GPS/BLE/UWB coordinates into `player.position` (replacing WASD). Stub is `scripts/sim_location.gd`.
- **Microsoft Graph integration:** Replace `mock_server.py` with an endpoint that reads real room calendar data via Graph API + corporate SSO.
- **Real building model:** Export a floor-plan GLB and replace the procedural geometry in `building_loader.gd`.
- **Route persistence:** Save last route to `user://last_route.json` so it survives app restart.
- **Accessibility:** Add text-to-speech for turn-by-turn directions.
