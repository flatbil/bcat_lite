# backend_stub/mock_server.py  — Boeing Everett Factory rooms
# cd backend_stub && pip install fastapi uvicorn && python mock_server.py
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
import uvicorn

app = FastAPI()
app.add_middleware(CORSMiddleware, allow_origins=["*"],
                   allow_methods=["*"], allow_headers=["*"])

rooms = {
    # ── Production Bays ───────────────────────────────────────────────────────
    "bay_747": {
        "id": "bay_747", "name": "747 Bay (Legacy)", "capacity": 200,
        "available": True,
        "meetings_today": [
            {"time": "07:00–09:00", "title": "Heritage Aircraft Walk-Down",  "organizer": "Maintenance Ops"},
            {"time": "14:00–15:30", "title": "Museum Loan Program Review",   "organizer": "Program Mgmt"},
        ],
    },
    "bay_767": {
        "id": "bay_767", "name": "767 Bay (Tanker)", "capacity": 150,
        "available": False,
        "meetings_today": [
            {"time": "06:00–07:30", "title": "KC-46 Quality Gate Standup",   "organizer": "QA Team"},
            {"time": "10:00–11:30", "title": "USAF Delivery Readiness Review","organizer": "Customer Ops"},
            {"time": "13:00–14:30", "title": "Tanker Line Production Walk",  "organizer": "VP Operations"},
            {"time": "16:00–17:00", "title": "737 Retrofit Briefing",        "organizer": "Engineering"},
        ],
    },
    "bay_777": {
        "id": "bay_777", "name": "777 Bay (Freighter)", "capacity": 150,
        "available": False,
        "meetings_today": [
            {"time": "08:00–09:30", "title": "777F Final Body Join",         "organizer": "Structures"},
            {"time": "11:00–12:00", "title": "FedEx Delivery Acceptance",    "organizer": "Customer Team"},
            {"time": "15:00–16:00", "title": "Composite Repair Review",      "organizer": "Materials Eng"},
        ],
    },
    "bay_777x": {
        "id": "bay_777x", "name": "777X Bay (WSD)", "capacity": 200,
        "available": True,
        "meetings_today": [
            {"time": "07:30–09:00", "title": "777X Folding Wingtip Test",    "organizer": "Test & Eval"},
            {"time": "10:30–12:00", "title": "FAA Certification Walk",       "organizer": "Regulatory Affairs"},
            {"time": "14:00–15:30", "title": "Emirates Program Review",      "organizer": "Sales & Delivery"},
        ],
    },
    # ── North Support Wing ────────────────────────────────────────────────────
    "visitor_ctr": {
        "id": "visitor_ctr", "name": "Visitor Center", "capacity": 50,
        "available": True,
        "meetings_today": [
            {"time": "09:00–10:30", "title": "Future of Flight Tour Group",  "organizer": "Community Relations"},
            {"time": "13:00–14:00", "title": "School Group Orientation",     "organizer": "Education Outreach"},
        ],
    },
    "safety_ofc": {
        "id": "safety_ofc", "name": "Safety & Training", "capacity": 30,
        "available": False,
        "meetings_today": [
            {"time": "07:00–08:00", "title": "Morning Safety Briefing",      "organizer": "EHS Team"},
            {"time": "09:00–11:30", "title": "Forklift Certification Class", "organizer": "Training Dept"},
            {"time": "14:00–15:00", "title": "Incident Review Board",        "organizer": "Safety Officer"},
        ],
    },
    "north_cafe": {
        "id": "north_cafe", "name": "North Cafeteria", "capacity": 80,
        "available": True,
        "meetings_today": [
            {"time": "11:30–13:00", "title": "Open Seating — Lunch",         "organizer": "Facilities"},
            {"time": "15:00–15:30", "title": "Town Hall — VP Address",       "organizer": "Executive Office"},
        ],
    },
    "quality_ctl": {
        "id": "quality_ctl", "name": "Quality Control", "capacity": 25,
        "available": False,
        "meetings_today": [
            {"time": "06:30–07:30", "title": "Daily Defect Triage",          "organizer": "QA Lead"},
            {"time": "09:00–10:30", "title": "AS9100 Audit Prep",            "organizer": "Quality Systems"},
            {"time": "13:00–14:00", "title": "First Article Inspection",     "organizer": "Inspection Ops"},
        ],
    },
    "delivery": {
        "id": "delivery", "name": "Delivery Center", "capacity": 30,
        "available": True,
        "meetings_today": [
            {"time": "10:00–11:00", "title": "Qatar Airways Handover",       "organizer": "Customer Delivery"},
            {"time": "14:00–15:00", "title": "Documentation Completion Walk","organizer": "Contracts"},
        ],
    },
    # ── South Support Wing ────────────────────────────────────────────────────
    "tool_crib": {
        "id": "tool_crib", "name": "Tool Crib", "capacity": 20,
        "available": True,
        "meetings_today": [
            {"time": "08:00–08:30", "title": "Tool Inventory Audit",         "organizer": "Tooling Ops"},
        ],
    },
    "engineering": {
        "id": "engineering", "name": "Engineering Office", "capacity": 60,
        "available": False,
        "meetings_today": [
            {"time": "08:30–10:00", "title": "Wing Spar Stress Review",      "organizer": "Structures Eng"},
            {"time": "10:30–12:00", "title": "CATIA Design Review — 777X",   "organizer": "CAD Team"},
            {"time": "13:30–15:00", "title": "Supplier NCR Disposition",     "organizer": "Supply Chain"},
            {"time": "15:30–17:00", "title": "GE9X Engine Interface Review", "organizer": "Propulsion Eng"},
        ],
    },
    "south_cafe": {
        "id": "south_cafe", "name": "South Cafeteria", "capacity": 80,
        "available": True,
        "meetings_today": [
            {"time": "11:30–13:00", "title": "Open Seating — Lunch",         "organizer": "Facilities"},
        ],
    },
    "final_asm": {
        "id": "final_asm", "name": "Final Assembly Ctrl", "capacity": 100,
        "available": False,
        "meetings_today": [
            {"time": "07:00–08:00", "title": "Production Rate Standup",      "organizer": "VP Manufacturing"},
            {"time": "09:00–10:30", "title": "Line Stop Resolution — Bay 2", "organizer": "Operations"},
            {"time": "13:00–14:30", "title": "737 Production Rate Review",   "organizer": "Program Office"},
        ],
    },
    "conf_777x": {
        "id": "conf_777x", "name": "777X Design Conf", "capacity": 20,
        "available": True,
        "meetings_today": [
            {"time": "09:00–10:30", "title": "Folding Wingtip PDR",         "organizer": "Advanced Design"},
            {"time": "13:00–14:30", "title": "LH Airlines Spec Review",      "organizer": "Program Mgmt"},
        ],
    },
    "med_center": {
        "id": "med_center", "name": "Medical Center", "capacity": 15,
        "available": True,
        "meetings_today": [
            {"time": "09:00–10:00", "title": "Ergonomics Clinic",            "organizer": "Occupational Health"},
            {"time": "11:00–12:00", "title": "Annual Hearing Tests",         "organizer": "Medical Staff"},
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
