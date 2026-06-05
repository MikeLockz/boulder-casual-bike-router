# Routing Analysis & Weight Tuning Guide

This guide is designed for developers and AI agents to understand how the Boulder bike routing engine constructs its graph, how to analyze routing decisions, and how to evaluate and tune cost multipliers to achieve desired routing outcomes.

---

## 1. Graph Architecture & Cost Formula

The router builds a NetworkX graph (`G_connected`) from OpenStreetMap (OSM) data and overlays it with Boulder Open Data GIS layers (Stress levels and Off-street paths).

### Edge Multiplier Calculation
Every edge $e$ in the graph has a distance in meters (length) and is assigned a cost weight:
$$\text{Weight} = \text{Length} \times \text{Multiplier}$$

The final multiplier is computed dynamically as:
$$\text{Multiplier} = \text{Base Multiplier} \times \text{Facility Modifier} \times \text{Stress Modifier} \times \text{Off-Street Modifier} \times \text{E-Bike Modifier}$$

1. **Base Multiplier**: Derived from OSM highway classification tags (`separated_path`, `residential`, `sharrow_minor`, etc.).
2. **Facility Modifier**: Applied for GIS-authoritative designations (e.g. `facility_designated_route` = `0.55`).
3. **Stress Modifier**: Applied for GIS matched bikestress levels (`stress_low` = `0.7`, `stress_high` = `2.0`). Separated paths default to `Low` stress (`0.7`).
4. **Off-Street Modifier**: Applied for GIS multi-use path status (`offstreet_multiuse` = `0.8`).
5. **E-Bike Modifier**: Applied if e-bikes are restricted on the segment.

---

## 2. Weight Calibration Hierarchy

To prioritize quiet streets and physically separated paths over painted lanes on busy roads, maintain the following hierarchy:

| Infrastructure Type | Base Multiplier | Modifiers Applied | Final Multiplier | Preference Rank |
| :--- | :---: | :---: | :---: | :---: |
| **Separated Multi-Use Path** | `0.5` | `offstreet_multiuse (0.8)` * `stress_low (0.7)` | **`0.28`** | **1 (Highest)** |
| **Designated Route on Residential St** | `0.7` (capped) | `facility_designated_route (0.55)` * `stress_low (0.7)` | **`0.27` - `0.38`** | **2** |
| **Separated Pedestrian Path (Sidewalk)**| `2.0` | `stress_low (0.7)` | **`1.40`** | **3** |
| **Standard Residential St (Undesignated)**| `0.7` | `stress_low (0.7)` | **`0.49`** | **4** |
| **On-Street Painted Lane (Minor St)** | `1.5` (capped) | `facility_onstreet_lane (0.55)` * `stress_low (0.7)` | **`0.58`** | **5** |
| **On-Street Painted Lane (Major St)** | `5.0` (capped) | `facility_onstreet_lane (0.55)` * `stress_low (0.7)` | **`1.93`** | **6 (Lowest)** |

> [!TIP]
> Always ensure that `"facility_onstreet_lane"` is kept high enough (e.g. `0.55` - `0.60`) to avoid giving painted lanes on busier streets a large discount that triggers detours from quiet neighborhood streets.

---

## 3. Step-by-Step Route Debugging Workflow

If a route goes along an undesirable road or detours awkwardly, follow these steps:

### Step 1: Identify Snap Coordinates
Locate the start and end coordinates of the problematic route in decimal degrees (e.g., `40.0284, -105.2798`).

### Step 2: Run Step-by-Step Route Breakdown
Use `analyze_route.py` to run Dijkstra on the CLI and inspect segment-by-segment lengths and multipliers:
```bash
./venv/bin/python3 tools/analyze_route.py <start_lat> <start_lon> <end_lat> <end_lon>
```
* **Output to look for**: Check which segment has an unexpectedly low weight or is bypassing a better street. Identify its name and infrastructure type.

### Step 3: Inspect Raw Edge Attributes
If a specific street segment is suspicious, inspect it using the Flask test client via the inspection endpoint:
```python
# Create a quick script or run curl:
curl "http://localhost:3001/api/inspect-edge?lat=40.0284&lon=-105.2798"
```
* **Verify**: Check the matched `facility_type`, `bikestress`, `offstreet_type`, and raw OSM `tags` to see why it was classified and weighted that way.

---

## 4. How to Write and Run Evaluations

Before committing weight updates, run regression checks to confirm that the changes solve the target problem without breaking existing safety rules.

### 1. Test Detours (Unsafe Crossings)
Ensure the router still forces detours to safe crossings on wide 4+ lane arterials instead of crossing directly at unsafe intersections:
```bash
./venv/bin/python3 tools/test_detour.py
```

### 2. Test Stress Modifiers & Restrictions
Ensure low-stress priorities, off-street priorities, and e-bike/bicycle prohibition rules still work:
```bash
./venv/bin/python3 tools/test_routing_stress.py
```

### 3. Test GIS Layer Matching
Verify that OSM way matching rate against GIS stress layers is high:
```bash
./venv/bin/python3 tools/test_matching.py
```

---

## 5. Deployment Checklist

When weight tuning is finalized:
1. **Sync frontend and backend configs**:
   * Change `DEFAULT_WEIGHTS` dictionary in `backend/app.py`.
   * Change `DEFAULT_WEIGHTS` dictionary in `frontend/app.js`.
   * Change the HTML slider default `value` and `<span class="weight-value">` display text in `frontend/index.html`.
2. **Kill stale python processes** and restart backend cleanly:
   ```bash
   lsof -i :3001
   kill -9 <PID>
   ./start.sh
   ```
3. **Commit and push** to origin to trigger Coolify deployment.
