# room_manager.gd
extends Node

# Stub API base; later replace with real backend endpoint that uses Microsoft Graph
var API_BASE := "http://192.168.1.100:8000" # replace with your mock server IP during dev
@onready var http: HTTPRequest = HTTPRequest.new()

func _ready():
	add_child(http)
	http.connect("request_completed", Callable(self, "_on_request_completed"))

func fetch_rooms():
	var url = "%s/rooms" % API_BASE
	http.request(url, [], false, HTTPClient.METHOD_GET)

# generic fetch for one room if needed
func fetch_room(room_id: String):
	var url = "%s/rooms/%s" % [API_BASE, room_id]
	http.request(url, [], false, HTTPClient.METHOD_GET)

func _on_request_completed(result, response_code, headers, body):
	if response_code == 200:
		var json = JSON.parse(body.get_string_from_utf8())
		if json.error == OK:
			var data = json.result
			# Broadcast to building loader to update overlays
			get_tree().call_group("building", "update_room_overlays", data)
		else:
			push_warning("Failed parse JSON")
	else:
		push_warning("HTTP error: %d" % response_code)
