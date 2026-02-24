# campus_manager.gd — Campus-level building index + GPS auto-detection
extends Node

signal building_list_loaded
signal building_detected(building_id: String)

const CAMPUS_FILE := "res://assets/campus.json"
const DEG_TO_M   := 111319.5   # metres per degree of latitude

var _campus_data:   Dictionary = {}
var _buildings:     Array      = []   # raw building entries from campus.json
var _last_detected: String     = ""


func load_campus() -> void:
	var f := FileAccess.open(CAMPUS_FILE, FileAccess.READ)
	if f == null:
		push_error("campus_manager: cannot open " + CAMPUS_FILE)
		return
	var txt := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	if parsed == null:
		push_error("campus_manager: invalid JSON in campus.json")
		return
	_campus_data = parsed
	_buildings   = _campus_data.get("buildings", [])
	building_list_loaded.emit()


func get_building_list() -> Array:
	var result: Array = []
	for b in _buildings:
		result.append({"id": b["id"], "display_name": b["display_name"]})
	return result


func load_building_data(building_id: String) -> Dictionary:
	for b in _buildings:
		if b["id"] == building_id:
			var f := FileAccess.open(b["file"], FileAccess.READ)
			if f == null:
				push_error("campus_manager: cannot open " + str(b["file"]))
				return {}
			var txt := f.get_as_text()
			f.close()
			var parsed = JSON.parse_string(txt)
			if parsed == null:
				push_error("campus_manager: invalid JSON in " + str(b["file"]))
				return {}
			return parsed
	push_error("campus_manager: unknown building id: " + building_id)
	return {}


# Equirectangular distance check; emits building_detected when a new building
# is within its gps_detection_radius_m.  Returns the detected building_id or "".
func detect_building(lat: float, lon: float) -> String:
	var best_id   := ""
	var best_dist := 1e9
	for b in _buildings:
		var anchor = b.get("gps_anchor", {})
		if not anchor.has("lat"):
			continue
		var alat: float = float(anchor["lat"])
		var alon: float = float(anchor["lon"])
		var dlat := (lat - alat) * DEG_TO_M
		var dlon := (lon - alon) * cos(deg_to_rad(alat)) * DEG_TO_M
		var dist := sqrt(dlat * dlat + dlon * dlon)
		var radius: float = float(b.get("gps_detection_radius_m", 50.0))
		if dist < radius and dist < best_dist:
			best_dist = dist
			best_id   = b["id"]
	if best_id != "" and best_id != _last_detected:
		_last_detected = best_id
		building_detected.emit(best_id)
	return best_id
