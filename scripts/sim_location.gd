# sim_location.gd — Dead-reckoning + GPS correction positioning
# Primary: accelerometer step detection + magnetometer compass heading
# Corrections: GPS fixes from companion.html via mock_server, blended smoothly
extends Node

signal location_changed(pos: Vector3)

# ── Dead reckoning constants ──────────────────────────────────────────────────
const STRIDE_M       := 0.70   # metres per detected step
const STEP_THRESHOLD := 1.2    # low-pass accel magnitude to count as step
const STEP_DEBOUNCE  := 0.30   # min seconds between steps
const LPF_ALPHA      := 0.12   # exponential low-pass factor

# ── GPS blending constants ────────────────────────────────────────────────────
const GPS_POLL_INTERVAL  := 5.0   # seconds between /location/building polls
const GPS_BLEND_SPEED    := 3.0   # m/s rate at which correction drains
const GPS_MAX_CORRECTION := 25.0  # max plausible GPS correction (metres)

# Shared with room_manager.gd — change both for Android deployment
const API_BASE := "http://127.0.0.1:8000"

# ── State ─────────────────────────────────────────────────────────────────────
var _enabled:        bool    = false
var _pos:            Vector3 = Vector3(50, 0, 44)   # building entrance default
var _accel_smooth:   Vector3 = Vector3.ZERO
var _step_cooldown:  float   = 0.0
var _north_bearing:  float   = 0.0                  # calibrated compass zero
var _gps_correction: Vector3 = Vector3.ZERO
var _gps_timer:      float   = 0.0
var _http_busy:      bool    = false

var _http: HTTPRequest

# ── Startup ───────────────────────────────────────────────────────────────────
func _ready() -> void:
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_gps_response)

# ── Frame update ──────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if not _enabled:
		return

	# Step detection via low-pass filtered accelerometer
	var raw: Vector3 = Input.get_accelerometer()
	_accel_smooth = _accel_smooth.lerp(raw, LPF_ALPHA)
	var mag := _accel_smooth.length()
	_step_cooldown = max(0.0, _step_cooldown - delta)
	if mag > STEP_THRESHOLD and _step_cooldown <= 0.0:
		_on_step()
		_step_cooldown = STEP_DEBOUNCE

	# Bleed GPS correction into position at a constant rate
	var corr_len := _gps_correction.length()
	if corr_len > 0.001:
		var move := min(GPS_BLEND_SPEED * delta, corr_len)
		var dir   := _gps_correction.normalized()
		_pos            += dir * move
		_gps_correction -= dir * move

	# Poll GPS server on timer
	_gps_timer -= delta
	if _gps_timer <= 0.0:
		_gps_timer = GPS_POLL_INTERVAL
		_poll_gps()

	location_changed.emit(_pos)

# ── Step handler ──────────────────────────────────────────────────────────────
func _on_step() -> void:
	var mag_raw: Vector3 = Input.get_magnetometer()
	var bearing: float   = _get_raw_bearing(mag_raw) - _north_bearing
	_pos.x += sin(bearing) * STRIDE_M
	_pos.z -= cos(bearing) * STRIDE_M   # -Z is north in building space

func _get_raw_bearing(m: Vector3) -> float:
	return atan2(m.x, m.y)

# ── GPS polling ───────────────────────────────────────────────────────────────
func _poll_gps() -> void:
	if _http_busy:
		return
	_http_busy = true
	var err := _http.request(API_BASE + "/location/building")
	if err != OK:
		_http_busy = false

func _on_gps_response(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_http_busy = false
	if code != 200:
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if data == null or not data.get("has_fix", false):
		return
	var gx := float(data.get("x", _pos.x))
	var gz := float(data.get("z", _pos.z))
	var diff := Vector3(gx, 0.0, gz) - _pos
	if diff.length() > GPS_MAX_CORRECTION:
		return   # discard wild GPS reading
	_gps_correction = diff

# ── Public API ────────────────────────────────────────────────────────────────
func enable(on: bool) -> void:
	_enabled = on
	if not on:
		_gps_correction = Vector3.ZERO

func set_start_position(pos: Vector3) -> void:
	_pos            = pos
	_gps_correction = Vector3.ZERO

func calibrate_north() -> void:
	var m := Input.get_magnetometer()
	_north_bearing = _get_raw_bearing(m)

func get_current_bearing_deg() -> float:
	var m := Input.get_magnetometer()
	var b := _get_raw_bearing(m) - _north_bearing
	return fmod(rad_to_deg(b) + 360.0, 360.0)
