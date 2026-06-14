import os
import json
import math
import sys
import datetime
import re
import difflib
import threading
import hashlib
import hmac

try:
    import requests
    import networkx as nx
    from flask import Flask, request, jsonify
except ImportError as e:
    missing_module = getattr(e, "name", "dependencies")
    print(f"\n[ERROR] Missing required library: '{missing_module}'")
    print("It looks like you are running the app with the system Python instead of the virtual environment.")
    print("Please run the app using the virtual environment:")
    print("  source venv/bin/activate")
    print("  python backend/app.py")
    print("Or run it directly using the venv executable:")
    print("  ./venv/bin/python3 backend/app.py\n")
    sys.exit(1)

app = Flask(__name__)

# Multi-Region Configuration
REGIONS = {
    "boulder": {
        "name": "Boulder",
        "bbox": (39.96, -105.30, 40.09, -105.18),
        "osm_cache_file": os.path.join(os.path.dirname(__file__), "boulder_osm_data.json"),
        "playgrounds_cache_file": os.path.join(os.path.dirname(__file__), "boulder_playground_data.json"),
        "stress_cache_file": os.path.join(os.path.dirname(__file__), "boulder_bike_stress_data.json"),
        "offstreet_cache_file": os.path.join(os.path.dirname(__file__), "boulder_bike_offstreet_data.json"),
        "playground_url": "https://opendata.arcgis.com/datasets/b1297c2328b343528f70dfd78c6de459_1.geojson",
        "stress_url": "https://opendata.arcgis.com/datasets/e20bc9b72c3b4d0fac167d722a7cf1b7_0.geojson",
        "offstreet_url": "https://opendata.arcgis.com/datasets/8cae0bbbd3154abe8264fa349b8f245f_0.geojson",
    },
    "broomfield": {
        "name": "Broomfield",
        "bbox": (39.88, -105.16, 40.01, -104.99),
        "osm_cache_file": os.path.join(os.path.dirname(__file__), "broomfield_osm_data.json"),
        "playgrounds_cache_file": None,
        "stress_cache_file": None,
        "offstreet_cache_file": None,
        "playground_url": None,
        "stress_url": None,
        "offstreet_url": None,
    }
}

DEFAULT_WEIGHTS = {
    "separated_path": 0.5,
    "sharrow_minor": 1.5,
    "sidewalk": 2.0,
    "residential": 0.7,
    "busy_with_lane": 5.0,
    "busy_with_sharrow": 8.0,
    "busy_undesignated": 15.0,
    "sidewalk_forced": 6.0,
    "crossing_safe": 1.0,
    "crossing_unsafe": 6.0,
    "stress_low": 0.7,
    "stress_high": 2.0,
    "offstreet_multiuse": 0.8,
    "ebike_restricted": 1.0,
    # Boulder GIS FACILITYTYPE bonus multipliers (applied on top of base type)
    # Lower = more preferred. Physical infrastructure beats mere designation.
    "facility_designated_route": 0.55,  # Designated Bike Route — mild preference (no physical infra)
    "facility_protected_lane": 0.20,    # Protected / Separated Bike Lane — physical barrier
    "facility_onstreet_lane": 0.55,     # On-Street Bike Lane (painted) — physical lanes
    "facility_bikeable_shoulder": 0.65, # Bikeable Shoulder
    "facility_contraflow": 0.45         # Contra Flow Bike Lane
}

NAV_METRIC_FILTER = {
    "max_accuracy_meters": 75.0,
    "stationary_radius_meters": 65.0,
    "idle_auto_end_seconds": 2700.0,
    "max_step_speed_mps": 15.0,
}

# In-memory graph storage per region
graphs_by_region = {}
nodes_by_region = {}
safe_crossings_by_region = {}
four_lane_nodes_by_region = {}
bike_routes_geojson_by_region = {}

# Build statuses per region
graph_build_statuses = {}
graph_build_lock = threading.Lock()

def utc_now_iso():
    return datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00", "Z")

def get_default_build_status():
    return {
        "state": "not_started",
        "started_at": None,
        "finished_at": None,
        "last_success_at": None,
        "duration_seconds": None,
        "error": None,
        "nodes": 0,
        "edges": 0,
        "build_id": 0,
    }

def mark_graph_build_started(region_id):
    with graph_build_lock:
        if region_id not in graph_build_statuses:
            graph_build_statuses[region_id] = get_default_build_status()
        graph_build_statuses[region_id].update({
            "state": "building",
            "started_at": utc_now_iso(),
            "finished_at": None,
            "duration_seconds": None,
            "error": None,
            "nodes": 0,
            "edges": 0,
            "build_id": graph_build_statuses[region_id]["build_id"] + 1,
        })

def mark_graph_build_ready(region_id, graph):
    started_at = parse_navigation_date(graph_build_statuses.get(region_id, {}).get("started_at"))
    finished_at = datetime.datetime.now(datetime.timezone.utc)
    duration_seconds = None
    if started_at:
        duration_seconds = round((finished_at - started_at).total_seconds(), 3)
    with graph_build_lock:
        if region_id not in graph_build_statuses:
            graph_build_statuses[region_id] = get_default_build_status()
        graph_build_statuses[region_id].update({
            "state": "ready",
            "finished_at": finished_at.isoformat().replace("+00:00", "Z"),
            "last_success_at": finished_at.isoformat().replace("+00:00", "Z"),
            "duration_seconds": duration_seconds,
            "error": None,
            "nodes": graph.number_of_nodes() if graph is not None else 0,
            "edges": graph.number_of_edges() if graph is not None else 0,
        })

def mark_graph_build_error(region_id, error):
    started_at = parse_navigation_date(graph_build_statuses.get(region_id, {}).get("started_at"))
    finished_at = datetime.datetime.now(datetime.timezone.utc)
    duration_seconds = None
    if started_at:
        duration_seconds = round((finished_at - started_at).total_seconds(), 3)
    with graph_build_lock:
        if region_id not in graph_build_statuses:
            graph_build_statuses[region_id] = get_default_build_status()
        graph_build_statuses[region_id].update({
            "state": "error",
            "finished_at": finished_at.isoformat().replace("+00:00", "Z"),
            "duration_seconds": duration_seconds,
            "error": str(error),
            "nodes": 0,
            "edges": 0,
        })

def get_graph_build_status(region_id):
    with graph_build_lock:
        status = dict(graph_build_statuses.get(region_id, get_default_build_status()))
    status["ready"] = graphs_by_region.get(region_id) is not None and status.get("state") == "ready"
    return status

