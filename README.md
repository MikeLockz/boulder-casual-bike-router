# Boulder Casual Bike Router

An interactive routing tool designed specifically for casual cyclists in Boulder, Colorado. It parses OpenStreetMap data and uses a custom-weighted NetworkX routing graph to prioritize comfortable cycle paths over busy roadways.

## Key Features
* **Interactive Leaflet Map**: Centered on Boulder, CO with start/end markers.
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
Run the Flask server. On the first run, it will fetch Boulder OSM data via the Overpass API (this takes ~10-15 seconds) and cache it locally as `backend/boulder_osm_data.json` for subsequent instant loads.
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
