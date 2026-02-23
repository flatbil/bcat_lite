# backend_stub/mock_server.py — School building rooms & schedules
# cd backend_stub && pip install fastapi uvicorn && python mock_server.py
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from math import cos, radians
from typing import Optional
import uvicorn

app = FastAPI()
app.add_middleware(CORSMiddleware, allow_origins=["*"],
                   allow_methods=["*"], allow_headers=["*"])

# ── GPS / location state ──────────────────────────────────────────────────────
_gps_state = {"lat": None, "lon": None, "accuracy": None}
# Anchor: maps a real-world lat/lon to a building X/Z coordinate.
# Until set via POST /location/anchor, has_fix will be false.
_gps_anchor = {"lat": None, "lon": None, "bx": 50.0, "bz": 44.0}


class GpsPayload(BaseModel):
    lat: float
    lon: float
    accuracy: Optional[float] = None


class AnchorPayload(BaseModel):
    lat: float
    lon: float
    building_x: float = 50.0
    building_z: float = 44.0

rooms = {
    # ── North Wing ────────────────────────────────────────────────────────────
    "bay_747": {
        "id": "bay_747", "name": "Gymnasium", "capacity": 200,
        "available": True,
        "meetings_today": [
            {"time": "07:30–09:00", "title": "Morning PE — Grade 10",        "organizer": "Coach Rivera"},
            {"time": "10:30–12:00", "title": "Basketball Practice",           "organizer": "Varsity Team"},
            {"time": "14:00–15:30", "title": "School Assembly — All Grades",  "organizer": "Principal's Office"},
        ],
    },
    "bay_767": {
        "id": "bay_767", "name": "Art Room", "capacity": 50,
        "available": False,
        "meetings_today": [
            {"time": "08:00–09:30", "title": "Visual Art — Grade 9",          "organizer": "Ms. Chen"},
            {"time": "10:00–11:30", "title": "Visual Art — Grade 11",         "organizer": "Ms. Chen"},
            {"time": "13:00–14:30", "title": "AP Studio Art",                 "organizer": "Ms. Chen"},
            {"time": "15:00–16:30", "title": "Art Club (after school)",        "organizer": "Art Club"},
        ],
    },
    "bay_777": {
        "id": "bay_777", "name": "Classroom Block", "capacity": 80,
        "available": False,
        "meetings_today": [
            {"time": "08:00–09:00", "title": "English 10 — Period 1",         "organizer": "Mr. Nguyen"},
            {"time": "09:15–10:15", "title": "History — Period 2",             "organizer": "Ms. Patel"},
            {"time": "10:30–11:30", "title": "English 12 — Period 3",          "organizer": "Mr. Nguyen"},
            {"time": "13:00–14:00", "title": "World Literature — Period 5",    "organizer": "Ms. Patel"},
            {"time": "14:15–15:15", "title": "SAT Prep Session",               "organizer": "Tutoring Centre"},
        ],
    },
    # ── Main Hallway — North Side ─────────────────────────────────────────────
    "visitor_ctr": {
        "id": "visitor_ctr", "name": "Main Office", "capacity": 20,
        "available": True,
        "meetings_today": [
            {"time": "07:00–07:30", "title": "Morning Admin Check-In",         "organizer": "Front Desk"},
            {"time": "09:00–10:00", "title": "Parent–Teacher Conference",      "organizer": "Principal Adams"},
            {"time": "14:00–14:30", "title": "Discipline Hearing",             "organizer": "Vice Principal"},
        ],
    },
    "safety_ofc": {
        "id": "safety_ofc", "name": "Counselor's Office", "capacity": 10,
        "available": False,
        "meetings_today": [
            {"time": "08:00–09:00", "title": "Individual Session — Grade 12",  "organizer": "Counselor Lee"},
            {"time": "10:00–11:00", "title": "College Planning Workshop",       "organizer": "Counselor Lee"},
            {"time": "13:00–14:00", "title": "Anxiety Support Group",          "organizer": "Counselor Lee"},
            {"time": "14:15–15:00", "title": "Individual Session — Grade 10",  "organizer": "Counselor Lee"},
        ],
    },
    "north_cafe": {
        "id": "north_cafe", "name": "Staff Lounge", "capacity": 40,
        "available": True,
        "meetings_today": [
            {"time": "07:30–08:00", "title": "Morning Briefing — All Staff",   "organizer": "Principal Adams"},
            {"time": "12:00–13:00", "title": "Staff Lunch (Open)",             "organizer": "Facilities"},
            {"time": "15:30–16:30", "title": "Department Heads Meeting",        "organizer": "Principal Adams"},
        ],
    },
    "quality_ctl": {
        "id": "quality_ctl", "name": "Library", "capacity": 60,
        "available": True,
        "meetings_today": [
            {"time": "08:00–09:00", "title": "Study Hall — Grades 9–10",       "organizer": "Librarian Torres"},
            {"time": "11:00–12:00", "title": "Research Skills Workshop",        "organizer": "Librarian Torres"},
            {"time": "13:00–14:00", "title": "Study Hall — Grades 11–12",      "organizer": "Librarian Torres"},
            {"time": "14:30–15:30", "title": "Book Club Meeting",               "organizer": "Literary Society"},
        ],
    },
    # ── Main Hallway — South Side ─────────────────────────────────────────────
    "final_asm": {
        "id": "final_asm", "name": "Assembly Hall", "capacity": 150,
        "available": False,
        "meetings_today": [
            {"time": "09:00–10:00", "title": "Choir Rehearsal",                "organizer": "Mr. Osei"},
            {"time": "11:00–12:00", "title": "Drama Rehearsal — Act II",       "organizer": "Drama Club"},
            {"time": "14:00–15:30", "title": "Spring Concert Rehearsal",       "organizer": "Music Dept"},
        ],
    },
    "med_center": {
        "id": "med_center", "name": "Nurse's Office", "capacity": 10,
        "available": True,
        "meetings_today": [
            {"time": "08:00–09:00", "title": "Daily Medication Administration", "organizer": "Nurse Kim"},
            {"time": "10:00–10:30", "title": "Allergy Injection Clinic",        "organizer": "Nurse Kim"},
            {"time": "13:00–13:30", "title": "Vision Screening — Grade 9",     "organizer": "Health Team"},
        ],
    },
    "conf_777x": {
        "id": "conf_777x", "name": "Conference Room", "capacity": 30,
        "available": True,
        "meetings_today": [
            {"time": "08:30–10:00", "title": "IEP Meeting — Student Services", "organizer": "Special Ed Dept"},
            {"time": "10:30–11:30", "title": "Curriculum Planning — Maths",    "organizer": "Dept Head"},
            {"time": "13:30–15:00", "title": "School Board Sub-Committee",     "organizer": "Board Rep"},
        ],
    },
    "bay_777x": {
        "id": "bay_777x", "name": "Computer Lab", "capacity": 40,
        "available": False,
        "meetings_today": [
            {"time": "08:00–09:00", "title": "Intro to Programming — Gr 9",   "organizer": "Mr. Walsh"},
            {"time": "09:15–10:15", "title": "AP Computer Science — Gr 12",   "organizer": "Mr. Walsh"},
            {"time": "10:30–11:30", "title": "Web Design Elective",            "organizer": "Mr. Walsh"},
            {"time": "13:00–14:00", "title": "Robotics Club",                  "organizer": "Tech Club"},
        ],
    },
    # ── South Wing ────────────────────────────────────────────────────────────
    "tool_crib": {
        "id": "tool_crib", "name": "Custodial Room", "capacity": 10,
        "available": True,
        "meetings_today": [
            {"time": "06:30–07:00", "title": "Morning Facilities Briefing",    "organizer": "Head Custodian"},
            {"time": "15:30–16:00", "title": "End-of-Day Equipment Check",     "organizer": "Head Custodian"},
        ],
    },
    "engineering": {
        "id": "engineering", "name": "Science Lab", "capacity": 60,
        "available": False,
        "meetings_today": [
            {"time": "08:00–09:30", "title": "Chemistry Lab — Grade 10",       "organizer": "Dr. Morris"},
            {"time": "10:00–11:30", "title": "Physics Lab — Grade 12",         "organizer": "Dr. Morris"},
            {"time": "13:00–14:30", "title": "Biology Dissection — Grade 11",  "organizer": "Dr. Morris"},
            {"time": "15:00–16:00", "title": "Science Olympiad Practice",       "organizer": "Science Club"},
        ],
    },
    "south_cafe": {
        "id": "south_cafe", "name": "Cafeteria", "capacity": 200,
        "available": True,
        "meetings_today": [
            {"time": "11:00–11:45", "title": "Lunch — Grades 9 & 10",         "organizer": "Facilities"},
            {"time": "11:45–12:30", "title": "Lunch — Grades 11 & 12",        "organizer": "Facilities"},
            {"time": "16:00–18:00", "title": "Fundraiser Dinner (evening)",    "organizer": "PTA"},
        ],
    },
    "delivery": {
        "id": "delivery", "name": "Storage Room", "capacity": 20,
        "available": True,
        "meetings_today": [
            {"time": "07:00–07:30", "title": "Supply Delivery Receiving",      "organizer": "Admin"},
            {"time": "14:00–14:30", "title": "Textbook Distribution",          "organizer": "Admin"},
        ],
    },
}


