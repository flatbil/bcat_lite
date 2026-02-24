# room_manager.gd
extends Node

signal rooms_updated(data: Dictionary)

# Desktop / emulator : 127.0.0.1 works fine.
# Physical Android   : change to your laptop's LAN IP.
var API_BASE     := "http://192.168.4.64:8000"
var _building_id := "school_main"

@onready var http: HTTPRequest = HTTPRequest.new()


func _ready():
	add_child(http)
	http.request_completed.connect(_on_request_completed)


func set_building(building_id: String) -> void:
	_building_id = building_id


func fetch_rooms() -> void:
	var url := "%s/rooms?building=%s" % [API_BASE, _building_id]
	var err  := http.request(url)
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


# Stub: will call POST /calendar/schedule when Graph auth is implemented.
func fetch_graph_schedule(calendar_ids: Array) -> void:
	# TODO: POST to /calendar/schedule with {calendar_ids, start, end}
	print("fetch_graph_schedule: TODO — calendar_ids=", calendar_ids)
