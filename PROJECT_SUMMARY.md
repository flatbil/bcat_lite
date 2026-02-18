# Indoor 3D Navigation Prototype — Project Summary

Purpose
- Rapid-prototype a secure, lightweight indoor 3D map + turn-by-turn navigation app for Boeing internal use.
- Demonstrate: 3D map visualization, room availability overlays (Outlook rooms later), simple routing, and simulated mobile navigation on Android.
- Prototype must be low-cost (free tools), run on Android for demo, and be extensible to integrate Microsoft Graph and native device positioning later.

Primary constraints & decisions
- Engine: Godot 4.6 (free, light, Android export available).
- Prototype will use a simulated touch-driven location initially. Native Android positioning (ARCore/BLE/Wi‑Fi RTT/UWB) will be added later via an Android plugin.
- Backend: simple local Python FastAPI mock server for room data and route endpoints during development. Later backend will integrate Microsoft Graph and corporate SSO (Boeing WSSO / OIDC/SAML).
- 3D assets: Convert FBX to `glb` (glTF binary). For the demo add a flat plane floor in Blender. Keep `glb` in `assets/models` (or optionally not tracked in git if large).
- No paid subscriptions required for prototype. Use internal Boeing tooling for production later.

High-level architecture
- Godot client (single APK) renders 3D scene, navigation, and UI.
- Mock backend (FastAPI) serves rooms and route data for the demo.
- Simulated location: touch/drag on-screen to move a `player` marker; emits location updates to navigator.
- Later additions:
  - Native Android plugin to gather device location (ARCore/BLE/RTT/UWB) and emit periodic `on_native_location` to Godot.
  - Backend integration with Microsoft Graph to read room calendars and normalize room availability.

How to run the prototype (development)
1. Prerequisites:
   - Godot 4.6 editor installed.
   - Python 3.9+ (for mock backend).
   - Blender (optional, to convert FBX to `glb`).
   - Android Studio + Android SDK if you intend to export to Android.

2. Start mock backend (in `backend_stub/`):
- Install dependencies (optional venv):
  - `python -m venv venv`
  - `source venv/bin/activate` (macOS / Linux) or `venv\Scripts\activate` (Windows)
  - `pip install fastapi uvicorn`
- Run:
  - `python backend_stub/mock_server.py`
- Ensure the server is reachable from your device. If testing on a physical Android device, run the server on a machine on the same Wi‑Fi and use laptop IP (e.g., `http://192.168.1.42:8000`).

3. Configure Godot:
- Open the project in Godot 4.6.
- Make sure `Main.tscn` is the main scene (`Project -> Project Settings -> Run -> Main Scene`).
- Update `scripts/room_manager.gd` `API_BASE` to point at your mock backend IP and port.

4. Run in editor:
- Press play. Use touch/drag (or mouse in editor) to move the simulated device marker on the floor.
- Use UI buttons to request a route to sample rooms. The navigator will compute routes from the simulated position to the room node and display simple step text.

5. Export to Android:
- Install Godot Android export templates if not present.
- Configure Android SDK/NDK paths in `Editor -> Editor Settings -> Export -> Android`.
- Create or use a debug keystore for testing.
- `Project -> Export` -> Add Android preset -> Export `.apk`.
- Install using `adb`:
  - `adb install -r path/to/app.apk`

Project file layout (recommended)
- `project.godot` - Godot project file
- `PROJECT_SUMMARY.md` - this file
- `.gitignore` - recommended ignore (provided separately)
- `scenes/`
  - `Main.tscn` - main scene (root Node3D)
  - `Building.tscn` - building loader (ModelContainer, RoomOverlays)
  - `UI.tscn` - HUD/UI scene (Control root)
- `scripts/`
  - `main.gd` - app glue, scene wiring
  - `building_loader.gd` - load `glb`, register room meshes, create overlays
  - `room_manager.gd` - HTTP fetch of rooms/availability (pluggable API base)
  - `navigator.gd` - nav graph loader and simple A* routing
  - `sim_location.gd` - touch/drag simulated location emitter
  - `ui.gd` - UI logic and route requests
- `assets/`
  - `models/` - `building.glb` (or placeholders)
  - `nav_graph.json` - graph nodes, edges, and room_node_map
- `backend_stub/`
  - `mock_server.py` - minimal FastAPI server returning room data and/or simple routes

Data contracts (backend stub -> client)
- `GET /rooms` -> returns JSON dictionary keyed by room id:
  - Example:
  ```json
  {
    "room_101": {"id":"room_101","name":"Room 101","capacity":8,"available": true}
  }