@app.post("/location/gps")
def post_gps(payload: GpsPayload):
    """Receive a GPS fix from the companion browser page."""
    _gps_state["lat"] = payload.lat
    _gps_state["lon"] = payload.lon
    _gps_state["accuracy"] = payload.accuracy
    return {"status": "ok"}


@app.get("/location/building")
def get_building_location():
    """Convert latest GPS fix to building X/Z using the anchor mapping."""
    if _gps_anchor["lat"] is None or _gps_state["lat"] is None:
        return {"has_fix": False}
    # Equirectangular approximation
    anchor_lat = _gps_anchor["lat"]
    anchor_lon = _gps_anchor["lon"]
    dx = ((_gps_state["lon"] - anchor_lon)
          * cos(radians(anchor_lat)) * 111319.5)
    dz = -((_gps_state["lat"] - anchor_lat) * 111319.5)  # -z = north
    x = _gps_anchor["bx"] + dx
    z = _gps_anchor["bz"] + dz
    return {"has_fix": True, "x": x, "z": z,
            "accuracy": _gps_state["accuracy"]}


@app.post("/location/anchor")
def set_anchor(payload: AnchorPayload):
    """Map a real-world GPS coordinate to a building position."""
    _gps_anchor["lat"] = payload.lat
    _gps_anchor["lon"] = payload.lon
    _gps_anchor["bx"]  = payload.building_x
    _gps_anchor["bz"]  = payload.building_z
    return {"status": "ok", "anchor": _gps_anchor}


@app.get("/rooms")
def list_rooms():
    return rooms


@app.get("/rooms/{room_id}")
def get_room(room_id: str):
    if room_id not in rooms:
        raise HTTPException(404, "Room not found")
    return rooms[room_id]


@app.post("/rooms/{room_id}/toggle")
def toggle_room(room_id: str):
    """Flip availability — handy for live demo."""
    if room_id not in rooms:
        raise HTTPException(404, "Room not found")
    rooms[room_id]["available"] = not rooms[room_id]["available"]
    return rooms[room_id]


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
