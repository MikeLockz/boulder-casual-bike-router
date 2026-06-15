# Boulder Casual Bike Router

An interactive routing tool for casual cyclists in Boulder and Broomfield, Colorado. Each region has an isolated OpenStreetMap routing graph and optional municipal comfort data.

## Key Features
* **Independent Regions**: Boulder and Broomfield routing with strict boundary and cross-region validation.
* **Interactive Leaflet Map**: Region-aware start/end markers and overlays.
* **Custom Weight Engine**: Prioritizes separated multi-use paths, quiet residential streets, and sharrows over busy streets.
* **4-Lane Road Blocking**: Automatically blocks routes along 4-lane roads unless they have a sidewalk (in which case it forces sidewalk-speed routing).
* **Sidewalk Routing**: Integrates pedestrian footways, multi-use trails, and road-side sidewalks for safe traversal.
* **Live Slider Adjustments**: Shift the weight multipliers dynamically and see the route update on the map in real-time.
* **Color-Coded Path Infrastructure**: Visualize exactly what infrastructure your route uses (Emerald green for paths, Cyan for sidewalks, etc.).

## Setup & Running

### One-Click Startup (Recommended)
If you are on macOS, you can run both the frontend and backend servers and automatically open the app in your browser with a single command:
```bash
./start.sh
```
Press `Ctrl+C` in your terminal at any time to shut down both servers cleanly.

---

### Manual Setup & Execution

#### 1. Install Dependencies
Make sure you have Python 3 installed. Navigate to the project directory and run:
```bash
pip install -r requirements.txt
```

#### 2. Start the Backend Server
Run the Flask server. Committed Boulder and Broomfield caches avoid network-dependent startup; graph construction continues in a background worker while health endpoints remain available.
```bash
python backend/app.py
```
The backend will run on `http://localhost:3001`.

#### 3. Open the Frontend UI
Since the frontend is static HTML/CSS/JS, you can serve it using a lightweight dev server:
```bash
python -m http.server 8081 --directory frontend
```
Then navigate to `http://localhost:8081` in your browser.

## Region Data & Routing Cache

Routing graphs for each region are constructed and cached as serialized bundles (`.graph-cache.pkl`) in `backend/.graph_cache` (default) or overridden by setting the `GRAPH_CACHE_DIR` environment variable.

- **Warm Startup**: If cache files exist and match the source files' content hashes and region configuration fingerprints, the routing graphs load almost instantly (under 1 second), dramatically reducing startup delay.
- **Cache Invalidation**: Caches are validated on load using chunked content hashing and configuration fingerprints. Proactive cache invalidation is also triggered by the GIS data sync script (`sync_gis_data.py`).
- **Manual Cache Removal**: To force a clean rebuild of the graphs from source JSON files, simply delete the cache files:
  ```bash
  rm -rf backend/.graph_cache/*.graph-cache.pkl
  ```

Refresh Broomfield's paginated Trails cache (which automatically invalidates Broomfield's graph cache):
```bash
./venv/bin/python3 backend/sync_gis_data.py --broomfield
```

Routes must keep their start, destination, and all waypoints inside one region. Clients send an explicit `region`; invalid, unsupported, mismatched, and cross-region requests return structured `400` errors.

`GET /api/health` reports Boulder readiness by default (HTTP 503 while building, HTTP 200 once ready). Use `GET /api/health?region=broomfield` for Broomfield, or `GET /api/graph-status` for all build states.

## Development Mode & Hot Reloader

For local development, enable Flask's debugger and auto-reloader by exporting environment variables:
```bash
export BACKEND_DEBUG=1
export BACKEND_RELOAD=1
```
Or start the project with:
```bash
./start.sh
```
When reloader is enabled, the background graph-initialization thread is gated by the `WERKZEUG_RUN_MAIN` environment variable to ensure it only starts once in the serving child process (preventing duplicate thread compilation overhead in the supervisor process).