def haversine_distance(coord1, coord2):
    """Calculate the great-circle distance between two points in meters."""
    lat1, lon1 = coord1
    lat2, lon2 = coord2
    R = 6371000  # Earth's radius in meters
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    delta_phi = math.radians(lat2 - lat1)
    delta_lambda = math.radians(lon2 - lon1)
    a = math.sin(delta_phi/2)**2 + math.cos(phi1) * math.cos(phi2) * math.sin(delta_lambda/2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
    return R * c

def parse_navigation_date(value):
    """Parse PocketBase/client ISO timestamps as UTC datetimes."""
    if not value:
        return None
    if isinstance(value, datetime.datetime):
        date_value = value
    else:
        date_str = str(value).strip()
        if not date_str:
            return None
        date_str = date_str.replace("Z", "+00:00")
        if " " in date_str and "T" not in date_str:
            date_str = date_str.replace(" ", "T", 1)
        try:
            date_value = datetime.datetime.fromisoformat(date_str)
        except ValueError:
            if "." in date_str:
                try:
                    date_value = datetime.datetime.fromisoformat(date_str.split(".")[0] + "+00:00")
                except ValueError:
                    return None
            else:
                return None
    if date_value.tzinfo is None:
        date_value = date_value.replace(tzinfo=datetime.timezone.utc)
    return date_value.astimezone(datetime.timezone.utc)

def route_date_sort_key(item):
    parsed = parse_navigation_date(item.get("started_at"))
    return parsed or datetime.datetime.min.replace(tzinfo=datetime.timezone.utc)

def sorted_navigation_ticks(ticks):
    return sorted(
        [tick for tick in ticks if isinstance(tick, dict)],
        key=lambda tick: parse_navigation_date(tick.get("timestamp")) or datetime.datetime.min.replace(tzinfo=datetime.timezone.utc)
    )

def usable_navigation_tick(tick):
    lat = tick.get("lat")
    lon = tick.get("lon")
    timestamp = parse_navigation_date(tick.get("timestamp"))
    if lat is None or lon is None or not timestamp:
        return None
    try:
        lat = float(lat)
        lon = float(lon)
    except (TypeError, ValueError):
        return None
    if not (-90.0 <= lat <= 90.0 and -180.0 <= lon <= 180.0):
        return None
    accuracy = tick.get("accuracy")
    if accuracy is not None:
        try:
            if float(accuracy) > NAV_METRIC_FILTER["max_accuracy_meters"]:
                return None
        except (TypeError, ValueError):
            pass
    return {**tick, "lat": lat, "lon": lon, "_parsed_timestamp": timestamp}

def filtered_navigation_tick_summary(ticks):
    """Apply the shared navigation metric filter to remove stale idle jitter."""
    usable_ticks = [tick for tick in (usable_navigation_tick(t) for t in sorted_navigation_ticks(ticks)) if tick]
    if not usable_ticks:
        return {"ticks": [], "distance_meters": 0.0, "started_at": None, "ended_at": None, "idle_cutoff_at": None}

    kept_ticks = [usable_ticks[0]]
    anchor_tick = usable_ticks[0]
    distance_meters = 0.0
    idle_cutoff_at = None

    for tick in usable_ticks[1:]:
        anchor_time = anchor_tick["_parsed_timestamp"]
        tick_time = tick["_parsed_timestamp"]
        elapsed = max(0.0, (tick_time - anchor_time).total_seconds())
        step_distance = haversine_distance((anchor_tick["lat"], anchor_tick["lon"]), (tick["lat"], tick["lon"]))

        if elapsed > 0 and (step_distance / elapsed) > NAV_METRIC_FILTER["max_step_speed_mps"]:
            continue

        if step_distance <= NAV_METRIC_FILTER["stationary_radius_meters"]:
            if elapsed >= NAV_METRIC_FILTER["idle_auto_end_seconds"]:
                idle_cutoff_at = anchor_time + datetime.timedelta(seconds=NAV_METRIC_FILTER["idle_auto_end_seconds"])
                break
            kept_ticks.append(tick)
            continue

        distance_meters += step_distance
        anchor_tick = tick
        kept_ticks.append(tick)

    return {
        "ticks": kept_ticks,
        "distance_meters": distance_meters,
        "started_at": kept_ticks[0]["_parsed_timestamp"] if kept_ticks else None,
        "ended_at": kept_ticks[-1]["_parsed_timestamp"] if kept_ticks else None,
        "idle_cutoff_at": idle_cutoff_at
    }

def calculate_tick_distance_meters(ticks):
    return filtered_navigation_tick_summary(ticks).get("distance_meters", 0.0)

def calculate_route_duration_seconds(route, ended_at=None, ticks=None):
    start_time = parse_navigation_date(route.get("started_at"))
    end_time = parse_navigation_date(ended_at or route.get("ended_at"))
    if start_time and end_time:
        duration = (end_time - start_time).total_seconds()
        if duration > 0:
            return duration

    sorted_ticks = sorted_navigation_ticks(ticks or [])
    if len(sorted_ticks) >= 2:
        first_tick = parse_navigation_date(sorted_ticks[0].get("timestamp"))
        last_tick = parse_navigation_date(sorted_ticks[-1].get("timestamp"))
        if first_tick and last_tick:
            duration = (last_tick - first_tick).total_seconds()
            if duration > 0:
                return duration
    return 0.0

def calculate_navigation_metrics(route, ticks=None, ended_at=None, status=None):
    """Return canonical actual and presentation metrics for a navigation route."""
    ticks = ticks or []
    tick_summary = filtered_navigation_tick_summary(ticks)
    actual_distance = tick_summary["distance_meters"]
    effective_ended_at = ended_at
    if tick_summary.get("idle_cutoff_at"):
        parsed_ended_at = parse_navigation_date(ended_at)
        if not parsed_ended_at or parsed_ended_at > tick_summary["idle_cutoff_at"]:
            effective_ended_at = tick_summary["idle_cutoff_at"].isoformat().replace("+00:00", "Z")
    actual_duration = calculate_route_duration_seconds(route, ended_at=effective_ended_at or ended_at, ticks=tick_summary["ticks"])

    total_length = float(route.get("total_length_meters") or 0.0)
    total_duration = float(route.get("total_estimated_time_seconds") or 0.0)
    route_status = status or route.get("status")

    if route_status == "completed" and total_length > 0 and actual_distance < total_length * 0.25:
        actual_distance = total_length

    average_speed = actual_distance / actual_duration if actual_duration > 0 else 0.0

    stored_actual_distance = float(route.get("actual_distance_meters") or 0.0)
    stored_actual_duration = float(route.get("actual_duration_seconds") or 0.0)
    display_distance = actual_distance if actual_distance > 0 else (stored_actual_distance if stored_actual_distance > 0 else total_length)
    display_duration = actual_duration if actual_duration > 0 else (stored_actual_duration if stored_actual_duration > 0 else total_duration)
    if (
        display_distance > 500
        and total_duration > 0
        and (
            display_duration <= 0
            or display_duration < 60
            or (display_distance / display_duration) > 15.0
        )
    ):
        display_duration = total_duration
    display_average_speed = display_distance / display_duration if display_duration > 0 else 0.0

    return {
        "actual_distance_meters": actual_distance,
        "actual_duration_seconds": actual_duration,
        "average_speed": average_speed,
        "display_distance_meters": display_distance,
        "display_duration_seconds": display_duration,
        "display_average_speed": display_average_speed,
        "_idle_cutoff_at": tick_summary["idle_cutoff_at"].isoformat().replace("+00:00", "Z") if tick_summary.get("idle_cutoff_at") else None
    }

def navigation_metrics_payload(metrics):
    return {key: value for key, value in metrics.items() if not key.startswith("_")}

def route_with_display_metrics(route):
    route_copy = dict(route)
    route_copy.pop("guest_owner_hash", None)
    display_distance = route_copy.get("display_distance_meters")
    if not display_distance or float(display_distance or 0) <= 0:
        display_distance = route_copy.get("actual_distance_meters") or route_copy.get("total_length_meters") or 0.0

    display_duration = route_copy.get("display_duration_seconds")
    if not display_duration or float(display_duration or 0) <= 0:
        display_duration = route_copy.get("actual_duration_seconds") or route_copy.get("total_estimated_time_seconds") or 0.0

    display_average_speed = route_copy.get("display_average_speed")
    total_duration = float(route_copy.get("total_estimated_time_seconds") or 0.0)
    if (
        float(display_distance or 0.0) > 500
        and total_duration > 0
        and (
            float(display_duration or 0.0) <= 0
            or float(display_duration or 0.0) < 60
            or (float(display_distance or 0.0) / float(display_duration or 1.0)) > 15.0
        )
    ):
        display_duration = total_duration
        display_average_speed = float(display_distance or 0.0) / total_duration
    if display_average_speed is None:
        display_average_speed = float(display_distance or 0.0) / float(display_duration or 0.0) if float(display_duration or 0.0) > 0 else 0.0

    route_copy["display_distance_meters"] = display_distance
    route_copy["display_duration_seconds"] = display_duration
    route_copy["display_average_speed"] = display_average_speed
    return route_copy

def fetch_osm_data(region_id):
    """Fetch OpenStreetMap data for specified region from Overpass API or load from cache."""
    config = REGIONS[region_id]
    cache_file = config["osm_cache_file"]
    if os.path.exists(cache_file):
        print(f"Loading {region_id} OSM data from cache...")
        with open(cache_file, "r") as f:
            return json.load(f)
            
    print(f"Fetching {region_id} OSM data from Overpass API (this may take a few seconds)...")
    s, w, n, e = config["bbox"]
    overpass_url = "https://overpass-api.de/api/interpreter"
    overpass_query = f"""
    [out:json][timeout:180];
    (
      way["highway"]({s},{w},{n},{e});
    );
    out body;
    >;
    out body qt;
    """
    
    headers = {
        "User-Agent": "BoulderCasualBikeRouter/1.0 (contact: support@bouldercasualrouter.local)"
    }
    response = requests.post(overpass_url, data={"data": overpass_query}, headers=headers)
    response.raise_for_status()
    data = response.json()
    
    # Save cache
    with open(cache_file, "w") as f:
        json.dump(data, f)
        
    return data

def fetch_playground_data(region_id):
    """Fetch playground locations data for specified region or load from cache."""
    config = REGIONS[region_id]
    cache_file = config["playgrounds_cache_file"]
    url = config["playground_url"]
    
    if not cache_file or not url:
        return {"type": "FeatureCollection", "features": []}

    if os.path.exists(cache_file):
        try:
            with open(cache_file, "r") as f:
                return json.load(f)
        except Exception as e:
            print(f"Error reading playgrounds cache for {region_id}: {e}")
            
    print(f"Fetching playground data from Open Data portal for {region_id}...")
    headers = {
        "User-Agent": "BoulderCasualBikeRouter/1.0 (contact: support@bouldercasualrouter.local)"
    }
    try:
        response = requests.get(url, headers=headers, timeout=30)
        response.raise_for_status()
        data = response.json()
        
        # Save cache
        with open(cache_file, "w") as f:
            json.dump(data, f)
        return data
    except Exception as e:
        print(f"Error fetching playground data for {region_id}: {e}")
        # Return cache if available as a fallback
        if os.path.exists(cache_file):
            with open(cache_file, "r") as f:
                return json.load(f)
        raise e

def fetch_stress_data(region_id):
    """Fetch bike stress data for specified region or load from cache."""
    config = REGIONS[region_id]
    cache_file = config["stress_cache_file"]
    url = config["stress_url"]
    
    if not cache_file or not url:
        return {"type": "FeatureCollection", "features": []}

    if os.path.exists(cache_file):
        try:
            with open(cache_file, "r") as f:
                return json.load(f)
        except Exception as e:
            print(f"Error reading stress cache for {region_id}: {e}")
            
    print(f"Fetching bike stress data from Open Data portal for {region_id}...")
    headers = {
        "User-Agent": "BoulderCasualBikeRouter/1.0 (contact: support@bouldercasualrouter.local)"
    }
    try:
        response = requests.get(url, headers=headers, timeout=30)
        response.raise_for_status()
        data = response.json()
        with open(cache_file, "w") as f:
            json.dump(data, f)
        return data
    except Exception as e:
        print(f"Error fetching bike stress data for {region_id}: {e}")
        if os.path.exists(cache_file):
            with open(cache_file, "r") as f:
                return json.load(f)
        raise e

def fetch_offstreet_data(region_id):
    """Fetch bike off-street data for specified region or load from cache."""
    config = REGIONS[region_id]
    cache_file = config["offstreet_cache_file"]
    url = config["offstreet_url"]
    
    if not cache_file or not url:
        return {"type": "FeatureCollection", "features": []}

    if os.path.exists(cache_file):
        try:
            with open(cache_file, "r") as f:
                return json.load(f)
        except Exception as e:
            print(f"Error reading off-street cache for {region_id}: {e}")
            
    print(f"Fetching bike off-street data from Open Data portal for {region_id}...")
    headers = {
        "User-Agent": "BoulderCasualBikeRouter/1.0 (contact: support@bouldercasualrouter.local)"
    }
    try:
        response = requests.get(url, headers=headers, timeout=30)
        response.raise_for_status()
        data = response.json()
        with open(cache_file, "w") as f:
            json.dump(data, f)
        return data
    except Exception as e:
        print(f"Error fetching bike off-street data for {region_id}: {e}")
        if os.path.exists(cache_file):
            with open(cache_file, "r") as f:
                return json.load(f)
        raise e


def point_to_segment_distance(pt, seg_start, seg_end):
    lat, lon = pt
    lat1, lon1 = seg_start
    lat2, lon2 = seg_end
    
    avg_lat = math.radians((lat + lat1 + lat2) / 3.0)
    lat_scale = 111000.0
    lon_scale = 111000.0 * math.cos(avg_lat)
    
    py = (lat - lat1) * lat_scale
    px = (lon - lon1) * lon_scale
    
    sey = (lat2 - lat1) * lat_scale
    sex = (lon2 - lon1) * lon_scale
    
    seg_len_sq = sex*sex + sey*sey
    if seg_len_sq == 0.0:
        return math.sqrt(px*px + py*py)
        
    t = (px * sex + py * sey) / seg_len_sq
    t = max(0.0, min(1.0, t))
    
    cpx = t * sex
    cpy = t * sey
    
    dx = px - cpx
    dy = py - cpy
    return math.sqrt(dx*dx + dy*dy)

def get_segment_bearing(lat1, lon1, lat2, lon2):
    dlon = math.radians(lon2 - lon1)
    lat1_r = math.radians(lat1)
    lat2_r = math.radians(lat2)
    
    y = math.sin(dlon) * math.cos(lat2_r)
    x = math.cos(lat1_r) * math.sin(lat2_r) - math.sin(lat1_r) * math.cos(lat2_r) * math.cos(dlon)
    bearing = math.atan2(y, x)
    return (math.degrees(bearing) + 360) % 360

def bearing_difference_undirected(b1, b2):
    diff = abs(b1 - b2) % 360
    if diff > 180:
        diff = 360 - diff
    if diff > 90:
        diff = 180 - diff
    return diff

class SpatialGridIndex:
    def __init__(self, cell_size=0.001):
        self.cell_size = cell_size
        self.grid = {}

    def _get_cell(self, lat, lon):
        return int(lat / self.cell_size), int(lon / self.cell_size)

    def add_segment(self, lat1, lon1, lat2, lon2, feature_idx, properties):
        # Prevent indexing segments with invalid lat/lon or extreme coordinates
        if not (-90.0 <= lat1 <= 90.0) or not (-180.0 <= lon1 <= 180.0):
            return
        if not (-90.0 <= lat2 <= 90.0) or not (-180.0 <= lon2 <= 180.0):
            return
            
        # Protect against long lines (e.g. diagonal lines spanning the globe)
        if abs(lat1 - lat2) > 0.05 or abs(lon1 - lon2) > 0.05:
            return

        min_lat, max_lat = min(lat1, lat2), max(lat1, lat2)
        min_lon, max_lon = min(lon1, lon2), max(lon1, lon2)
        
        start_cell_x, start_cell_y = self._get_cell(min_lat, min_lon)
        end_cell_x, end_cell_y = self._get_cell(max_lat, max_lon)
        
        # Double check cell span is reasonable
        if (end_cell_x - start_cell_x > 50) or (end_cell_y - start_cell_y > 50):
            return
            
        # Precalculate bearing once
        bearing = get_segment_bearing(lat1, lon1, lat2, lon2)
        segment_data = (lat1, lon1, lat2, lon2, feature_idx, properties, bearing)
        
        for x in range(start_cell_x, end_cell_x + 1):
            for y in range(start_cell_y, end_cell_y + 1):
                cell_key = (x, y)
                if cell_key not in self.grid:
                    self.grid[cell_key] = []
                self.grid[cell_key].append(segment_data)

    def query_nearest_with_bearing(self, lat, lon, osm_bearing, max_dist_meters=15.0, bearing_tolerance=30.0):
        cell_x, cell_y = self._get_cell(lat, lon)
        candidates = []
        
        for dx in [-1, 0, 1]:
            for dy in [-1, 0, 1]:
                cell_key = (cell_x + dx, cell_y + dy)
                if cell_key in self.grid:
                    candidates.extend(self.grid[cell_key])
                    
        if not candidates:
            return None
            
        best_candidate = None
        min_dist = float('inf')
        checked_segments = set()
        
        for lat1, lon1, lat2, lon2, feat_idx, props, gis_bearing in candidates:
            seg_key = (lat1, lon1, lat2, lon2, feat_idx)
            if seg_key in checked_segments:
                continue
            checked_segments.add(seg_key)
            
            if bearing_difference_undirected(osm_bearing, gis_bearing) > bearing_tolerance:
                continue
                
            dist = point_to_segment_distance((lat, lon), (lat1, lon1), (lat2, lon2))
            if dist < min_dist:
                min_dist = dist
                best_candidate = (props, dist)
                
        if min_dist <= max_dist_meters:
            return best_candidate
        return None


def calculate_centroid(pts):
    """Calculate exact centroid of a 2D polygon using shifted coordinates to avoid floating point cancellation."""
    if not pts:
        return 0.0, 0.0
    # Use first point as offset to prevent precision loss with large coordinates
    offset_x, offset_y = pts[0]
    shifted_pts = [[x - offset_x, y - offset_y] for x, y in pts]
    A = 0.0
    Cx = 0.0
    Cy = 0.0
    for i in range(len(shifted_pts) - 1):
        x0, y0 = shifted_pts[i]
        x1, y1 = shifted_pts[i+1]
        factor = (x0 * y1 - x1 * y0)
        A += factor
        Cx += (x0 + x1) * factor
        Cy += (y0 + y1) * factor
    A = 0.5 * A
    if A == 0.0:
        # Fallback to average of unique vertices
        unique_pts = pts[:-1] if len(pts) > 1 and pts[0] == pts[-1] else pts
        return sum(p[1] for p in unique_pts) / len(unique_pts), sum(p[0] for p in unique_pts) / len(unique_pts)
    
    Cx = Cx / (6 * A) + offset_x  # Longitude (x)
    Cy = Cy / (6 * A) + offset_y  # Latitude (y)
    return Cy, Cx  # Returns (lat, lon)

def get_way_class_and_multiplier(tags, weights, way_nodes=None, safe_crossing_nodes=None, node_highways=None):
    """Categorize the way and return its infrastructure type and weighting multiplier."""
    highway = tags.get("highway", "")
    cycleway = tags.get("cycleway", "")
    cycleway_left = tags.get("cycleway:left", "")
    cycleway_right = tags.get("cycleway:right", "")
    cycleway_both = tags.get("cycleway:both", "")
    sidewalk = tags.get("sidewalk", "")
    bicycle = tags.get("bicycle", "")
    
    # Check for crossings first
    is_crossing = (tags.get("footway") == "crossing" or tags.get("cycleway") == "crossing" or highway == "crossing")
    if is_crossing and way_nodes and safe_crossing_nodes is not None and node_highways is not None:
        intersects_busy = False
        intersects_safe_node = False
        
        for node_id in way_nodes:
            # Check if this node touches a busy street
            busy_types = ["primary", "primary_link", "secondary", "secondary_link", "tertiary", "tertiary_link"]
            node_ways = node_highways.get(node_id, set())
            if any(bt in node_ways for bt in busy_types):
                intersects_busy = True
            if node_id in safe_crossing_nodes:
                intersects_safe_node = True
                
        if intersects_busy:
            if intersects_safe_node:
                return "crossing_safe", weights.get("crossing_safe", 1.0)
            else:
                return "crossing_unsafe", weights.get("crossing_unsafe", 3.0)
        else:
            # Crosses a quiet street or footpath connector: comfortable
            return "crossing_safe", weights.get("crossing_safe", 1.0)

    # Block motorways and trunks entirely
    if highway in ["motorway", "motorway_link", "trunk", "trunk_link"]:
        return "blocked", 999999.0
        
    # Check lanes count
    lanes_str = tags.get("lanes", "")
    try:
        if ";" in lanes_str:
            lanes = max([int(x) for x in lanes_str.split(";") if x.isdigit()])
        else:
            lanes = int(lanes_str) if lanes_str.isdigit() else 2
    except:
        lanes = 2

    # Check forward/backward lanes
    try:
        lanes_fwd = int(tags.get("lanes:forward", "0"))
        lanes_bwd = int(tags.get("lanes:backward", "0"))
        if lanes_fwd + lanes_bwd > 0:
            lanes = lanes_fwd + lanes_bwd
    except:
        pass

    has_sidewalk = (sidewalk in ["yes", "both", "left", "right", "shared"]) or \
                   ("sidewalk:left" in tags) or ("sidewalk:right" in tags) or ("sidewalk:both" in tags)

    has_track = (cycleway == "track") or (cycleway_left == "track") or (cycleway_right == "track") or (cycleway_both == "track")

    # Check for standard bike lanes (on-street painted)
    has_bike_lane = (cycleway in ["lane", "opposite_lane"]) or \
                    (cycleway_left in ["lane", "opposite_lane"]) or \
                    (cycleway_right in ["lane", "opposite_lane"]) or \
                    (cycleway_both in ["lane", "opposite_lane"])

    # Check for separated cycle tracks or dedicated paths first
    if highway == "cycleway" or (highway in ["path", "footway"] and bicycle in ["yes", "designated"]) or has_track:
        return "separated_path", weights.get("separated_path", 0.5)

    # 4+ Lane Block Rules
    if lanes >= 4:
        if has_bike_lane:
            return "busy_with_lane", weights.get("busy_with_lane", 5.0)
        elif not has_sidewalk:
            return "blocked", 999999.0
        else:
            return "sidewalk_forced", weights.get("sidewalk_forced", 6.0)

    # Check for sharrows
    has_sharrow = (cycleway == "shared_lane") or (cycleway_left == "shared_lane") or (cycleway_right == "shared_lane") or (cycleway_both == "shared_lane")

    # Separate sidewalks / footways / pedestrian paths
    if highway in ["footway", "pedestrian", "path"] or tags.get("footway") == "sidewalk":
        return "sidewalk", weights.get("sidewalk", 2.0)

    # Quiet residential streets
    if highway in ["residential", "living_street", "service"]:
        if has_sharrow:
            return "sharrow_minor", weights.get("sharrow_minor", 1.5)
        elif has_bike_lane:
            # High quality bike lane on quiet street counts as a separated path quality for comfort
            return "separated_path", weights.get("separated_path", 0.5)
        else:
            return "residential", weights.get("residential", 1.0)

    # Busy streets (primary, secondary, tertiary)
    if highway in ["primary", "primary_link", "secondary", "secondary_link", "tertiary", "tertiary_link"]:
        if has_bike_lane:
            is_designated = bicycle in ["yes", "designated"]
            if is_designated and lanes <= 2 and highway in ["tertiary", "tertiary_link", "unclassified"]:
                # Dedicated painted bike lanes + designated on a low-speed tertiary
                # → treat as sharrow_minor quality
                return "sharrow_minor", weights.get("sharrow_minor", 1.5)
            else:
                # Primary/secondary or high-lane-count: still a busy road with lane
                return "busy_with_lane", weights.get("busy_with_lane", 3.0)
        elif has_sharrow:
            is_designated = bicycle in ["yes", "designated"]
            if is_designated and lanes <= 2 and highway in ["tertiary", "tertiary_link", "unclassified"]:
                return "sharrow_minor", weights.get("sharrow_minor", 1.3)
            else:
                return "busy_with_sharrow", weights.get("busy_with_sharrow", 6.0)
        elif has_sidewalk:
            return "sidewalk", weights.get("sidewalk", 2.0)
        else:
            return "busy_undesignated", weights.get("busy_undesignated", 15.0)

    # Fall-through defaults
    if has_bike_lane:
        return "busy_with_lane", weights.get("busy_with_lane", 3.0)
    return "residential", weights.get("residential", 1.2)



def match_stress_for_edge(u, v, nodes, spatial_index):
    """Returns (stress_level, facility_type) tuple from Boulder GIS stress data."""
    if not spatial_index or u not in nodes or v not in nodes:
        return "None", "None"
    lat_u, lon_u = nodes[u]["lat"], nodes[u]["lon"]
    lat_v, lon_v = nodes[v]["lat"], nodes[v]["lon"]
    
    midpoint = ((lat_u + lat_v) / 2.0, (lon_u + lon_v) / 2.0)
    osm_bearing = get_segment_bearing(lat_u, lon_u, lat_v, lon_v)
    
    match = spatial_index.query_nearest_with_bearing(
        midpoint[0], midpoint[1], osm_bearing, 
        max_dist_meters=15.0, bearing_tolerance=30.0
    )
    if match:
        props, dist = match
        stress = props.get("BIKESTRESS", "None") or "None"
        facility = props.get("FACILITYTYPE", "None") or "None"
        return stress, facility
    return "None", "None"

def match_offstreet_for_edge(u, v, nodes, spatial_index):
    if not spatial_index or u not in nodes or v not in nodes:
        return "None", "Yes", "Yes"
    lat_u, lon_u = nodes[u]["lat"], nodes[u]["lon"]
    lat_v, lon_v = nodes[v]["lat"], nodes[v]["lon"]

    midpoint = ((lat_u + lat_v) / 2.0, (lon_u + lon_v) / 2.0)
    osm_bearing = get_segment_bearing(lat_u, lon_u, lat_v, lon_v)

    match = spatial_index.query_nearest_with_bearing(
        midpoint[0], midpoint[1], osm_bearing,
        max_dist_meters=15.0, bearing_tolerance=30.0
    )
    if match:
        props, dist = match
        facility_type = props.get("FACILITYTYPE", "None") or "None"

        # Sidewalks and pedestrian paths run alongside roads and will naturally
        # snap onto the adjacent road edge. Their BICYCLES=No means the SIDEWALK
        # itself is ped-only — it must NOT block the road running next to it.
        PEDESTRIAN_ONLY_TYPES = {"Sidewalk", "Pedestrian Path", "Pedestrian Overpass",
                                  "Pedestrian Underpass", "Plaza Path"}
        if facility_type in PEDESTRIAN_ONLY_TYPES:
            return (facility_type, "Yes", "Yes")

        return (
            facility_type,
            props.get("BICYCLES", "Yes") or "Yes",
            props.get("EBIKE", "Yes") or "Yes"
        )
    return "None", "Yes", "Yes"


def _bike_edge_direction(tags, infra_type):
    """
    Determines valid travel direction(s) for a bike on this OSM way.
    Returns: "both" | "forward" | "reverse"
    """
    oneway = tags.get("oneway", "")
    bike_oneway = tags.get("oneway:bicycle", "")

    # Dedicated bike infrastructure is bidirectional unless explicitly one-way for bikes.
    if infra_type == "separated_path":
        return "forward" if bike_oneway == "yes" else "both"

    return "both"


def build_graph(region_id="boulder", weights=None):
    """Build the NetworkX routing graph from OSM JSON data for the specified region."""
    mark_graph_build_started(region_id)
    if weights is None:
        weights = DEFAULT_WEIGHTS

    try:
        data = fetch_osm_data(region_id)
    except Exception as e:
        print(f"CRITICAL ERROR: Failed to fetch OSM data for {region_id}: {e}")
        print(f"Graph for {region_id} will not be built. Routing will be unavailable.")
        mark_graph_build_error(region_id, e)
        return None

    G = nx.DiGraph()
    config = REGIONS[region_id]

    # Load stress data and build spatial index (if configured)
    spatial_index = None
    if config.get("stress_cache_file"):
        try:
            stress_data = fetch_stress_data(region_id)
            spatial_index = SpatialGridIndex(cell_size=0.001)
            for idx, feature in enumerate(stress_data.get("features", [])):
                geom = feature.get("geometry", {})
                props = feature.get("properties", {})
                if geom.get("type") == "LineString":
                    coords = geom.get("coordinates", [])
                    for i in range(len(coords) - 1):
                        lon1, lat1 = coords[i]
                        lon2, lat2 = coords[i+1]
                        spatial_index.add_segment(lat1, lon1, lat2, lon2, idx, props)
            print(f"Bicycle stress spatial index built successfully for {region_id}.")
        except Exception as e:
            print(f"Error building bicycle stress spatial index for {region_id}: {e}")
            spatial_index = None

    # Load off-street data and build spatial index (if configured)
    offstreet_spatial_index = None
    if config.get("offstreet_cache_file"):
        try:
            offstreet_data = fetch_offstreet_data(region_id)
            offstreet_spatial_index = SpatialGridIndex(cell_size=0.001)
            for idx, feature in enumerate(offstreet_data.get("features", [])):
                geom = feature.get("geometry", {})
                props = feature.get("properties", {})
                if geom.get("type") == "LineString":
                    coords = geom.get("coordinates", [])
                    for i in range(len(coords) - 1):
                        lon1, lat1 = coords[i]
                        lon2, lat2 = coords[i+1]
                        offstreet_spatial_index.add_segment(lat1, lon1, lat2, lon2, idx, props)
            print(f"Off-street spatial index built successfully for {region_id}.")
        except Exception as e:
            print(f"Error building off-street spatial index for {region_id}: {e}")
            offstreet_spatial_index = None



    # Phase 1: Parse nodes & map network topology for crossings
    node_highways = {}
    safe_crossing_nodes = set()
    nodes = {}
    
    for element in data.get("elements", []):
        if element.get("type") == "node":
            node_id = element["id"]
            nodes[node_id] = {
                "lat": element["lat"],
                "lon": element["lon"],
                "tags": element.get("tags", {})
            }
            node_tags = element.get("tags", {})
            highway = node_tags.get("highway", "")
            crossing = node_tags.get("crossing", "")
            
            is_safe = False
            if highway == "traffic_signals":
                is_safe = True
            elif highway == "crossing":
                is_safe = (
                    crossing in ["traffic_signals", "toucan", "pelican", "pegasus", "controlled", "marked", "zebra"] or
                    node_tags.get("crossing:signals") == "yes" or
                    node_tags.get("crossing:signals:pedestrian") == "yes" or
                    node_tags.get("flashing_lights") in ["yes", "button"] or
                    node_tags.get("crossing:bicycle") in ["yes", "designated"] or
                    node_tags.get("crossing:markings") in ["yes", "marked", "zebra", "surface"]
                )
            
            if is_safe:
                safe_crossing_nodes.add(node_id)
                    
        elif element.get("type") == "way":
            way_nodes = element.get("nodes", [])
            way_tags = element.get("tags", {})
            highway = way_tags.get("highway", "")
            if highway:
                for node_id in way_nodes:
                    if node_id not in node_highways:
                        node_highways[node_id] = set()
                    node_highways[node_id].add(highway)

    # Pre-identify all ways that have lanes >= 4
    four_lane_ways = {}
    four_lane_nodes = set()
    node_to_four_lane_ways = {}
    way_orientations = {}
    
    for element in data.get("elements", []):
        if element.get("type") == "way":
            way_id = element["id"]
            way_nodes = element.get("nodes", [])
            tags = element.get("tags", {})
            highway = tags.get("highway", "")
            if not highway or highway in ["motorway", "motorway_link", "trunk", "trunk_link"]:
                continue
                
            lanes_str = tags.get("lanes", "")
            try:
                if ";" in lanes_str:
                    lanes = max([int(x) for x in lanes_str.split(";") if x.isdigit()])
                else:
                    lanes = int(lanes_str) if lanes_str.isdigit() else 2
            except:
                lanes = 2
                
            try:
                lanes_fwd = int(tags.get("lanes:forward", "0"))
                lanes_bwd = int(tags.get("lanes:backward", "0"))
                if lanes_fwd + lanes_bwd > 0:
                    lanes = lanes_fwd + lanes_bwd
            except:
                pass
                
            if lanes >= 4:
                four_lane_ways[way_id] = tags
                for nid in way_nodes:
                    four_lane_nodes.add(nid)
                    if nid not in node_to_four_lane_ways:
                        node_to_four_lane_ways[nid] = set()
                    node_to_four_lane_ways[nid].add(way_id)
                
                # Determine orientation
                lats = [nodes[n]["lat"] for n in way_nodes if n in nodes]
                lons = [nodes[n]["lon"] for n in way_nodes if n in nodes]
                if lats and lons:
                    lat_span = max(lats) - min(lats)
                    lon_span = max(lons) - min(lons)
                    orientation = "NS" if lat_span > lon_span else "EW"
                else:
                    orientation = "NS"
                way_orientations[way_id] = orientation

    # Phase 2: Parse ways and create edges
    for element in data.get("elements", []):
        if element.get("type") == "way":
            way_id = element["id"]
            tags = element.get("tags", {})
            way_nodes = element.get("nodes", [])
            
            infra_type, multiplier = get_way_class_and_multiplier(
                tags, weights, way_nodes, safe_crossing_nodes, node_highways
            )
            
            # Skip blocked roads (unless it's a 4-lane way, in which case we still need crossing edges)
            if (infra_type == "blocked" or multiplier >= 100000.0) and way_id not in four_lane_ways:
                continue
                
            way_name = tags.get("name", "Unnamed Path")
            
            if way_id in four_lane_ways:
                # Reconstruct parallel sides for 4+ lane way (only if not blocked)
                if infra_type != "blocked" and multiplier < 100000.0:
                    for i in range(len(way_nodes) - 1):
                        u = way_nodes[i]
                        v = way_nodes[i+1]
                        if u in nodes and v in nodes:
                            u_side1 = f"{u}_side1"
                            v_side1 = f"{v}_side1"
                            u_side2 = f"{u}_side2"
                            v_side2 = f"{v}_side2"
                            
                            G.add_node(u_side1, lat=nodes[u]["lat"], lon=nodes[u]["lon"])
                            G.add_node(v_side1, lat=nodes[v]["lat"], lon=nodes[v]["lon"])
                            G.add_node(u_side2, lat=nodes[u]["lat"], lon=nodes[u]["lon"])
                            G.add_node(v_side2, lat=nodes[v]["lat"], lon=nodes[v]["lon"])
                            
                            dist = haversine_distance((nodes[u]["lat"], nodes[u]["lon"]), (nodes[v]["lat"], nodes[v]["lon"]))
                            stress_level, facility_type = match_stress_for_edge(u, v, nodes, spatial_index)
                            offstreet_type, bicycles_allowed, ebike_allowed = match_offstreet_for_edge(u, v, nodes, offstreet_spatial_index)
                            
                            # Apply Boulder GIS facility type bonus on top of base multiplier
                            edge_multiplier = multiplier
                            FACILITY_BONUS = {
                                "Designated Bike Route": weights.get("facility_designated_route", 0.4),
                                "Protected Bike Lane": weights.get("facility_protected_lane", 0.3),
                                "Separated Bike Lane": weights.get("facility_protected_lane", 0.3),
                                "On-Street Bike Lane": weights.get("facility_onstreet_lane", 0.6),
                                "Bikeable Shoulder": weights.get("facility_bikeable_shoulder", 0.75),
                                "Contra Flow Bike Lane": weights.get("facility_contraflow", 0.5),
                            }
                            if facility_type in FACILITY_BONUS:
                                edge_multiplier = multiplier * FACILITY_BONUS[facility_type]
                            weight = dist * edge_multiplier

                            direction = _bike_edge_direction(tags, infra_type)
                            edge_attrs = dict(
                                weight=weight,
                                length=dist,
                                type=infra_type,
                                multiplier=edge_multiplier,
                                name=way_name,
                                bikestress=stress_level,
                                facility_type=facility_type,
                                offstreet_type=offstreet_type,
                                bicycles_allowed=bicycles_allowed,
                                ebike_allowed=ebike_allowed,
                                way_id=way_id,
                                tags=tags,
                            )
                            if direction in ("both", "forward"):
                                G.add_edge(u_side1, v_side1, **edge_attrs)
                                G.add_edge(u_side2, v_side2, **edge_attrs)
                            if direction in ("both", "reverse"):
                                G.add_edge(v_side1, u_side1, **edge_attrs)
                                G.add_edge(v_side2, u_side2, **edge_attrs)
                
                # Connect side1 and side2 at each node on this way
                for nid in way_nodes:
                    if nid in nodes:
                        nid_side1 = f"{nid}_side1"
                        nid_side2 = f"{nid}_side2"
                        
                        length_crossing = 15.0
                        if nid in safe_crossing_nodes:
                            crossing_type = "crossing_safe"
                            crossing_multiplier = weights.get("crossing_safe", 1.0)
                            weight_crossing = length_crossing * crossing_multiplier
                        else:
                            crossing_type = "crossing_unsafe"
                            crossing_multiplier = weights.get("crossing_unsafe", 3.0)
                            weight_crossing = (length_crossing + 100.0) * crossing_multiplier
                            
                        if not G.has_edge(nid_side1, nid_side2):
                            crossing_name = f"{way_name} Crossing"
                            G.add_node(nid_side1, lat=nodes[nid]["lat"], lon=nodes[nid]["lon"])
                            G.add_node(nid_side2, lat=nodes[nid]["lat"], lon=nodes[nid]["lon"])
                            G.add_edge(nid_side1, nid_side2,
                                       weight=weight_crossing,
                                       length=length_crossing,
                                       type=crossing_type,
                                       multiplier=crossing_multiplier,
                                       name=crossing_name,
                                       way_id=None,
                                       tags=nodes[nid].get("tags", {}))
                            G.add_edge(nid_side2, nid_side1,
                                       weight=weight_crossing,
                                       length=length_crossing,
                                       type=crossing_type,
                                       multiplier=crossing_multiplier,
                                       name=crossing_name,
                                       way_id=None,
                                       tags=nodes[nid].get("tags", {}))
            else:
                # For other streets, connect to side1 or side2 if they touch a 4+ lane node
                for i in range(len(way_nodes) - 1):
                    u = way_nodes[i]
                    v = way_nodes[i+1]
                    if u in nodes and v in nodes:
                        u_name = u
                        v_name = v
                        
                        if u in four_lane_nodes:
                            parent_way_id = list(node_to_four_lane_ways[u])[0]
                            orientation = way_orientations[parent_way_id]
                            if orientation == "NS":
                                if nodes[v]["lon"] > nodes[u]["lon"]:
                                    u_name = f"{u}_side1"
                                else:
                                    u_name = f"{u}_side2"
                            else:
                                if nodes[v]["lat"] > nodes[u]["lat"]:
                                    u_name = f"{u}_side1"
                                else:
                                    u_name = f"{u}_side2"
                                    
                        if v in four_lane_nodes:
                            parent_way_id = list(node_to_four_lane_ways[v])[0]
                            orientation = way_orientations[parent_way_id]
                            if orientation == "NS":
                                if nodes[u]["lon"] > nodes[v]["lon"]:
                                    v_name = f"{v}_side1"
                                else:
                                    v_name = f"{v}_side2"
                            else:
                                if nodes[u]["lat"] > nodes[v]["lat"]:
                                    v_name = f"{v}_side1"
                                else:
                                    v_name = f"{v}_side2"
                                    
                        G.add_node(u_name, lat=nodes[u]["lat"], lon=nodes[u]["lon"])
                        G.add_node(v_name, lat=nodes[v]["lat"], lon=nodes[v]["lon"])
                        
                        dist = haversine_distance((nodes[u]["lat"], nodes[u]["lon"]), (nodes[v]["lat"], nodes[v]["lon"]))
                        stress_level, facility_type = match_stress_for_edge(u, v, nodes, spatial_index)
                        offstreet_type, bicycles_allowed, ebike_allowed = match_offstreet_for_edge(u, v, nodes, offstreet_spatial_index)
                        
                        # Apply Boulder GIS facility type bonus on top of base multiplier
                        edge_multiplier = multiplier
                        FACILITY_BONUS = {
                            "Designated Bike Route": weights.get("facility_designated_route", 0.4),
                            "Protected Bike Lane": weights.get("facility_protected_lane", 0.3),
                            "Separated Bike Lane": weights.get("facility_protected_lane", 0.3),
                            "On-Street Bike Lane": weights.get("facility_onstreet_lane", 0.6),
                            "Bikeable Shoulder": weights.get("facility_bikeable_shoulder", 0.75),
                            "Contra Flow Bike Lane": weights.get("facility_contraflow", 0.5),
                        }
                        if facility_type in FACILITY_BONUS:
                            edge_multiplier = multiplier * FACILITY_BONUS[facility_type]
                        weight = dist * edge_multiplier
                        
                        direction = _bike_edge_direction(tags, infra_type)
                        edge_attrs = dict(
                            weight=weight,
                            length=dist,
                            type=infra_type,
                            multiplier=edge_multiplier,
                            name=way_name,
                            bikestress=stress_level,
                            facility_type=facility_type,
                            offstreet_type=offstreet_type,
                            bicycles_allowed=bicycles_allowed,
                            ebike_allowed=ebike_allowed,
                            way_id=way_id,
                            tags=tags,
                        )
                        if direction in ("both", "forward"):
                            G.add_edge(u_name, v_name, **edge_attrs)
                        if direction in ("both", "reverse"):
                            G.add_edge(v_name, u_name, **edge_attrs)

    # Get largest connected component to ensure routes are reachable
    if len(G) > 0:
        largest_cc = max(nx.weakly_connected_components(G), key=len)
        G_connected = G.subgraph(largest_cc).copy()
        print(f"Graph loaded successfully for {region_id}: {G_connected.number_of_nodes()} nodes, {G_connected.number_of_edges()} edges.")
    else:
        G_connected = G
        print(f"Warning: Graph for {region_id} is empty.")

    # Store global references for API usage
    graphs_by_region[region_id] = G_connected
    nodes_by_region[region_id] = nodes
    safe_crossings_by_region[region_id] = safe_crossing_nodes
    four_lane_nodes_by_region[region_id] = four_lane_nodes
    
    # Pre-build bike routes GeoJSON
    build_bike_routes_geojson(region_id)

    # Pre-populate graph with default weights so CLI routing tools remain in sync
    print(f"Populating graph for {region_id} with default routing weights...")
    update_graph_weights(G_connected, weights)
    mark_graph_build_ready(region_id, G_connected)

def build_bike_routes_geojson(region_id="boulder"):
    """Load, filter, and simplify official bike routes data into a lightweight FeatureCollection."""
    print(f"Compiling lightweight official bike routes GeoJSON for {region_id}...")
    
    features = []
    config = REGIONS[region_id]
    
    # 1. Process bike stress data (on-street network)
    stress_file = config.get("stress_cache_file")
    if stress_file and os.path.exists(stress_file):
        try:
            with open(stress_file, "r") as f:
                stress_data = json.load(f)
                
            allowed_stress_types = {
                "Designated Bike Route",
                "On-Street Bike Lane",
                "Protected Bike Lane",
                "Separated Bike Lane",
                "Contra Flow Bike Lane",
                "Bikeable Shoulder"
            }
            
            for feat in stress_data.get("features", []):
                props = feat.get("properties", {})
                fac_type = props.get("FACILITYTYPE")
                if fac_type in allowed_stress_types:
                    geom = feat.get("geometry")
                    if geom and geom.get("type") in ["LineString", "MultiLineString"]:
                        features.append({
                            "type": "Feature",
                            "geometry": geom,
                            "properties": {
                                "FACILITYTYPE": fac_type,
                                "name": props.get("STREETNAME") or props.get("NAME") or "Unnamed Street"
                            }
                        })
        except Exception as e:
            print(f"Error compiling stress routes for {region_id}: {e}")
            
    # 2. Process off-street data
    offstreet_file = config.get("offstreet_cache_file")
    if offstreet_file and os.path.exists(offstreet_file):
        try:
            with open(offstreet_file, "r") as f:
                offstreet_data = json.load(f)
                
            allowed_offstreet_types = {
                "Multi-Use Path",
                "Bike Park Path"
            }
            
            for feat in offstreet_data.get("features", []):
                props = feat.get("properties", {})
                fac_type = props.get("FACILITYTYPE")
                if fac_type in allowed_offstreet_types:
                    geom = feat.get("geometry")
                    if geom and geom.get("type") in ["LineString", "MultiLineString"]:
                        features.append({
                            "type": "Feature",
                            "geometry": geom,
                            "properties": {
                                "FACILITYTYPE": fac_type,
                                "name": props.get("NAME") or props.get("STREETNAME") or "Unnamed Path"
                            }
                        })
        except Exception as e:
            print(f"Error compiling off-street routes for {region_id}: {e}")
            
    bike_routes_geojson_by_region[region_id] = {
        "type": "FeatureCollection",
        "features": features
    }
    print(f"Successfully compiled {len(features)} official bike route features for {region_id}.")

def find_nearest_node(graph, target_coord):
    """Find the nearest node in the connected graph to the target coordinate."""
    min_dist = float("inf")
    nearest_node = None
    for node, data in graph.nodes(data=True):
        dist = haversine_distance(target_coord, (data["lat"], data["lon"]))
        if dist < min_dist:
            min_dist = dist
            nearest_node = node
    return nearest_node, min_dist

def get_region_for_coordinate(lat, lon):
    """Determine the region ID that contains the given coordinate. Fallback to 'boulder' if not matched."""
    try:
        lat = float(lat)
        lon = float(lon)
    except (TypeError, ValueError):
        return "boulder"
        
    for r_id, config in REGIONS.items():
        s, w, n, e = config["bbox"]
        if s <= lat <= n and w <= lon <= e:
            return r_id
    return "boulder"

def update_graph_weights(G, weights):
    """Update all edge multipliers and weights in the graph G based on weights dictionary."""
    FACILITY_BONUS_ROUTING = {
        "Designated Bike Route": weights.get("facility_designated_route", DEFAULT_WEIGHTS.get("facility_designated_route", 0.55)),
        "Protected Bike Lane":   weights.get("facility_protected_lane",   DEFAULT_WEIGHTS.get("facility_protected_lane",   0.20)),
        "Separated Bike Lane":   weights.get("facility_protected_lane",   DEFAULT_WEIGHTS.get("facility_protected_lane",   0.20)),
        "On-Street Bike Lane":   weights.get("facility_onstreet_lane",    DEFAULT_WEIGHTS.get("facility_onstreet_lane",    0.55)),
        "Bikeable Shoulder":     weights.get("facility_bikeable_shoulder",DEFAULT_WEIGHTS.get("facility_bikeable_shoulder",0.65)),
        "Contra Flow Bike Lane": weights.get("facility_contraflow",       DEFAULT_WEIGHTS.get("facility_contraflow",       0.45)),
    }

    for u, v, d in G.edges(data=True):
        infra_type = d.get("type", "residential")
        base_multiplier = weights.get(infra_type, DEFAULT_WEIGHTS.get(infra_type, 1.0))

        # Apply Boulder GIS facility type bonus (official designated routes etc.)
        facility_type = d.get("facility_type", "None")
        facility_modifier = FACILITY_BONUS_ROUTING.get(facility_type, 1.0)

        # Parse lanes count from tags to identify 4+ lane arterials
        tags = d.get("tags", {})
        lanes_str = tags.get("lanes", "")
        try:
            if ";" in lanes_str:
                lanes = max([int(x) for x in lanes_str.split(";") if x.isdigit()])
            else:
                lanes = int(lanes_str) if lanes_str.isdigit() else 2
        except:
            lanes = 2

        # Check forward/backward lanes
        try:
            lanes_fwd = int(tags.get("lanes:forward", "0"))
            lanes_bwd = int(tags.get("lanes:backward", "0"))
            if lanes_fwd + lanes_bwd > 0:
                lanes = lanes_fwd + lanes_bwd
        except:
            pass

        highway = tags.get("highway", "")
        is_major_busy_road = (lanes >= 4) or (highway in ["primary", "primary_link", "secondary", "secondary_link"])

        if is_major_busy_road:
            GIS_BASE_CAP = {
                "Protected Bike Lane":   weights.get("separated_path",    DEFAULT_WEIGHTS.get("separated_path",    0.5)),
                "Separated Bike Lane":   weights.get("separated_path",    DEFAULT_WEIGHTS.get("separated_path",    0.5)),
                "On-Street Bike Lane":   weights.get("busy_with_lane",    DEFAULT_WEIGHTS.get("busy_with_lane",    5.0)),
                "Designated Bike Route": weights.get("busy_with_sharrow", DEFAULT_WEIGHTS.get("busy_with_sharrow", 8.0)),
                "Bikeable Shoulder":     weights.get("busy_undesignated", DEFAULT_WEIGHTS.get("busy_undesignated", 15.0)),
                "Contra Flow Bike Lane": weights.get("busy_with_lane",    DEFAULT_WEIGHTS.get("busy_with_lane",    5.0)),
            }
        else:
            GIS_BASE_CAP = {
                "Protected Bike Lane":   weights.get("separated_path",    DEFAULT_WEIGHTS.get("separated_path",    0.5)),
                "Separated Bike Lane":   weights.get("separated_path",    DEFAULT_WEIGHTS.get("separated_path",    0.5)),
                "On-Street Bike Lane":   weights.get("sharrow_minor",     DEFAULT_WEIGHTS.get("sharrow_minor",     1.3)),
                "Designated Bike Route": weights.get("residential",       DEFAULT_WEIGHTS.get("residential",       1.2)),
                "Bikeable Shoulder":     weights.get("busy_with_lane",    DEFAULT_WEIGHTS.get("busy_with_lane",    3.0)),
                "Contra Flow Bike Lane": weights.get("sharrow_minor",     DEFAULT_WEIGHTS.get("sharrow_minor",     1.3)),
            }

        if facility_type in GIS_BASE_CAP:
            # Use whichever is lower: OSM-derived base or GIS cap
            base_multiplier = min(base_multiplier, GIS_BASE_CAP[facility_type])

        # Apply stress modifier if matched (default separated paths to Low stress)
        stress = d.get("bikestress", "None")
        if stress == "None" and infra_type == "separated_path":
            stress = "Low"

        stress_modifier = 1.0
        if stress == "Low":
            stress_modifier = weights.get("stress_low", DEFAULT_WEIGHTS.get("stress_low", 0.7))
        elif stress == "High":
            stress_modifier = weights.get("stress_high", DEFAULT_WEIGHTS.get("stress_high", 2.0))

        # Apply off-street modifiers
        offstreet_modifier = 1.0
        bicycles_allowed = d.get("bicycles_allowed", "Yes")

        if bicycles_allowed == "No":
            # Bicycles forbidden -> Blocked segment!
            final_multiplier = 999999.0
        else:
            offstreet_type = d.get("offstreet_type", "None")
            if offstreet_type == "Multi-Use Path":
                offstreet_modifier = weights.get("offstreet_multiuse", DEFAULT_WEIGHTS.get("offstreet_multiuse", 0.8))

            ebike_allowed = d.get("ebike_allowed", "Yes")
            ebike_modifier = 1.0
            if ebike_allowed == "No":
                ebike_modifier = weights.get("ebike_restricted", DEFAULT_WEIGHTS.get("ebike_restricted", 1.0))

            final_multiplier = base_multiplier * facility_modifier * stress_modifier * offstreet_modifier * ebike_modifier

        G[u][v]["multiplier"] = final_multiplier

        length = d.get("length", 0.0)
        if infra_type == "crossing_unsafe":
            G[u][v]["weight"] = (length + 100.0) * final_multiplier
        else:
            G[u][v]["weight"] = length * final_multiplier

@app.route("/api/route", methods=["POST", "OPTIONS"])
def get_route():
    """API endpoint to request a route between two points with custom weights."""
    if request.method == "OPTIONS":
        return "", 200

    data = request.json or {}

    start_lat = data.get("start_lat")
    start_lon = data.get("start_lon")
    end_lat = data.get("end_lat")
    end_lon = data.get("end_lon")
    custom_weights = data.get("weights") or DEFAULT_WEIGHTS
    region_id = data.get("region")

    if not all([start_lat, start_lon, end_lat, end_lon]):
        return jsonify({"error": "Missing coordinates"}), 400

    if not region_id:
        region_id = get_region_for_coordinate(start_lat, start_lon)

    if region_id not in REGIONS:
        return jsonify({"error": f"Invalid region: {region_id}"}), 400

    graph = graphs_by_region.get(region_id)
    if graph is None:
        return jsonify({"error": f"Routing graph not initialized for region: {region_id}"}), 503

    # Check if start and end coordinates are in the same region
    end_region_id = get_region_for_coordinate(end_lat, end_lon)
    if region_id != end_region_id:
        return jsonify({"error": f"Start and Destination span across separate areas ({region_id} and {end_region_id}). Cross-region routing is not supported."}), 400

    # Recalculate weights on the graph dynamically using client weights
    update_graph_weights(graph, custom_weights)

    waypoints = data.get("waypoints", []) # list of [lat, lon]
    
    # Compile a sequence of coordinates to route between
    route_points = [(start_lat, start_lon)]
    for wp in waypoints:
        route_points.append((wp[0], wp[1]))
    route_points.append((end_lat, end_lon))

    try:
        segments = []
        total_length = 0
        total_weight = 0
        
        start_node_dist = None
        end_node_dist = None
        
        # Iterate over consecutive pairs of points
        for p in range(len(route_points) - 1):
            sub_start_lat, sub_start_lon = route_points[p]
            sub_end_lat, sub_end_lon = route_points[p+1]
            
            sub_start_node, sub_start_dist = find_nearest_node(graph, (sub_start_lat, sub_start_lon))
            sub_end_node, sub_end_dist = find_nearest_node(graph, (sub_end_lat, sub_end_lon))
            
            if sub_start_node is None or sub_end_node is None:
                return jsonify({"error": f"Could not locate routing node for point {p+1}."}), 404
                
            if p == 0:
                start_node_dist = sub_start_dist
            if p == len(route_points) - 2:
                end_node_dist = sub_end_dist
                
            path_nodes = nx.shortest_path(graph, source=sub_start_node, target=sub_end_node, weight="weight")
            
            for i in range(len(path_nodes) - 1):
                u = path_nodes[i]
                v = path_nodes[i+1]
                edge_data = graph.get_edge_data(u, v)
                length = edge_data.get("length", 0)
                infra_type = edge_data.get("type", "residential")
                name = edge_data.get("name", "Unnamed Path")
                multiplier = edge_data.get("multiplier", 1.0)
                
                edge_weight = edge_data.get("weight", length * multiplier)
                total_length += length
                total_weight += edge_weight
                
                node_u_data = graph.nodes[u]
                node_v_data = graph.nodes[v]
                
                segments.append({
                    "coords": [
                        [node_u_data["lat"], node_u_data["lon"]],
                        [node_v_data["lat"], node_v_data["lon"]]
                    ],
                    "type": infra_type,
                    "name": name,
                    "length": length,
                    "multiplier": multiplier,
                    "bikestress": edge_data.get("bikestress", "None"),
                    "offstreet_type": edge_data.get("offstreet_type", "None"),
                    "bicycles_allowed": edge_data.get("bicycles_allowed", "Yes"),
                    "ebike_allowed": edge_data.get("ebike_allowed", "Yes")
                })
                
        response_payload = {
            "segments": segments,
            "total_length_meters": total_length,
            "total_weight": total_weight,
            "start_node_dist_meters": start_node_dist,
            "end_node_dist_meters": end_node_dist
        }
        record_route_analytics_event("route_created", {
            "route_type": data.get("route_type") or "dynamic",
            "start_lat": start_lat,
            "start_lon": start_lon,
            "end_lat": end_lat,
            "end_lon": end_lon,
            "waypoint_count": len(waypoints),
            "total_length_meters": total_length,
            "total_weight": total_weight,
            "segment_count": len(segments),
            "weights": custom_weights,
            "offsets": clean_optional_json(data.get("offsets")),
            "metadata": compact_route_metadata(segments),
            "client_session_id": data.get("client_session_id"),
            "client_event_id": data.get("client_event_id"),
        }, source=get_request_source("backend"))
        return jsonify(response_payload)
        
    except nx.NetworkXNoPath:
        return jsonify({"error": "No route exists between the selected points."}), 404
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route("/api/inspect-edge", methods=["GET"])
def inspect_edge():
    """Inspect the nearest edge in the routing graph and return its full attributes and geometry."""
    lat_val = request.args.get("lat")
    lon_val = request.args.get("lon")
    region_id = request.args.get("region")
    
    if not lat_val or not lon_val:
        return jsonify({"error": "Missing coordinates"}), 400
        
    try:
        click_coord = (float(lat_val), float(lon_val))
    except ValueError:
        return jsonify({"error": "Invalid coordinates"}), 400
        
    if not region_id:
        region_id = get_region_for_coordinate(click_coord[0], click_coord[1])
        
    if region_id not in REGIONS:
        return jsonify({"error": f"Invalid region: {region_id}"}), 400

    graph = graphs_by_region.get(region_id)
    if graph is None:
        return jsonify({"error": f"Routing graph not initialized for region: {region_id}"}), 503

    # Find nearest node
    nearest_node, _ = find_nearest_node(graph, click_coord)
    if nearest_node is None:
        return jsonify({"error": "No road network found near click."}), 404
        
    best_edge = None
    min_dist = float("inf")
    
    # Check incoming and outgoing edges connected to nearest_node to find the closest segment line.
    connected_edges = set(graph.out_edges(nearest_node)) | set(graph.in_edges(nearest_node))
    for u, v in connected_edges:
        node_u_data = graph.nodes[u]
        node_v_data = graph.nodes[v]
        pt_u = (node_u_data["lat"], node_u_data["lon"])
        pt_v = (node_v_data["lat"], node_v_data["lon"])
        
        dist = point_to_segment_distance(click_coord, pt_u, pt_v)
        if dist < min_dist:
            min_dist = dist
            best_edge = (u, v)
            
    if best_edge is None:
        return jsonify({"error": "Could not identify an edge."}), 404
        
    u, v = best_edge
    edge_data = graph.get_edge_data(u, v)
    node_u_data = graph.nodes[u]
    node_v_data = graph.nodes[v]
    
    response_data = {
        "name": edge_data.get("name", "Unnamed Path"),
        "type": edge_data.get("type", "residential"),
        "multiplier": edge_data.get("multiplier", 1.0),
        "bikestress": edge_data.get("bikestress", "None"),
        "facility_type": edge_data.get("facility_type", "None"),
        "offstreet_type": edge_data.get("offstreet_type", "None"),
        "bicycles_allowed": edge_data.get("bicycles_allowed", "Yes"),
        "ebike_allowed": edge_data.get("ebike_allowed", "Yes"),
        "length": edge_data.get("length", 0.0),
        "way_id": edge_data.get("way_id"),
        "tags": edge_data.get("tags", {}),
        "coords": [
            [node_u_data["lat"], node_u_data["lon"]],
            [node_v_data["lat"], node_v_data["lon"]]
        ],
        "distance_to_click_meters": min_dist
    }
    
    return jsonify(response_data)

@app.route("/api/weights", methods=["GET"])
def get_current_weights():
    """Get the default and currently configured weighting factors."""
    return jsonify(DEFAULT_WEIGHTS)

# Metadata definitions for sliders and preset routes
WEIGHTS_METADATA = [
    {
        "key": "separated_path",
        "name": "Separated Paths",
        "description": "Multi-use paths, greenways, cycletracks",
        "web_icon": "fa-leaf",
        "ios_icon": "leaf.fill",
        "min": 0.1, "max": 2.0, "step": 0.1,
        "default": 0.5
    },
    {
        "key": "sharrow_minor",
        "name": "Quiet Streets (Sharrows)",
        "description": "Quiet streets with shared lane markings",
        "web_icon": "fa-shield",
        "ios_icon": "shield.fill",
        "min": 0.5, "max": 5.0, "step": 0.1,
        "default": 1.5
    },
    {
        "key": "residential",
        "name": "Residential Streets",
        "description": "Quiet side streets without designations",
        "web_icon": "fa-house",
        "ios_icon": "house.fill",
        "min": 0.5, "max": 5.0, "step": 0.1,
        "default": 0.7
    },
    {
        "key": "sidewalk",
        "name": "Sidewalk Routing",
        "description": "Separate sidewalks, pedestrian ways, slow speed",
        "web_icon": "fa-walking",
        "ios_icon": "figure.walk",
        "min": 1.0, "max": 10.0, "step": 0.5,
        "default": 2.0
    },
    {
        "key": "busy_with_lane",
        "name": "Busy Roads w/ Bike Lane",
        "description": "Secondary/tertiary roads with painted lanes",
        "web_icon": "fa-road",
        "ios_icon": "road.lanes",
        "min": 2.0, "max": 15.0, "step": 0.5,
        "default": 5.0
    },
    {
        "key": "busy_with_sharrow",
        "name": "Busy Roads w/ Sharrows",
        "description": "Busy arterials with sharrows",
        "web_icon": "fa-triangle-exclamation",
        "ios_icon": "exclamationmark.triangle.fill",
        "min": 3.0, "max": 25.0, "step": 1.0,
        "default": 8.0
    },
    {
        "key": "busy_undesignated",
        "name": "Busy Roads (Undesignated)",
        "description": "Arterials without bike infrastructure (feeder-only)",
        "web_icon": "fa-skull-crossbones",
        "ios_icon": "skull",
        "min": 5.0, "max": 50.0, "step": 1.0,
        "default": 15.0
    },
    {
        "key": "sidewalk_forced",
        "name": "Sidewalk on 4+ Lanes",
        "description": "Forced sidewalk walk on 4+ lane roads",
        "web_icon": "fa-ban",
        "ios_icon": "nosign",
        "min": 2.0, "max": 20.0, "step": 1.0,
        "default": 6.0
    },
    {
        "key": "crossing_safe",
        "name": "Safe Crossings",
        "description": "Signalized, beacon-flashing, or bike crossings",
        "web_icon": "fa-traffic-light",
        "ios_icon": "traffic.light.fill",
        "min": 0.5, "max": 3.0, "step": 0.1,
        "default": 1.0
    },
    {
        "key": "crossing_unsafe",
        "name": "Unsignalized Crossings",
        "description": "Unmarked or non-signalized busy street crossings",
        "web_icon": "fa-triangle-exclamation",
        "ios_icon": "exclamationmark.triangle.fill",
        "min": 1.0, "max": 10.0, "step": 0.5,
        "default": 6.0
    },
    {
        "key": "stress_low",
        "name": "Low Stress Modifier",
        "description": "Additional multiplier applied to streets matching Low Traffic Stress overlay",
        "web_icon": "fa-heart-circle-check",
        "ios_icon": "heart.text.square.fill",
        "min": 0.1, "max": 1.5, "step": 0.1,
        "default": 0.7
    },
    {
        "key": "stress_high",
        "name": "High Stress Modifier",
        "description": "Additional penalty applied to streets matching High Traffic Stress overlay",
        "web_icon": "fa-circle-exclamation",
        "ios_icon": "exclamationmark.circle.fill",
        "min": 1.0, "max": 10.0, "step": 0.5,
        "default": 2.0
    },
    {
        "key": "offstreet_multiuse",
        "name": "Multi-Use Path Modifier",
        "description": "Additional multiplier applied to off-street Multi-Use Paths",
        "web_icon": "fa-tree-city",
        "ios_icon": "tree.fill",
        "min": 0.1, "max": 1.5, "step": 0.1,
        "default": 0.8
    },
    {
        "key": "ebike_restricted",
        "name": "E-Bike Prohibited Penalty",
        "description": "Additional penalty applied if e-bikes are prohibited on the path",
        "web_icon": "fa-bolt-lightning",
        "ios_icon": "bolt.fill",
        "min": 1.0, "max": 10.0, "step": 0.5,
        "default": 1.0
    }
]

ROUTE_PRESETS = [
    {
        "name": "Park Playgrounds",
        "desc": "Choose a playground destination from your current location",
        "start": [],
        "end": [],
        "waypoints": [],
        "route_type": "playgrounds"
    },
    {
        "name": "Boulder Loops B-180",
        "desc": "12 mi scenic loop (Valmont Park)",
        "start": [40.030, -105.234],
        "end": [40.030, -105.234],
        "waypoints": [
            [40.033, -105.253],
            [40.038, -105.263],
            [40.028, -105.281],
            [40.028, -105.283],
            [40.021, -105.291],
            [40.015, -105.292],
            [40.014, -105.275],
            [40.015, -105.253]
        ],
        "route_type": "b180"
    },
    {
        "name": "Boulder Loops B-360",
        "desc": "24 mi grand loop (Valmont Park)",
        "start": [40.030, -105.234],
        "end": [40.030, -105.234],
        "waypoints": [
            [40.034, -105.225],
            [40.052, -105.207],
            [40.054, -105.228],
            [40.040, -105.249],
            [40.046, -105.265],
            [40.060, -105.275],
            [40.039, -105.289],
            [40.028, -105.289],
            [40.015, -105.292],
            [39.998, -105.283],
            [39.991, -105.263],
            [39.986, -105.238],
            [39.981, -105.233],
            [39.998, -105.228],
            [40.030, -105.210]
        ],
        "route_type": "b360"
    },
    {
        "name": "Broomfield Commons Tour",
        "desc": "2.5 mi route around Broomfield Commons Park",
        "start": [39.932, -105.059],
        "end": [39.927, -105.080],
        "waypoints": [
            [39.930, -105.068],
            [39.925, -105.075]
        ],
        "route_type": "broomfield_loop"
    }
]

@app.route("/api/config", methods=["GET"])
def get_config():
    """Get the full list of dynamic configuration presets, sliders metadata, and supported regions."""
    pb_url = os.environ.get("POCKETBASE_URL", "http://127.0.0.1:8090")
    config_payload = {
        "weights": WEIGHTS_METADATA,
        "presets": ROUTE_PRESETS,
        "regions": {r_id: {"name": config["name"], "bbox": config["bbox"]} for r_id, config in REGIONS.items()}
    }
    try:
        resp = requests.get(f"{pb_url}/api/collections/global_configs/records", timeout=2)
        if resp.status_code == 200:
            data = resp.json()
            items = data.get("items", [])
            configs_dict = {item.get("key"): item.get("value") for item in items if "key" in item and "value" in item}
            
            weights = configs_dict.get("weights")
            if weights:
                config_payload["weights"] = weights
    except Exception as e:
        print(f"[-] Failed to fetch config from PocketBase: {e}. Falling back to default config.")
        
    return jsonify(config_payload)


@app.route("/api/crossings", methods=["GET"])
def get_crossings():
    """Get all crossing nodes on 4+ lane roads or safe crossings in the network for the specified region."""
    region_id = request.args.get("region", "boulder")
    if region_id not in REGIONS:
        return jsonify({"error": f"Invalid region: {region_id}"}), 400

    nodes = nodes_by_region.get(region_id, {})
    four_lane_nodes = four_lane_nodes_by_region.get(region_id, set())
    safe_crossing_nodes = safe_crossings_by_region.get(region_id, set())
    
    crossings_list = []
    for nid, ndata in nodes.items():
        tags = ndata.get("tags", {})
        highway = tags.get("highway", "")
        if highway == "crossing" or highway == "traffic_signals":
            if nid in four_lane_nodes or nid in safe_crossing_nodes:
                lat = ndata["lat"]
                lon = ndata["lon"]
                
                # Classify type
                if nid in safe_crossing_nodes:
                    if tags.get("bicycle") in ["yes", "designated"] or tags.get("crossing:bicycle") in ["yes", "designated"]:
                        crossing_type = "bike_signal"
                        desc = "Dedicated Bike Signal"
                    else:
                        crossing_type = "stop_light"
                        desc = "Signalized Crossing (Stop Light)"
                else:
                    crossing_type = "crosswalk"
                    desc = "Unsignalized Crosswalk"
                    
                crossings_list.append({
                    "id": nid,
                    "lat": lat,
                    "lon": lon,
                    "crossing_type": crossing_type,
                    "description": desc,
                    "tags": tags
                })
                
    return jsonify(crossings_list)

@app.route("/api/playgrounds", methods=["GET"])
def get_playgrounds():
    """Get processed playground locations for the specified region sorted alphabetically."""
    region_id = request.args.get("region", "boulder")
    if region_id not in REGIONS:
        return jsonify({"error": f"Invalid region: {region_id}"}), 400

    from collections import Counter
    try:
        data = fetch_playground_data(region_id)
        features = data.get("features", [])
        
        # Filter for active playgrounds
        playgrounds = []
        for f in features:
            prop = f.get("properties", {})
            geom = f.get("geometry", {})
            if prop.get("PLAYTYPE") == "Park Playground" and geom and geom.get("type") == "Polygon":
                playgrounds.append(f)
                
        if not playgrounds:
            return jsonify([])

        # Count playgrounds per park to format name properly
        park_counts = Counter(f["properties"].get("PROPNAME", "") for f in playgrounds)
        
        results = []
        for f in playgrounds:
            prop = f["properties"]
            park_name = prop.get("PROPNAME", "Unnamed Park")
            play_name = prop.get("NAME", "Unnamed Playground")
            coords = f["geometry"]["coordinates"][0]
            
            lat, lon = calculate_centroid(coords)
            
            # Format display name
            if park_counts[park_name] == 1:
                display_name = park_name
            else:
                # Remove park name words and common terms to get a clean suffix
                words_to_remove = set(w.lower() for w in park_name.split())
                words_to_remove.update(["playground", "park", "community"])
                
                play_words = play_name.split()
                unique_words = [w for w in play_words if w.lower() not in words_to_remove]
                suffix = " ".join(unique_words)
                
                if not suffix:
                    suffix = "Playground"
                display_name = f"{park_name} ({suffix})"
                
            results.append({
                "name": display_name,
                "lat": lat,
                "lon": lon
            })
            
        # Sort alphabetically by display name
        results.sort(key=lambda x: x["name"])
        
        return jsonify(results)
    except Exception as e:
        return jsonify([]), 200 # Return empty list on failure or missing playgrounds

@app.route("/api/bike-routes", methods=["GET"])
def get_bike_routes():
    """API endpoint to get the compiled, lightweight official bike routes GeoJSON for the specified region."""
    region_id = request.args.get("region", "boulder")
    if region_id not in REGIONS:
        return jsonify({"error": f"Invalid region: {region_id}"}), 400

    geojson = bike_routes_geojson_by_region.get(region_id)
    if geojson is None:
        return jsonify({"type": "FeatureCollection", "features": []})
    return jsonify(geojson)

# Simple CORS support for development
@app.after_request
def add_cors_headers(response):
    response.headers["Access-Control-Allow-Origin"] = "*"
    response.headers["Access-Control-Allow-Headers"] = "Content-Type, Authorization, X-Client-Source, X-Client-Session-Id, X-Client-Event-Id, X-Guest-Id, X-Guest-Token"
    response.headers["Access-Control-Allow-Methods"] = "POST, GET, PATCH, PUT, DELETE, OPTIONS"
    return response

@app.route("/api/pocketbase-status", methods=["GET"])
def pocketbase_status():
    """Check status of PocketBase connection."""
    pb_url = os.environ.get("POCKETBASE_URL", "http://127.0.0.1:8090")
    try:
        resp = requests.get(f"{pb_url}/api/health", timeout=2)
        if resp.status_code == 200:
            return jsonify({
                "status": "connected",
                "url": pb_url,
                "health": resp.json()
            })
        else:
            return jsonify({
                "status": "error",
                "url": pb_url,
                "code": resp.status_code,
                "message": "PocketBase did not return 200 OK"
            }), 500
    except Exception as e:
        return jsonify({
            "status": "disconnected",
            "url": pb_url,
            "error": str(e)
        }), 500

@app.route("/api/graph-status", methods=["GET"])
def graph_status():
    """Report routing graph build state for polling/debugging of all regions."""
    status_dict = {}
    for r_id in REGIONS:
        status_dict[r_id] = get_graph_build_status(r_id)
    return jsonify(status_dict)

@app.route("/api/health", methods=["GET"])
def api_health():
    """Report backend readiness and routing graph build state for primary (boulder) region."""
    graph_status = get_graph_build_status("boulder")
    http_status = 200 if graph_status["ready"] else 503
    return jsonify({
        "status": "ok" if graph_status["ready"] else graph_status["state"],
        "graph": graph_status,
    }), http_status

def get_auth_user_id(auth_header):
    if not auth_header:
        return None
    pb_url = os.environ.get("POCKETBASE_URL", "http://127.0.0.1:8090")
    try:
        resp = requests.post(f"{pb_url}/api/collections/users/auth-refresh", headers={"Authorization": auth_header}, timeout=2)
        if resp.status_code == 200:
            user_data = resp.json()
            return user_data.get("record", {}).get("id")
    except Exception as e:
        print(f"Error validating token with PocketBase: {e}")
    return None

def clamp_number(value, minimum, maximum):
    try:
        numeric = float(value)
    except (TypeError, ValueError):
        return None
    return max(minimum, min(maximum, numeric))

def normalize_place_query(value):
    return re.sub(r"\s+", " ", str(value or "").strip().lower())

def escape_pocketbase_filter_value(value):
    return str(value).replace("\\", "\\\\").replace('"', '\\"')

def get_request_source(default="backend"):
    source = request.headers.get("X-Client-Source") or request.args.get("source") or default
    source = str(source or default).strip().lower()
    if source not in {"backend", "web", "ios"}:
        return default
    return source

def request_auth_user_id():
    return get_auth_user_id(request.headers.get("Authorization"))

def client_analytics_fields(data=None):
    data = data if isinstance(data, dict) else {}
    return {
        "client_session_id": request.headers.get("X-Client-Session-Id") or data.get("client_session_id"),
        "client_event_id": request.headers.get("X-Client-Event-Id") or data.get("client_event_id"),
    }

def clean_optional_text(value, max_length=500):
    if value is None:
        return None
    text = str(value).strip()
    if not text:
        return None
    return text[:max_length]

def clean_optional_number(value):
    try:
        if value is None or value == "":
            return None
        numeric = float(value)
    except (TypeError, ValueError):
        return None
    if not math.isfinite(numeric):
        return None
    return numeric

def clean_optional_json(value):
    return value if isinstance(value, (dict, list)) else None

def compact_route_metadata(segments):
    type_counts = {}
    names = []
    for segment in segments[:500]:
        seg_type = segment.get("type") or "unknown"
        type_counts[seg_type] = type_counts.get(seg_type, 0) + 1
        name = clean_optional_text(segment.get("name"), 120)
        if name and name not in names and len(names) < 20:
            names.append(name)
    return {
        "segment_type_counts": type_counts,
        "sample_street_names": names,
    }

def write_pocketbase_analytics(collection, payload):
    pb_url = os.environ.get("POCKETBASE_URL", "http://127.0.0.1:8090")
    try:
        resp = requests.post(
            f"{pb_url}/api/collections/{collection}/records",
            json=payload,
            timeout=3
        )
        if resp.status_code >= 400:
            print(f"[-] Analytics write failed for {collection}: {resp.status_code} {resp.text[:300]}")
            return False
        return True
    except Exception as e:
        print(f"[-] Analytics write failed for {collection}: {e}")
        return False

def record_place_search_event(query, limit=None, result_count=None, target=None, selected_place=None, metadata=None, source=None):
    normalized_query = normalize_place_query(query)
    if not normalized_query:
        return False
    selected_place = selected_place if isinstance(selected_place, dict) else {}
    payload = {
        "source": source or get_request_source("backend"),
        "target": clean_optional_text(target, 40),
        "query": clean_optional_text(query, 500) or normalized_query,
        "normalized_query": normalized_query,
        "limit": clean_optional_number(limit),
        "result_count": clean_optional_number(result_count),
        "selected_place_id": clean_optional_text(selected_place.get("id"), 120),
        "selected_place_name": clean_optional_text(selected_place.get("name"), 300),
        "metadata": clean_optional_json(metadata),
        "occurred_at": utc_now_iso(),
        **client_analytics_fields(metadata),
    }
    user_id = request_auth_user_id()
    if user_id:
        payload["user"] = user_id
    else:
        payload["guest_owner_hash"] = get_guest_owner_hash()
    return write_pocketbase_analytics("place_search_events", payload)

def record_route_analytics_event(event_type, data=None, source=None):
    data = data if isinstance(data, dict) else {}
    payload = {
        "source": source or get_request_source("backend"),
        "event_type": clean_optional_text(event_type, 80) or "route_event",
        "route_type": clean_optional_text(data.get("route_type"), 80),
        "route_id": clean_optional_text(data.get("route_id"), 120),
        "start_lat": clean_optional_number(data.get("start_lat")),
        "start_lon": clean_optional_number(data.get("start_lon")),
        "end_lat": clean_optional_number(data.get("end_lat")),
        "end_lon": clean_optional_number(data.get("end_lon")),
        "waypoint_count": clean_optional_number(data.get("waypoint_count")),
        "total_length_meters": clean_optional_number(data.get("total_length_meters")),
        "total_weight": clean_optional_number(data.get("total_weight")),
        "segment_count": clean_optional_number(data.get("segment_count")),
        "start_point_name": clean_optional_text(data.get("start_point_name"), 300),
        "end_point_name": clean_optional_text(data.get("end_point_name"), 300),
        "weights": clean_optional_json(data.get("weights")),
        "offsets": clean_optional_json(data.get("offsets")),
        "metadata": clean_optional_json(data.get("metadata")),
        "occurred_at": clean_optional_text(data.get("occurred_at"), 80) or utc_now_iso(),
        **client_analytics_fields(data),
    }
    user_id = request_auth_user_id()
    if user_id:
        payload["user"] = user_id
    else:
        payload["guest_owner_hash"] = get_guest_owner_hash()
    return write_pocketbase_analytics("route_analytics_events", payload)

def place_record_to_api(record):
    return {
        "id": record.get("id"),
        "name": record.get("name") or "",
        "type": record.get("type") or "place",
        "lat": record.get("lat"),
        "lng": record.get("lng"),
        "source": record.get("source") or "osm"
    }

PLACE_TYPE_PRIORITY = {
    "playground": 5,
    "park": 8,
    "pedestrian": 10,
    "trailhead": 12,
    "path": 14,
    "cycleway": 16,
    "footway": 18,
    "bus_stop": 25,
    "restaurant": 30,
    "cafe": 30,
    "library": 30,
    "school": 35,
    "university": 35,
    "peak": 40,
    "secondary": 70,
    "tertiary": 75,
    "residential": 80,
    "unclassified": 82,
    "service": 90,
    "proposed": 95,
}

def place_type_priority(place_type):
    return PLACE_TYPE_PRIORITY.get(str(place_type or "").lower(), 60)

def place_match_score(record, query):
    name = normalize_place_query(record.get("name", ""))
    score = 0
    if record.get("_fuzzy_score") is not None:
        score -= float(record.get("_fuzzy_score") or 0) * 75
    if name == query:
        score -= 100
    elif name.startswith(query):
        score -= 50
    elif f" {query}" in name:
        score -= 25
    score += place_type_priority(record.get("type"))
    score += min(len(name), 80) / 100.0
    return score

def aggregate_place_records(records, query, limit):
    grouped = {}
    for record in records:
        name = str(record.get("name") or "").strip()
        lat = record.get("lat")
        lng = record.get("lng")
        if not name or lat is None or lng is None:
            continue
        try:
            lat = float(lat)
            lng = float(lng)
        except (TypeError, ValueError):
            continue

        key = normalize_place_query(name)
        existing = grouped.get(key)
        score = place_match_score(record, query)
        if not existing:
            grouped[key] = {
                "id": record.get("id"),
                "name": name,
                "type": record.get("type") or "place",
                "lat_total": lat,
                "lng_total": lng,
                "count": 1,
                "source": record.get("source") or "osm",
                "score": score,
            }
            continue

        existing["lat_total"] += lat
        existing["lng_total"] += lng
        existing["count"] += 1
        if score < existing["score"]:
            existing["id"] = record.get("id")
            existing["type"] = record.get("type") or existing["type"]
            existing["source"] = record.get("source") or existing["source"]
            existing["score"] = score

    results = []
    for item in grouped.values():
        count = item["count"]
        results.append({
            "id": item["id"],
            "name": item["name"],
            "type": item["type"],
            "lat": item["lat_total"] / count,
            "lng": item["lng_total"] / count,
            "source": item["source"],
            "match_count": count,
        })

    results.sort(key=lambda item: (
        place_match_score(item, query),
        normalize_place_query(item.get("name", ""))
    ))
    return results[:limit]

def fuzzy_place_score(query, search_name):
    query = normalize_place_query(query)
    search_name = normalize_place_query(search_name)
    if not query or not search_name:
        return 0.0
    name_parts = [search_name]
    name_parts.extend(part for part in re.split(r"[^a-z0-9]+", search_name) if part)
    return max(difflib.SequenceMatcher(None, query, part).ratio() for part in name_parts)

def fetch_fuzzy_place_candidates(pb_url, query):
    candidates = []
    page = 1
    per_page = 500
    while page <= 20:
        resp = requests.get(
            f"{pb_url}/api/collections/places/records",
            params={
                "page": page,
                "perPage": per_page,
                "sort": "search_name",
            },
            timeout=8
        )
        if resp.status_code != 200:
            return [], resp
        data = resp.json()
        for record in data.get("items", []):
            score = fuzzy_place_score(query, record.get("search_name") or record.get("name") or "")
            if score >= 0.72:
                candidates.append({**record, "_fuzzy_score": score})
        if page >= int(data.get("totalPages") or 1):
            break
        page += 1

    candidates.sort(key=lambda record: (
        -float(record.get("_fuzzy_score", 0)),
        place_type_priority(record.get("type")),
        normalize_place_query(record.get("name", ""))
    ))
    return candidates[:250], None

@app.route("/api/autocomplete", methods=["GET"])
def autocomplete_places():
    query = normalize_place_query(request.args.get("q", ""))
    if len(query) < 2:
        return jsonify([])

    limit = clamp_number(request.args.get("limit", 10), 1, 25) or 10
    pb_url = os.environ.get("POCKETBASE_URL", "http://127.0.0.1:8090")
    escaped_query = escape_pocketbase_filter_value(query)

    try:
        resp = requests.get(
            f"{pb_url}/api/collections/places/records",
            params={
                "filter": f'search_name ~ "{escaped_query}"',
                "sort": "search_name",
                "perPage": max(int(limit) * 30, 100),
            },
            timeout=5
        )
        if resp.status_code == 404:
            return jsonify({"error": "Places collection has not been migrated yet."}), 503
        if resp.status_code != 200:
            return jsonify({"error": f"PocketBase returned {resp.status_code}: {resp.text}"}), resp.status_code

        records = resp.json().get("items", [])
        if not records:
            records, fuzzy_resp = fetch_fuzzy_place_candidates(pb_url, query)
            if fuzzy_resp is not None:
                return jsonify({"error": f"PocketBase returned {fuzzy_resp.status_code}: {fuzzy_resp.text}"}), fuzzy_resp.status_code
        results = aggregate_place_records(records, query, int(limit))
        record_place_search_event(
            query,
            limit=limit,
            result_count=len(results),
            target=request.args.get("target"),
            metadata={"request_path": "/api/autocomplete"},
            source=get_request_source("backend")
        )
        return jsonify(results), 200
    except Exception as e:
        return jsonify({"error": f"Failed to fetch autocomplete places: {e}"}), 500

# Landmark priorities for coordinates-to-place resolving (lower = higher priority / more recognizable)
LANDMARK_PRIORITIES = {
    "park": 1.0,
    "playground": 1.0,
    "trailhead": 1.0,
    "peak": 1.1,
    "viewpoint": 1.2,
    "cafe": 1.2,
    "pub": 1.2,
    "bar": 1.2,
    "restaurant": 1.3,
    "fast_food": 1.3,
    "library": 1.3,
    "university": 1.4,
    "school": 1.4,
    "community_centre": 1.4,
    "place_of_worship": 1.5,
    "bus_stop": 1.8,
    "bicycle_rental": 2.0,
    "fuel": 2.0,
    "parking": 2.5,
    "drinking_water": 3.0,
    "toilets": 4.0,
    "shelter": 4.0,
    "bench": 5.0,
    "bicycle_parking": 5.0,
}

@app.route("/api/nearest-place", methods=["GET"])
def get_nearest_place():
    try:
        lat_val = request.args.get("lat")
        lng_val = request.args.get("lng") or request.args.get("lon")
        
        if not lat_val or not lng_val:
            return jsonify({"error": "Missing lat or lng query parameters"}), 400
            
        lat = float(lat_val)
        lng = float(lng_val)
    except (ValueError, TypeError):
        return jsonify({"error": "Invalid lat or lng values"}), 400

    pb_url = os.environ.get("POCKETBASE_URL", "http://127.0.0.1:8090")
    
    # Try query bounding boxes of increasing sizes: 500m (~0.005), 1.5km (~0.015), 5km (~0.05)
    deltas = [0.005, 0.015, 0.05]
    records = []
    
    for delta in deltas:
        min_lat = lat - delta
        max_lat = lat + delta
        min_lng = lng - delta
        max_lng = lng + delta
        
        try:
            resp = requests.get(
                f"{pb_url}/api/collections/places/records",
                params={
                    "filter": f"lat >= {min_lat} && lat <= {max_lat} && lng >= {min_lng} && lng <= {max_lng}",
                    "perPage": 200
                },
                timeout=5
            )
            if resp.status_code == 200:
                records = resp.json().get("items", [])
                if records:
                    break
        except Exception as e:
            print(f"[-] Error querying PocketBase for nearest place (delta={delta}): {e}")
            
    # If still no records, query a small sample of the database as fallback
    if not records:
        try:
            resp = requests.get(
                f"{pb_url}/api/collections/places/records",
                params={"perPage": 50},
                timeout=5
            )
            if resp.status_code == 200:
                records = resp.json().get("items", [])
        except Exception as e:
            print(f"[-] Error querying PocketBase fallback: {e}")
            
    if not records:
        return jsonify({
            "place": None,
            "display_name": f"near {lat:.6f}, {lng:.6f}"
        }), 200
        
    closest_place = None
    min_score = float("inf")
    closest_distance = float("inf")
    
    for record in records:
        try:
            p_lat = float(record.get("lat"))
            p_lng = float(record.get("lng"))
        except (ValueError, TypeError):
            continue
            
        dist = haversine_distance((lat, lng), (p_lat, p_lng))
        p_type = str(record.get("type") or "").lower()
        
        # Apply score penalty for less descriptive places
        multiplier = LANDMARK_PRIORITIES.get(p_type, 1.5)
        score = dist * multiplier
        
        if score < min_score:
            min_score = score
            closest_place = record
            closest_distance = dist
            
    if closest_place and closest_distance <= 5000:
        name = closest_place.get("name") or "Unknown Landmark"
        return jsonify({
            "place": {
                "id": closest_place.get("id"),
                "name": name,
                "type": closest_place.get("type"),
                "lat": closest_place.get("lat"),
                "lng": closest_place.get("lng"),
                "distance_meters": closest_distance
            },
            "display_name": f"near {name}"
        }), 200
    else:
        return jsonify({
            "place": None,
            "display_name": f"near {lat:.6f}, {lng:.6f}"
        }), 200

@app.route("/api/analytics/place-search", methods=["POST", "OPTIONS"])
def analytics_place_search():
    if request.method == "OPTIONS":
        return "", 200

    data = request.json or {}
    query = data.get("query")
    if not normalize_place_query(query):
        return jsonify({"error": "Missing query"}), 400

    selected_place = data.get("selected_place") if isinstance(data.get("selected_place"), dict) else None
    record_place_search_event(
        query,
        limit=data.get("limit"),
        result_count=data.get("result_count"),
        target=data.get("target"),
        selected_place=selected_place,
        metadata=clean_optional_json(data.get("metadata")),
        source=data.get("source") or get_request_source("web")
    )
    return jsonify({"ok": True}), 202

@app.route("/api/analytics/route-event", methods=["POST", "OPTIONS"])
def analytics_route_event():
    if request.method == "OPTIONS":
        return "", 200

    data = request.json or {}
    event_type = clean_optional_text(data.get("event_type"), 80)
    if not event_type:
        return jsonify({"error": "Missing event_type"}), 400

    allowed_events = {
        "route_rendered",
        "official_route_selected",
        "navigation_started",
        "navigation_ended",
        "route_previewed",
    }
    if event_type not in allowed_events:
        return jsonify({"error": "Unsupported event_type"}), 400

    record_route_analytics_event(event_type, data, source=data.get("source") or get_request_source("web"))
    return jsonify({"ok": True}), 202

def sanitize_route_tuning_payload(data, partial=False):
    """Validate and normalize route tuning profile payloads."""
    if not isinstance(data, dict):
        return None, "Invalid JSON payload"

    payload = {}

    if not partial or "name" in data:
        name = str(data.get("name") or "").strip()
        if not name:
            return None, "Profile name is required"
        payload["name"] = name[:80]

    weight_meta = {item["key"]: item for item in WEIGHTS_METADATA}
    raw_weights = data.get("weights")
    if raw_weights is None and not partial:
        raw_weights = {}
    if raw_weights is not None:
        if not isinstance(raw_weights, dict):
            return None, "weights must be an object"
        weights = {}
        for key, value in raw_weights.items():
            meta = weight_meta.get(key)
            if not meta:
                continue
            numeric = clamp_number(value, float(meta["min"]), float(meta["max"]))
            if numeric is not None:
                weights[key] = numeric
        for key, meta in weight_meta.items():
            if key not in weights and not partial:
                weights[key] = float(meta["default"])
        payload["weights"] = weights

    raw_offsets = data.get("offsets")
    if raw_offsets is None and not partial:
        raw_offsets = {}
    if raw_offsets is not None:
        if not isinstance(raw_offsets, dict):
            return None, "offsets must be an object"
        offsets = {}
        for key, value in raw_offsets.items():
            if not isinstance(key, str):
                continue
            numeric = clamp_number(value, -1000.0, 1000.0)
            if numeric is not None:
                offsets[key[:64]] = numeric
        payload["offsets"] = offsets

    if "is_default" in data:
        payload["is_default"] = bool(data.get("is_default"))
    elif not partial:
        payload["is_default"] = bool(data.get("isDefault", False))

    return payload, None

def route_tuning_record_to_api(record):
    return {
        "id": record.get("id"),
        "name": record.get("name") or "Routing Profile",
        "weights": record.get("weights") or {},
        "offsets": record.get("offsets") or {},
        "is_default": bool(record.get("is_default")),
        "created": record.get("created"),
        "updated": record.get("updated"),
        "user": record.get("user")
    }

def sanitize_navigation_route_update_payload(data):
    """Validate and normalize user-editable navigation route fields."""
    if not isinstance(data, dict):
        return None, "Invalid JSON payload"

    payload = {}

    if "display_name" in data:
        display_name = str(data.get("display_name") or "").strip()
        payload["display_name"] = display_name[:120]

    if "notes" in data:
        notes = str(data.get("notes") or "").strip()
        payload["notes"] = notes[:1000]

    if "start_point_name" in data:
        start_point_name = str(data.get("start_point_name") or "").strip()
        if not start_point_name:
            return None, "Start point name cannot be empty"
        payload["start_point_name"] = start_point_name[:120]

    if "end_point_name" in data:
        end_point_name = str(data.get("end_point_name") or "").strip()
        if not end_point_name:
            return None, "End point name cannot be empty"
        payload["end_point_name"] = end_point_name[:120]

    if "status" in data:
        status = str(data.get("status") or "").strip()
        if status not in {"active", "completed", "cancelled", "deleted"}:
            return None, "Invalid route status"
        payload["status"] = status

    return payload, None

def sanitize_home_location_payload(data):
    """Validate and normalize home location coordinates."""
    if not isinstance(data, dict):
        return None, "Invalid JSON payload"

    lat = clamp_number(data.get("lat"), -90.0, 90.0)
    lng = clamp_number(data.get("lng"), -180.0, 180.0)
    if lat is None or lng is None:
        return None, "Home location requires valid lat and lng coordinates"

    return {"lat": lat, "lng": lng}, None

def home_location_record_to_api(record):
    value = record.get("value") or {}
    return {
        "id": record.get("id"),
        "lat": value.get("lat"),
        "lng": value.get("lng"),
        "created": record.get("created"),
        "updated": record.get("updated")
    }

def get_home_location_record(pb_url, user_id, auth_header):
    headers = {"Authorization": auth_header} if auth_header else {}
    resp = requests.get(
        f"{pb_url}/api/collections/user_configs/records",
        headers=headers,
        params={
            "filter": f"user='{user_id}' && key='home_location'",
            "limit": 1
        },
        timeout=5
    )
    if resp.status_code != 200:
        return None, resp
    items = resp.json().get("items", [])
    return (items[0] if items else None), resp

def get_guest_owner_hash():
    guest_id = (request.headers.get("X-Guest-Id") or "").strip()
    guest_token = (request.headers.get("X-Guest-Token") or "").strip()
    if not guest_id or not guest_token or len(guest_id) > 128 or len(guest_token) > 256:
        return None
    return hashlib.sha256(f"{guest_id}:{guest_token}".encode("utf-8")).hexdigest()

def get_navigation_route_for_user(pb_url, route_id, auth_header):
    """Fetch a navigation route and verify account or guest-installation ownership."""
    headers = {"Authorization": auth_header} if auth_header else {}
    try:
        resp = requests.get(
            f"{pb_url}/api/collections/navigation_routes/records/{route_id}",
            headers=headers,
            timeout=5
        )
    except Exception as e:
        return None, None, (jsonify({"error": str(e)}), 500)

    if resp.status_code != 200:
        return None, None, (jsonify({"error": "Route not found"}), 404)

    route = resp.json()
    route_owner = route.get("user")
    guest_owner_hash = route.get("guest_owner_hash")
    user_id = get_auth_user_id(auth_header)

    if auth_header and not user_id:
        return None, None, (jsonify({"error": "Unauthorized"}), 401)

    if route_owner:
        if not user_id:
            return None, None, (jsonify({"error": "Unauthorized"}), 401)
        if route_owner != user_id:
            return None, None, (jsonify({"error": "Forbidden"}), 403)
        return route, user_id, None

    if guest_owner_hash:
        supplied_guest_hash = get_guest_owner_hash()
        if not supplied_guest_hash:
            return None, user_id, (jsonify({"error": "Guest credentials required"}), 401)
        if not hmac.compare_digest(guest_owner_hash, supplied_guest_hash):
            return None, user_id, (jsonify({"error": "Forbidden"}), 403)
        return route, user_id, None

    # Legacy guest routes predate installation credentials. Only an authenticated
    # user with the route ID may claim or delete one during migration.
    if user_id:
        return route, user_id, None
    return None, None, (jsonify({"error": "Guest route ownership unavailable"}), 403)

def clear_other_default_route_tuning_profiles(pb_url, user_id, auth_header, selected_id=None):
    try:
        resp = requests.get(
            f"{pb_url}/api/collections/route_tuning_profiles/records",
            headers={"Authorization": auth_header} if auth_header else {},
            params={
                "filter": f"user='{user_id}' && is_default=true",
                "limit": 200
            },
            timeout=5
        )
        if resp.status_code != 200:
            return
        for item in resp.json().get("items", []):
            if selected_id and item.get("id") == selected_id:
                continue
            requests.patch(
                f"{pb_url}/api/collections/route_tuning_profiles/records/{item.get('id')}",
                json={"is_default": False},
                headers={"Authorization": auth_header} if auth_header else {},
                timeout=5
            )
    except Exception as e:
        print(f"[-] Failed to clear default route tuning profiles: {e}")

@app.route("/api/settings/home", methods=["GET", "POST", "PATCH", "PUT", "DELETE", "OPTIONS"])
def home_location_settings():
    if request.method == "OPTIONS":
        return jsonify({}), 200

    pb_url = os.environ.get("POCKETBASE_URL", "http://127.0.0.1:8090")
    auth_header = request.headers.get("Authorization")
    user_id = get_auth_user_id(auth_header)

    if not user_id:
        return jsonify({"error": "Unauthorized"}), 401

    headers = {"Authorization": auth_header} if auth_header else {}

    try:
        existing, existing_resp = get_home_location_record(pb_url, user_id, auth_header)
        if existing_resp.status_code != 200:
            return jsonify({"error": f"PocketBase returned {existing_resp.status_code}: {existing_resp.text}"}), existing_resp.status_code

        if request.method == "GET":
            if not existing:
                return jsonify({"home": None}), 200
            return jsonify({"home": home_location_record_to_api(existing)}), 200

        if request.method == "DELETE":
            if not existing:
                return jsonify({"home": None}), 200
            resp = requests.delete(
                f"{pb_url}/api/collections/user_configs/records/{existing.get('id')}",
                headers=headers,
                timeout=5
            )
            if resp.status_code not in [200, 204]:
                return jsonify({"error": f"PocketBase returned {resp.status_code}: {resp.text}"}), resp.status_code
            return jsonify({"home": None}), 200

        payload, error = sanitize_home_location_payload(request.json or {})
        if error:
            return jsonify({"error": error}), 400

        if request.method == "POST" and existing:
            return jsonify({"error": "Home location already exists"}), 409

        if existing:
            resp = requests.patch(
                f"{pb_url}/api/collections/user_configs/records/{existing.get('id')}",
                json={"value": payload},
                headers=headers,
                timeout=5
            )
        else:
            resp = requests.post(
                f"{pb_url}/api/collections/user_configs/records",
                json={"user": user_id, "key": "home_location", "value": payload},
                headers=headers,
                timeout=5
            )

        if resp.status_code not in [200, 201]:
            return jsonify({"error": f"PocketBase returned {resp.status_code}: {resp.text}"}), resp.status_code

        return jsonify({"home": home_location_record_to_api(resp.json())}), resp.status_code
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route("/api/navigation/start", methods=["POST", "OPTIONS"])
def nav_start():
    if request.method == "OPTIONS":
        return jsonify({}), 200
    data = request.json or {}
    pb_url = os.environ.get("POCKETBASE_URL", "http://127.0.0.1:8090")
    
    auth_header = request.headers.get("Authorization")
    user_id = get_auth_user_id(auth_header)

    # A supplied but invalid token represents an expired authenticated session.
    # Do not silently create a guest route that the user cannot later manage.
    if auth_header and not user_id:
        return jsonify({"error": "Unauthorized"}), 401

    guest_owner_hash = None
    if not user_id:
        guest_owner_hash = get_guest_owner_hash()
        if not guest_owner_hash:
            return jsonify({"error": "Guest credentials required"}), 401
    
    import datetime
    now_str = datetime.datetime.utcnow().isoformat() + "Z"
    
    pb_payload = {
        "user": user_id,
        "guest_owner_hash": guest_owner_hash,
        "display_name": data.get("display_name"),
        "notes": data.get("notes"),
        "start_lat": data.get("start_lat"),
        "start_lon": data.get("start_lon"),
        "end_lat": data.get("end_lat"),
        "end_lon": data.get("end_lon"),
        "start_point_name": data.get("start_point_name") or "Start Point",
        "end_point_name": data.get("end_point_name") or "Destination",
        "route_geojson": data.get("route_geojson"),
        "total_length_meters": data.get("total_length_meters", 0),
        "total_estimated_time_seconds": data.get("total_estimated_time_seconds", 0),
        "status": "active",
        "started_at": now_str,
        "device_type": data.get("device_type") or "web",
        "weights": data.get("weights") or {},
        "display_distance_meters": data.get("total_length_meters", 0),
        "display_duration_seconds": data.get("total_estimated_time_seconds", 0),
        "display_average_speed": (
            float(data.get("total_length_meters") or 0.0) / float(data.get("total_estimated_time_seconds") or 0.0)
            if float(data.get("total_estimated_time_seconds") or 0.0) > 0
            else 0.0
        )
    }
    
    try:
        resp = requests.post(f"{pb_url}/api/collections/navigation_routes/records", json=pb_payload, timeout=5)
        if resp.status_code in [200, 201]:
            record = resp.json()
            record_route_analytics_event("navigation_started", {
                "route_id": record.get("id"),
                "start_lat": record.get("start_lat"),
                "start_lon": record.get("start_lon"),
                "end_lat": record.get("end_lat"),
                "end_lon": record.get("end_lon"),
                "start_point_name": record.get("start_point_name"),
                "end_point_name": record.get("end_point_name"),
                "total_length_meters": record.get("total_length_meters"),
                "weights": record.get("weights"),
                "metadata": {
                    "device_type": record.get("device_type"),
                    "status": record.get("status"),
                },
                "client_session_id": data.get("client_session_id"),
                "client_event_id": data.get("client_event_id"),
            }, source=data.get("device_type") or get_request_source("backend"))
            return jsonify({
                "status": "success",
                "route_id": record.get("id"),
                "started_at": record.get("started_at")
            }), 201
        else:
            return jsonify({"error": f"PocketBase returned {resp.status_code}: {resp.text}"}), resp.status_code
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route("/api/navigation/<route_id>/tick", methods=["POST", "OPTIONS"])
def nav_tick(route_id):
    if request.method == "OPTIONS":
        return jsonify({}), 200
    data = request.json or {}
    pb_url = os.environ.get("POCKETBASE_URL", "http://127.0.0.1:8090")
    _, _, auth_error = get_navigation_route_for_user(
        pb_url, route_id, request.headers.get("Authorization")
    )
    if auth_error:
        return auth_error
    
    import datetime
    ts = data.get("timestamp") or datetime.datetime.utcnow().isoformat() + "Z"
    
    pb_payload = {
        "route": route_id,
        "lat": data.get("lat"),
        "lon": data.get("lon"),
        "speed": data.get("speed"),
        "direction": data.get("direction"),
        "accuracy": data.get("accuracy"),
        "altitude": data.get("altitude"),
        "timestamp": ts,
        "battery_level": data.get("battery_level")
    }
    
    try:
        resp = requests.post(f"{pb_url}/api/collections/navigation_ticks/records", json=pb_payload, timeout=5)
        if resp.status_code in [200, 201]:
            try:
                route_resp = requests.get(f"{pb_url}/api/collections/navigation_routes/records/{route_id}", timeout=5)
                if route_resp.status_code == 200:
                    route_record = route_resp.json()
                    ticks_resp = requests.get(
                        f"{pb_url}/api/collections/navigation_ticks/records?filter=route='{route_id}'&sort=timestamp&limit=5000",
                        timeout=5
                    )
                    if ticks_resp.status_code == 200:
                        ticks = ticks_resp.json().get("items", [])
                        metrics = calculate_navigation_metrics(route_record, ticks=ticks, status=route_record.get("status"))
                        if route_record.get("status") == "active" and metrics.get("_idle_cutoff_at"):
                            requests.patch(
                                f"{pb_url}/api/collections/navigation_routes/records/{route_id}",
                                json={
                                    "status": "cancelled",
                                    "ended_at": metrics["_idle_cutoff_at"],
                                    **navigation_metrics_payload(metrics)
                                },
                                timeout=5
                            )
            except Exception as e:
                print(f"[-] Error checking idle navigation route {route_id}: {e}")
            return jsonify({"status": "success"}), 201
        else:
            return jsonify({"error": f"PocketBase returned {resp.status_code}: {resp.text}"}), resp.status_code
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route("/api/navigation/<route_id>/end", methods=["POST", "OPTIONS"])
def nav_end(route_id):
    if request.method == "OPTIONS":
        return jsonify({}), 200
    data = request.json or {}
    pb_url = os.environ.get("POCKETBASE_URL", "http://127.0.0.1:8090")
    route_record, _, auth_error = get_navigation_route_for_user(
        pb_url, route_id, request.headers.get("Authorization")
    )
    if auth_error:
        return auth_error
    
    now_str = data.get("ended_at") or datetime.datetime.utcnow().isoformat() + "Z"
    status = data.get("status") or "completed"
    
    ticks = []
    route_record = route_record or {}
    batched_ticks = data.get("ticks") or []
    try:
        if isinstance(batched_ticks, list):
            for tick in batched_ticks[:5000]:
                if not isinstance(tick, dict):
                    continue
                lat = tick.get("lat")
                lon = tick.get("lon")
                timestamp = tick.get("timestamp")
                if lat is None or lon is None or not timestamp:
                    continue
                pb_tick_payload = {
                    "route": route_id,
                    "lat": lat,
                    "lon": lon,
                    "speed": tick.get("speed"),
                    "direction": tick.get("direction"),
                    "accuracy": tick.get("accuracy"),
                    "altitude": tick.get("altitude"),
                    "timestamp": timestamp,
                    "battery_level": tick.get("battery_level")
                }
                tick_create_resp = requests.post(
                    f"{pb_url}/api/collections/navigation_ticks/records",
                    json=pb_tick_payload,
                    timeout=3
                )
                if tick_create_resp.status_code in [200, 201]:
                    ticks.append(tick_create_resp.json())
        
        ticks_resp = requests.get(f"{pb_url}/api/collections/navigation_ticks/records?filter=route='{route_id}'&sort=timestamp&limit=5000", timeout=5)
        if ticks_resp.status_code == 200:
            ticks = ticks_resp.json().get("items", [])
    except Exception as e:
        print(f"Error fetching ticks for calculations: {e}")
    
    metrics = calculate_navigation_metrics(route_record, ticks=ticks, ended_at=now_str, status=status)
    idle_cutoff_at = metrics.get("_idle_cutoff_at")
    if idle_cutoff_at:
        now_str = idle_cutoff_at
        if status == "active":
            status = "cancelled"
    
    pb_update = {
        "status": status,
        "ended_at": now_str,
        "ended_lat": data.get("ended_lat"),
        "ended_lon": data.get("ended_lon"),
        **navigation_metrics_payload(metrics)
    }
    
    try:
        resp = requests.patch(f"{pb_url}/api/collections/navigation_routes/records/{route_id}", json=pb_update, timeout=5)
        if resp.status_code == 200:
            updated_route = resp.json()
            record_route_analytics_event("navigation_ended", {
                "route_id": route_id,
                "start_lat": route_record.get("start_lat") or updated_route.get("start_lat"),
                "start_lon": route_record.get("start_lon") or updated_route.get("start_lon"),
                "end_lat": route_record.get("end_lat") or updated_route.get("end_lat"),
                "end_lon": route_record.get("end_lon") or updated_route.get("end_lon"),
                "start_point_name": route_record.get("start_point_name") or updated_route.get("start_point_name"),
                "end_point_name": route_record.get("end_point_name") or updated_route.get("end_point_name"),
                "total_length_meters": updated_route.get("total_length_meters") or route_record.get("total_length_meters"),
                "weights": route_record.get("weights") or updated_route.get("weights"),
                "metadata": {
                    "status": status,
                    "ended_lat": data.get("ended_lat"),
                    "ended_lon": data.get("ended_lon"),
                    "actual_distance_meters": metrics.get("actual_distance_meters"),
                    "actual_duration_seconds": metrics.get("actual_duration_seconds"),
                    "tick_count": len(ticks),
                },
                "client_session_id": data.get("client_session_id"),
                "client_event_id": data.get("client_event_id"),
            }, source=(route_record.get("device_type") or updated_route.get("device_type") or get_request_source("backend")))
            return jsonify({
                "status": "success",
                **navigation_metrics_payload(metrics)
            })
        else:
            return jsonify({"error": f"PocketBase returned {resp.status_code}: {resp.text}"}), resp.status_code
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route("/api/navigation/history", methods=["GET"])
def nav_history():
    pb_url = os.environ.get("POCKETBASE_URL", "http://127.0.0.1:8090")
    
    auth_header = request.headers.get("Authorization")
    user_id = get_auth_user_id(auth_header)

    # An invalid supplied token is an expired/invalid session, not an anonymous
    # history request. Returning [] here makes clients look signed in with an
    # empty account and hides the authentication failure.
    if auth_header and not user_id:
        return jsonify({"error": "Unauthorized"}), 401
    
    url = f"{pb_url}/api/collections/navigation_routes/records"
    params = {"sort": "-started_at", "limit": 50}
    if user_id:
        params["filter"] = f"user='{user_id}'"
    else:
        guest_owner_hash = get_guest_owner_hash()
        if not guest_owner_hash:
            return jsonify({"error": "Guest credentials required"}), 401
        route_ids_str = request.args.get("route_ids")
        if route_ids_str:
            route_ids = [rid.strip() for rid in route_ids_str.split(",") if re.fullmatch(r"[A-Za-z0-9]{15}", rid.strip())]
            if not route_ids:
                return jsonify([])
            filter_query = "||".join([f"id='{rid}'" for rid in route_ids])
            params["filter"] = f"guest_owner_hash='{guest_owner_hash}'&&({filter_query})"
        else:
            params["filter"] = f"guest_owner_hash='{guest_owner_hash}'"
            
    try:
        resp = requests.get(url, params=params, timeout=5)
        if resp.status_code == 200:
            items = resp.json().get("items", [])
            normalized_items = [route_with_display_metrics(item) for item in items]
            normalized_items.sort(key=route_date_sort_key, reverse=True)
            return jsonify(normalized_items)
        else:
            return jsonify({"error": f"PocketBase returned {resp.status_code}: {resp.text}"}), resp.status_code
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route("/api/navigation/<route_id>", methods=["GET", "PATCH", "DELETE", "OPTIONS"])
def nav_detail(route_id):
    if request.method == "OPTIONS":
        return jsonify({}), 200

    pb_url = os.environ.get("POCKETBASE_URL", "http://127.0.0.1:8090")
    auth_header = request.headers.get("Authorization")
    headers = {"Authorization": auth_header} if auth_header else {}
    route, _, auth_error = get_navigation_route_for_user(pb_url, route_id, auth_header)
    if auth_error:
        return auth_error

    if request.method in ["PATCH", "DELETE"]:
        if request.method == "DELETE":
            try:
                tick_resp = requests.get(
                    f"{pb_url}/api/collections/navigation_ticks/records",
                    headers=headers,
                    params={
                        "filter": f"route='{route_id}'",
                        "limit": 5000
                    },
                    timeout=5
                )
                if tick_resp.status_code == 200:
                    for tick in tick_resp.json().get("items", []):
                        requests.delete(
                            f"{pb_url}/api/collections/navigation_ticks/records/{tick.get('id')}",
                            headers=headers,
                            timeout=3
                        )

                resp = requests.delete(
                    f"{pb_url}/api/collections/navigation_routes/records/{route_id}",
                    headers=headers,
                    timeout=5
                )
                if resp.status_code in [200, 204]:
                    return jsonify({"status": "success"})
                return jsonify({"error": f"PocketBase returned {resp.status_code}: {resp.text}"}), resp.status_code
            except Exception as e:
                return jsonify({"error": str(e)}), 500

        payload, error = sanitize_navigation_route_update_payload(request.json or {})
        if error:
            return jsonify({"error": error}), 400
        if not payload:
            return jsonify({"error": "No supported fields supplied"}), 400

        try:
            resp = requests.patch(
                f"{pb_url}/api/collections/navigation_routes/records/{route_id}",
                json=payload,
                headers=headers,
                timeout=5
            )
            if resp.status_code == 200:
                return jsonify(route_with_display_metrics(resp.json()))
            return jsonify({"error": f"PocketBase returned {resp.status_code}: {resp.text}"}), resp.status_code
        except Exception as e:
            return jsonify({"error": str(e)}), 500
    
    try:
        ticks_resp = requests.get(f"{pb_url}/api/collections/navigation_ticks/records?filter=route='{route_id}'&sort=timestamp&limit=5000", timeout=5)
        ticks = []
        if ticks_resp.status_code == 200:
            ticks = sorted_navigation_ticks(ticks_resp.json().get("items", []))
            
        route["ticks"] = ticks
        return jsonify(route_with_display_metrics(route))
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route("/api/route-tuning-profiles", methods=["GET", "POST", "OPTIONS"])
def route_tuning_profiles():
    if request.method == "OPTIONS":
        return jsonify({}), 200

    auth_header = request.headers.get("Authorization")
    user_id = get_auth_user_id(auth_header)
    if not user_id:
        return jsonify({"error": "Unauthorized"}), 401

    pb_url = os.environ.get("POCKETBASE_URL", "http://127.0.0.1:8090")
    headers = {"Authorization": auth_header} if auth_header else {}

    if request.method == "GET":
        try:
            resp = requests.get(
                f"{pb_url}/api/collections/route_tuning_profiles/records",
                headers=headers,
                params={
                    "filter": f"user='{user_id}'",
                    "limit": 200
                },
                timeout=5
            )
            if resp.status_code == 200:
                items = [route_tuning_record_to_api(item) for item in resp.json().get("items", [])]
                items.sort(key=lambda item: (item.get("is_default", False), item.get("updated") or item.get("created") or ""), reverse=True)
                return jsonify(items)
            return jsonify({"error": f"PocketBase returned {resp.status_code}: {resp.text}"}), resp.status_code
        except Exception as e:
            return jsonify({"error": str(e)}), 500

    data = request.json or {}
    payload, error = sanitize_route_tuning_payload(data, partial=False)
    if error:
        return jsonify({"error": error}), 400
    payload["user"] = user_id

    try:
        if payload.get("is_default"):
            clear_other_default_route_tuning_profiles(pb_url, user_id, auth_header)
        resp = requests.post(
            f"{pb_url}/api/collections/route_tuning_profiles/records",
            json=payload,
            headers=headers,
            timeout=5
        )
        if resp.status_code in [200, 201]:
            return jsonify(route_tuning_record_to_api(resp.json())), 201
        return jsonify({"error": f"PocketBase returned {resp.status_code}: {resp.text}"}), resp.status_code
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route("/api/route-tuning-profiles/<profile_id>", methods=["PATCH", "DELETE", "OPTIONS"])
def route_tuning_profile_detail(profile_id):
    if request.method == "OPTIONS":
        return jsonify({}), 200

    auth_header = request.headers.get("Authorization")
    user_id = get_auth_user_id(auth_header)
    if not user_id:
        return jsonify({"error": "Unauthorized"}), 401

    pb_url = os.environ.get("POCKETBASE_URL", "http://127.0.0.1:8090")
    headers = {"Authorization": auth_header} if auth_header else {}

    try:
        existing = requests.get(
            f"{pb_url}/api/collections/route_tuning_profiles/records/{profile_id}",
            headers=headers,
            timeout=5
        )
        if existing.status_code != 200:
            return jsonify({"error": "Profile not found"}), 404
        if existing.json().get("user") != user_id:
            return jsonify({"error": "Forbidden"}), 403

        if request.method == "DELETE":
            resp = requests.delete(
                f"{pb_url}/api/collections/route_tuning_profiles/records/{profile_id}",
                headers=headers,
                timeout=5
            )
            if resp.status_code in [200, 204]:
                return jsonify({"status": "success"})
            return jsonify({"error": f"PocketBase returned {resp.status_code}: {resp.text}"}), resp.status_code

        payload, error = sanitize_route_tuning_payload(request.json or {}, partial=True)
        if error:
            return jsonify({"error": error}), 400
        if payload.get("is_default"):
            clear_other_default_route_tuning_profiles(pb_url, user_id, auth_header, selected_id=profile_id)

        resp = requests.patch(
            f"{pb_url}/api/collections/route_tuning_profiles/records/{profile_id}",
            json=payload,
            headers=headers,
            timeout=5
        )
        if resp.status_code == 200:
            return jsonify(route_tuning_record_to_api(resp.json()))
        return jsonify({"error": f"PocketBase returned {resp.status_code}: {resp.text}"}), resp.status_code
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route("/api/route-tuning-profiles/sync", methods=["POST", "OPTIONS"])
def route_tuning_profiles_sync():
    if request.method == "OPTIONS":
        return jsonify({}), 200

    auth_header = request.headers.get("Authorization")
    user_id = get_auth_user_id(auth_header)
    if not user_id:
        return jsonify({"error": "Unauthorized"}), 401

    data = request.json or {}
    profiles = data.get("profiles", [])
    if not isinstance(profiles, list):
        return jsonify({"error": "profiles must be a list"}), 400

    pb_url = os.environ.get("POCKETBASE_URL", "http://127.0.0.1:8090")
    headers = {"Authorization": auth_header} if auth_header else {}
    synced_profiles = []
    deleted_profiles = []

    for profile in profiles:
        local_id = profile.get("local_id") or profile.get("id")
        server_id = profile.get("server_id")
        operation = profile.get("operation") or ("delete" if profile.get("deleted") else "upsert")

        try:
            if operation == "delete":
                if server_id:
                    resp = requests.delete(
                        f"{pb_url}/api/collections/route_tuning_profiles/records/{server_id}",
                        headers=headers,
                        timeout=5
                    )
                    if resp.status_code not in [200, 204, 404]:
                        print(f"[-] Failed to delete route tuning profile {server_id}: {resp.status_code} {resp.text}")
                        continue
                deleted_profiles.append({"local_id": local_id, "server_id": server_id})
                continue

            payload, error = sanitize_route_tuning_payload(profile, partial=False)
            if error:
                print(f"[-] Invalid route tuning profile {local_id}: {error}")
                continue
            payload["user"] = user_id

            if payload.get("is_default"):
                clear_other_default_route_tuning_profiles(pb_url, user_id, auth_header, selected_id=server_id)

            if server_id:
                existing = requests.get(
                    f"{pb_url}/api/collections/route_tuning_profiles/records/{server_id}",
                    headers=headers,
                    timeout=5
                )
                if existing.status_code == 200 and existing.json().get("user") == user_id:
                    resp = requests.patch(
                        f"{pb_url}/api/collections/route_tuning_profiles/records/{server_id}",
                        json=payload,
                        headers=headers,
                        timeout=5
                    )
                else:
                    resp = requests.post(
                        f"{pb_url}/api/collections/route_tuning_profiles/records",
                        json=payload,
                        headers=headers,
                        timeout=5
                    )
            else:
                resp = requests.post(
                    f"{pb_url}/api/collections/route_tuning_profiles/records",
                    json=payload,
                    headers=headers,
                    timeout=5
                )

            if resp.status_code in [200, 201]:
                record = route_tuning_record_to_api(resp.json())
                synced_profiles.append({
                    "local_id": local_id,
                    "server_id": record.get("id"),
                    "profile": record
                })
            else:
                print(f"[-] Failed to sync route tuning profile {local_id}: {resp.status_code} {resp.text}")
        except Exception as e:
            print(f"[-] Error syncing route tuning profile {local_id}: {e}")

    return jsonify({
        "status": "success",
        "synced_profiles": synced_profiles,
        "deleted_profiles": deleted_profiles
    }), 200

@app.route("/api/navigation/sync", methods=["POST", "OPTIONS"])
def nav_sync():
    if request.method == "OPTIONS":
        return jsonify({}), 200
    
    auth_header = request.headers.get("Authorization")
    user_id = get_auth_user_id(auth_header)
    
    if not user_id:
        return jsonify({"error": "Unauthorized"}), 401
        
    data = request.json or {}
    routes = data.get("routes", [])
    pb_url = os.environ.get("POCKETBASE_URL", "http://127.0.0.1:8090")
    headers = {"Authorization": auth_header} if auth_header else {}
    
    synced_routes = []
    
    for r in routes:
        local_id = r.get("local_id")
        server_id = r.get("server_id")
        operation = r.get("operation") or ("delete" if r.get("deleted") else "upsert")

        if operation == "delete":
            if server_id:
                try:
                    existing, _, auth_error = get_navigation_route_for_user(pb_url, server_id, auth_header)
                    if auth_error:
                        print(f"[-] Skipping route delete {server_id}: authorization failed")
                        continue
                    requests.delete(
                        f"{pb_url}/api/collections/navigation_routes/records/{server_id}",
                        headers=headers,
                        timeout=5
                    )
                except Exception as e:
                    print(f"[-] Error deleting route {server_id}: {e}")
                    continue
            synced_routes.append({
                "local_id": local_id,
                "server_id": server_id,
                "operation": "delete"
            })
            continue

        pb_payload = {
            "user": user_id,
            "guest_owner_hash": None,
            "display_name": r.get("display_name"),
            "notes": r.get("notes"),
            "start_lat": r.get("start_lat"),
            "start_lon": r.get("start_lon"),
            "end_lat": r.get("end_lat"),
            "end_lon": r.get("end_lon"),
            "start_point_name": r.get("start_point_name") or "Start Point",
            "end_point_name": r.get("end_point_name") or "Destination",
            "route_geojson": r.get("route_geojson") or {
                "type": "Feature",
                "geometry": {
                    "type": "LineString",
                    "coordinates": [
                        [r.get("start_lon") or 0.0, r.get("start_lat") or 0.0],
                        [r.get("end_lon") or 0.0, r.get("end_lat") or 0.0]
                    ]
                },
                "properties": {}
            },
            "total_length_meters": r.get("total_length_meters", 0.0),
            "total_estimated_time_seconds": r.get("total_estimated_time_seconds", 0.0),
            "status": r.get("status") or "completed",
            "started_at": r.get("started_at"),
            "ended_at": r.get("ended_at"),
            "ended_lat": r.get("ended_lat"),
            "ended_lon": r.get("ended_lon"),
            "device_type": r.get("device_type") or "web",
            "weights": r.get("weights") or {}
        }
        
        try:
            if server_id:
                existing, _, auth_error = get_navigation_route_for_user(pb_url, server_id, auth_header)
                if auth_error:
                    print(f"[-] Skipping route update {server_id}: authorization failed")
                    continue
                resp = requests.patch(
                    f"{pb_url}/api/collections/navigation_routes/records/{server_id}",
                    json=pb_payload,
                    headers=headers,
                    timeout=5
                )
            else:
                resp = requests.post(
                    f"{pb_url}/api/collections/navigation_routes/records",
                    json=pb_payload,
                    headers=headers,
                    timeout=5
                )
            if resp.status_code in [200, 201]:
                record = resp.json()
                server_id = record.get("id")
                
                # Sync ticks
                ticks = r.get("ticks", [])
                for t in ticks if not r.get("server_id") else []:
                    pb_tick_payload = {
                        "route": server_id,
                        "lat": t.get("lat"),
                        "lon": t.get("lon"),
                        "speed": t.get("speed"),
                        "direction": t.get("direction"),
                        "accuracy": t.get("accuracy"),
                        "altitude": t.get("altitude"),
                        "timestamp": t.get("timestamp"),
                        "battery_level": t.get("battery_level")
                    }
                    requests.post(
                        f"{pb_url}/api/collections/navigation_ticks/records",
                        json=pb_tick_payload,
                        headers=headers,
                        timeout=3
                    )

                try:
                    ticks_resp = requests.get(
                        f"{pb_url}/api/collections/navigation_ticks/records?filter=route='{server_id}'&sort=timestamp&limit=5000",
                        headers=headers,
                        timeout=5
                    )
                    stored_ticks = ticks_resp.json().get("items", []) if ticks_resp.status_code == 200 else []
                    route_for_metrics = {**pb_payload, **record, "status": pb_payload.get("status")}
                    metrics = calculate_navigation_metrics(
                        route_for_metrics,
                        ticks=stored_ticks,
                        ended_at=pb_payload.get("ended_at"),
                        status=pb_payload.get("status")
                    )
                    metric_payload = navigation_metrics_payload(metrics)
                    if metrics.get("_idle_cutoff_at"):
                        metric_payload["ended_at"] = metrics["_idle_cutoff_at"]
                        if pb_payload.get("status") == "active":
                            metric_payload["status"] = "cancelled"
                    requests.patch(
                        f"{pb_url}/api/collections/navigation_routes/records/{server_id}",
                        json=metric_payload,
                        headers=headers,
                        timeout=5
                    )
                except Exception as e:
                    print(f"[-] Error recalculating synced route metrics {server_id}: {e}")
                
                synced_routes.append({
                    "local_id": local_id,
                    "server_id": server_id
                })
            else:
                print(f"[-] PocketBase route save returned {resp.status_code}: {resp.text}")
        except Exception as e:
            print(f"[-] Error syncing route {local_id}: {e}")
            
    return jsonify({
        "status": "success",
        "synced_routes": synced_routes
    }), 200

if __name__ == "__main__":
    # Pre-build graph on startup for all regions
    print("[*] Starting Multi-Region Bike Router backend...")
    for region_id in REGIONS:
        print(f"[*] Building routing graph for {region_id}...")
        build_graph(region_id)
        graph = graphs_by_region.get(region_id)
        if graph is None:
            print(f"[!] Warning: Graph for {region_id} failed to initialize!")
        else:
            print(f"[+] Graph for {region_id} ready: {graph.number_of_nodes()} nodes, {graph.number_of_edges()} edges")

    # Verify PocketBase connection
    pb_url = os.environ.get("POCKETBASE_URL", "http://127.0.0.1:8090")
    print(f"[*] PocketBase connection check: pinging {pb_url}...")
    try:
        resp = requests.get(f"{pb_url}/api/health", timeout=2)
        if resp.status_code == 200:
            print(f"[+] PocketBase is connected and healthy: {resp.json()}")
        else:
            print(f"[-] PocketBase returned status {resp.status_code}")
    except Exception as e:
        print(f"[-] PocketBase connection failed: {e}")

    print("[*] Starting Flask server on 0.0.0.0:3001")
    app.run(host="0.0.0.0", port=3001, debug=True, use_reloader=False)
