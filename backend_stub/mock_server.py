# backend_stub/mock_server.py
from fastapi import FastAPI
import uvicorn

app = FastAPI()

rooms = {
    "room_101": {"id":"room_101","name":"Room 101","capacity":8,"available": True},
    "room_102": {"id":"room_102","name":"Room 102","capacity":6,"available": False}
}

@app.get("/rooms")
def list_rooms():
    return rooms

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)