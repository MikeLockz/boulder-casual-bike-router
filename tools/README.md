# Boulder Bike Router - Investigation & Analysis Tools

This directory contains a suite of CLI tools and test scripts used to build, inspect, fetch data for, and verify the routing engine.

---

## 1. Routing and Analysis Tools

### [analyze_route.py](file:///Users/mbp/.gemini/antigravity/scratch/boulder-bike-router/tools/analyze_route.py)
* **Purpose:** Trace and print a detailed segment-by-segment breakdown of the shortest route between two coordinates.
* **When to use:** Use this to debug routing decisions, check final edge costs/multipliers, and verify safe crossings.
* **Usage:**
  ```bash
  ./venv/bin/python3 tools/analyze_route.py <start_lat> <start_lon> <end_lat> <end_lon>
  ```
  Example:
  ```bash
  ./venv/bin/python3 tools/analyze_route.py 40.028446 -105.281088 40.038755 -105.264027
  ```

### [check_local_path.py](file:///Users/mbp/.gemini/antigravity/scratch/boulder-bike-router/tools/check_local_path.py)
* **Purpose:** A lightweight, self-contained pathfinding sanity check that builds a NetworkX graph directly from `backend/boulder_osm_data.json` without loading full GIS overlays or importing backend modules.
* **When to use:** Use this to verify simple graph connectivity and snapping between Cedar Ave and North Boulder Park.

---

## 2. Data Fetching and Syncing Scripts

### [fetch_offstreet.py](file:///Users/mbp/.gemini/antigravity/scratch/boulder-bike-router/tools/fetch_offstreet.py)
* **Purpose:** Fetches the latest off-street paths data from the Boulder Open Data Portal and updates `backend/boulder_bike_offstreet_data.json`.

### [fetch_stress.py](file:///Users/mbp/.gemini/antigravity/scratch/boulder-bike-router/tools/fetch_stress.py)
* **Purpose:** Fetches on-street bikestress GIS datasets from the Boulder Open Data Portal and updates `backend/boulder_bike_stress_data.json`.

### [fetch_playgrounds.py](file:///Users/mbp/.gemini/antigravity/scratch/boulder-bike-router/tools/fetch_playgrounds.py)
* **Purpose:** Fetches the playground locations dataset from the Boulder Open Data Portal and saves it locally.

---

## 3. Graph Node and Edge Inspectors

### [inspect_graph_nodes.py](file:///Users/mbp/.gemini/antigravity/scratch/boulder-bike-router/tools/inspect_graph_nodes.py)
* **Purpose:** Inspects node neighbors, edges, and shortest paths in `G_connected` (specifically target crossing nodes and side1/side2 splits).

### [inspect_crossing_tags.py](file:///Users/mbp/.gemini/antigravity/scratch/boulder-bike-router/tools/inspect_crossing_tags.py)
* **Purpose:** Analyzes OSM crossing node tags (signals, crossing types) in the cached data.

### [inspect_broadway_crossing.py](file:///Users/mbp/.gemini/antigravity/scratch/boulder-bike-router/tools/inspect_broadway_crossing.py)
* **Purpose:** Debugging tool that prints nodes and edges near Broadway crossings.

### [inspect_iris_crossing.py](file:///Users/mbp/.gemini/antigravity/scratch/boulder-bike-router/tools/inspect_iris_crossing.py)
* **Purpose:** Debugging tool that prints nodes and ways near the Iris Ave path crossing.

### [inspect_cedar_geom.py](file:///Users/mbp/.gemini/antigravity/scratch/boulder-bike-router/tools/inspect_cedar_geom.py)
* **Purpose:** Inspects matched stress levels and classifications specifically around Cedar Ave.

### [inspect_park_footways.py](file:///Users/mbp/.gemini/antigravity/scratch/boulder-bike-router/tools/inspect_park_footways.py)
* **Purpose:** Inspects footway segments and tags near North Boulder Park.

### [inspect_stress.py](file:///Users/mbp/.gemini/antigravity/scratch/boulder-bike-router/tools/inspect_stress.py)
* **Purpose:** Debugs the spatial snapping index for bikestress attributes at a target coordinate.

