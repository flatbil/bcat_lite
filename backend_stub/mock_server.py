# backend_stub/mock_server.py
# cd backend_stub && pip install fastapi uvicorn && python mock_server.py
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
import uvicorn

app = FastAPI()
app.add_middleware(CORSMiddleware, allow_origins=["*"],
                   allow_methods=["*"], allow_headers=["*"])

rooms = {
    "boardroom": {
        "id": "boardroom", "name": "Boardroom", "capacity": 20,
        "available": False,
        "meetings_today": [
            {"time": "08:30–09:30", "title": "Exec Standup",      "organizer": "CEO Office"},
            {"time": "10:00–12:00", "title": "Q2 Strategy",       "organizer": "A. Rivera"},
            {"time": "14:00–16:00", "title": "Board Review",      "organizer": "B. Chen"},
        ],
    },
    "conf_a": {
        "id": "conf_a", "name": "Conf A", "capacity": 12,
        "available": True,
        "meetings_today": [
            {"time": "13:00–14:00", "title": "Sprint Planning",   "organizer": "Dev Team"},
        ],
    },
    "conf_b": {
        "id": "conf_b", "name": "Conf B", "capacity": 10,
        "available": False,
        "meetings_today": [
            {"time": "09:00–10:30", "title": "UX Review",         "organizer": "Design"},
            {"time": "11:00–12:00", "title": "Vendor Call",       "organizer": "Procurement"},
            {"time": "15:00–16:00", "title": "Retro",             "organizer": "Scrum Master"},
        ],
    },
    "conf_c": {
        "id": "conf_c", "name": "Conf C", "capacity": 10,
        "available": True,
        "meetings_today": [
            {"time": "14:30–15:30", "title": "HR One-on-Ones",   "organizer": "HR Dept"},
        ],
    },
    "conf_d": {
        "id": "conf_d", "name": "Conf D", "capacity": 12,
        "available": True,
        "meetings_today": [],
    },
    "conf_e": {
        "id": "conf_e", "name": "Conf E", "capacity": 10,
        "available": False,
        "meetings_today": [
            {"time": "09:30–11:00", "title": "Client Demo",       "organizer": "Sales"},
            {"time": "13:00–14:30", "title": "Partner Sync",      "organizer": "Partnerships"},
        ],
    },
    "focus_a": {
        "id": "focus_a", "name": "Focus A", "capacity": 4,
        "available": True,
        "meetings_today": [
            {"time": "10:00–11:00", "title": "1-on-1: Eng",       "organizer": "T. Park"},
        ],
    },
    "focus_b": {
        "id": "focus_b", "name": "Focus B", "capacity": 4,
        "available": True,
        "meetings_today": [],
    },
    "focus_c": {
        "id": "focus_c", "name": "Focus C", "capacity": 4,
        "available": False,
        "meetings_today": [
            {"time": "08:00–09:00", "title": "Morning Briefing",  "organizer": "Ops"},
            {"time": "15:30–16:00", "title": "Quick Sync",        "organizer": "M. Wang"},
        ],
    },
    "focus_d": {
        "id": "focus_d", "name": "Focus D", "capacity": 4,
        "available": True,
        "meetings_today": [],
    },
    "east_a": {
        "id": "east_a", "name": "East Mtg A", "capacity": 6,
        "available": True,
        "meetings_today": [
            {"time": "11:00–12:00", "title": "Cross-team Sync",   "organizer": "PM Office"},
        ],
    },
    "east_b": {
        "id": "east_b", "name": "East Mtg B", "capacity": 6,
        "available": False,
        "meetings_today": [
            {"time": "09:00–17:00", "title": "All-day Workshop",  "organizer": "L&D Team"},
        ],
    },
}


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
