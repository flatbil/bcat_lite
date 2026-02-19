# room_manager.gd
extends Node

signal rooms_updated(data: Dictionary)

# ── Backend URL ──────────────────────────────────────────────────────────────
# Desktop / emulator : 127.0.0.1 works fine.
# Physical Android   : change to your laptop's LAN IP, e.g. "http://192.168.1.42:8000"
#                      (phone and laptop must be on the same Wi-Fi network)
var API_BASE := "http://127.0.0.1:8000"
@onready var http: HTTPRequest = HTTPRequest.new()

func _ready():
	add_child(http)
	http.request_completed.connect(_on_request_completed)

func fetch_rooms():
	var url = "%s/rooms" % API_BASE
	var err = http.request(url)
	if err != OK:
		push_warning("HTTP request failed to start: %d" % err)

func _on_request_completed(result, response_code, _headers, body):
	if result != HTTPRequest.RESULT_SUCCESS:
		push_warning("HTTP request failed (result=%d)" % result)
		return
	if response_code == 200:
		var data = JSON.parse_string(body.get_string_from_utf8())
		if data != null:
			rooms_updated.emit(data)
		else:
			push_warning("Failed to parse rooms JSON")
	else:
		push_warning("HTTP error: %d" % response_code)