### [get_park_ways.py](file:///Users/mbp/.gemini/antigravity/scratch/boulder-bike-router/tools/get_park_ways.py)
* **Purpose:** Prints coordinates and tags of OSM ways matched near the park boundary.

### [find_all_broadway_ways.py](file:///Users/mbp/.gemini/antigravity/scratch/boulder-bike-router/tools/find_all_broadway_ways.py)
* **Purpose:** Searches the OSM cache and lists all ways named "Broadway".

### [find_close_footways.py](file:///Users/mbp/.gemini/antigravity/scratch/boulder-bike-router/tools/find_close_footways.py)
* **Purpose:** Locates footway segments matching close snapping parameters.

### [get_cache_bbox.py](file:///Users/mbp/.gemini/antigravity/scratch/boulder-bike-router/tools/get_cache_bbox.py)
* **Purpose:** Prints the bounding box coordinates contained inside `boulder_osm_data.json`.

### [count_highways.py](file:///Users/mbp/.gemini/antigravity/scratch/boulder-bike-router/tools/count_highways.py)
* **Purpose:** Prints a counter table of OSM `highway=*` tag occurrences in the cache dataset.

### [search_cache_elements.py](file:///Users/mbp/.gemini/antigravity/scratch/boulder-bike-router/tools/search_cache_elements.py)
* **Purpose:** Simple regex search for tags/attributes inside the OSM cache.

### [search_raw_node.py](file:///Users/mbp/.gemini/antigravity/scratch/boulder-bike-router/tools/search_raw_node.py)
* **Purpose:** Searches for a specific node ID coordinate in the raw cache.

---

## 4. Automated Testing and Verification

### [test_inspect.py](file:///Users/mbp/.gemini/antigravity/scratch/boulder-bike-router/tools/test_inspect.py)
* **Purpose:** Automated test checking the backend `/api/inspect-edge` endpoint (sends requests and asserts the JSON payload structure).
* **Usage:**
  ```bash
  ./venv/bin/python3 tools/test_inspect.py
  ```

### [test_routing_stress.py](file:///Users/mbp/.gemini/antigravity/scratch/boulder-bike-router/tools/test_routing_stress.py)
* **Purpose:** Asserts that custom multipliers for low stress, high stress, multi-use paths, and e-bike restrictions behave correctly.
* **Usage:**
  ```bash
  ./venv/bin/python3 tools/test_routing_stress.py
  ```

### [test_detour.py](file:///Users/mbp/.gemini/antigravity/scratch/boulder-bike-router/tools/test_detour.py)
* **Purpose:** Tests the API detour logic by requesting routes with custom weights (comparing unsafe crossing multiplier = 1.0 vs default).
* **Usage:**
  ```bash
  ./venv/bin/python3 tools/test_detour.py
  ```

### [test_iris_route.py](file:///Users/mbp/.gemini/antigravity/scratch/boulder-bike-router/tools/test_iris_route.py)
* **Purpose:** Validates safe crossing routing across Iris Ave.
* **Usage:**
  ```bash
  ./venv/bin/python3 tools/test_iris_route.py
  ```

### [test_split_graph.py](file:///Users/mbp/.gemini/antigravity/scratch/boulder-bike-router/tools/test_split_graph.py)
* **Purpose:** Tests 4+ lane splitting logic on the graph.

### [test_general_split.py](file:///Users/mbp/.gemini/antigravity/scratch/boulder-bike-router/tools/test_general_split.py)
* **Purpose:** Tests generic splitting of graph edges.

### [test_loops.py](file:///Users/mbp/.gemini/antigravity/scratch/boulder-bike-router/tools/test_loops.py)
* **Purpose:** Validates that the built graph contains no unreachable components or routing loops.

### [test_matching.py](file:///Users/mbp/.gemini/antigravity/scratch/boulder-bike-router/tools/test_matching.py)
* **Purpose:** Runs alignment snapping tests between OSM roads and Boulder GIS Stress data, computing overall matching rates.
