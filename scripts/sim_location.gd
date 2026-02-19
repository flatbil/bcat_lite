# sim_location.gd — stub for future GPS / BLE / UWB integration
extends Node3D

signal location_changed(new_pos: Vector3)

# TODO: integrate a real positioning back-end.
# Options: BLE beacon RSSI trilateration, UWB anchors, indoor GPS, or keep
# fixed kiosk mode (position hardcoded to building entrance).
