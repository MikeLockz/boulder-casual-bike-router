import os
import json
import math
import sys

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

# Bounding box for Boulder, CO: [South, West, North, East]
BOULDER_BBOX = (39.96, -105.30, 40.09, -105.18)
CACHE_FILE = os.path.join(os.path.dirname(__file__), "boulder_osm_data.json")
PLAYGROUNDS_CACHE_FILE = os.path.join(os.path.dirname(__file__), "boulder_playground_data.json")
STRESS_CACHE_FILE = os.path.join(os.path.dirname(__file__), "boulder_bike_stress_data.json")
OFFSTREET_CACHE_FILE = os.path.join(os.path.dirname(__file__), "boulder_bike_offstreet_data.json")

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

# In-memory graph storage
G_connected = None
nodes_global = {}
safe_crossing_nodes_global = set()
four_lane_nodes_global = set()
bike_routes_geojson_global = None

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

def fetch_osm_data():
    """Fetch OpenStreetMap data for Boulder from Overpass API or load from cache."""
    if os.path.exists(CACHE_FILE):
        print("Loading OSM data from cache...")
        with open(CACHE_FILE, "r") as f:
            return json.load(f)
            
    print("Fetching OSM data from Overpass API (this may take a few seconds)...")
    s, w, n, e = BOULDER_BBOX
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
    with open(CACHE_FILE, "w") as f:
        json.dump(data, f)
        
    return data

def fetch_playground_data():
    """Fetch playground locations data for Boulder from Open Data portal or load from cache."""
    if os.path.exists(PLAYGROUNDS_CACHE_FILE):
        try:
            with open(PLAYGROUNDS_CACHE_FILE, "r") as f:
                return json.load(f)
        except Exception as e:
            print(f"Error reading playgrounds cache: {e}")
            
    print("Fetching playground data from Boulder Open Data portal...")
    url = "https://opendata.arcgis.com/datasets/b1297c2328b343528f70dfd78c6de459_1.geojson"
    headers = {
        "User-Agent": "BoulderCasualBikeRouter/1.0 (contact: support@bouldercasualrouter.local)"
    }
    try:
        response = requests.get(url, headers=headers, timeout=30)
        response.raise_for_status()
        data = response.json()
        
        # Save cache
        with open(PLAYGROUNDS_CACHE_FILE, "w") as f:
            json.dump(data, f)
        return data
    except Exception as e:
        print(f"Error fetching playground data: {e}")
        # Return cache if available as a fallback
        if os.path.exists(PLAYGROUNDS_CACHE_FILE):
            with open(PLAYGROUNDS_CACHE_FILE, "r") as f:
                return json.load(f)
        raise e

def fetch_stress_data():
    """Fetch bike stress data for Boulder from Open Data portal or load from cache."""
    if os.path.exists(STRESS_CACHE_FILE):
        try:
            with open(STRESS_CACHE_FILE, "r") as f:
                return json.load(f)
        except Exception as e:
            print(f"Error reading stress cache: {e}")
            
    print("Fetching bike stress data from Boulder Open Data portal...")
    url = "https://opendata.arcgis.com/datasets/e20bc9b72c3b4d0fac167d722a7cf1b7_0.geojson"
    headers = {
        "User-Agent": "BoulderCasualBikeRouter/1.0 (contact: support@bouldercasualrouter.local)"
    }
    try:
        response = requests.get(url, headers=headers, timeout=30)
        response.raise_for_status()
        data = response.json()
        with open(STRESS_CACHE_FILE, "w") as f:
            json.dump(data, f)
        return data
    except Exception as e:
        print(f"Error fetching bike stress data: {e}")
        if os.path.exists(STRESS_CACHE_FILE):
            with open(STRESS_CACHE_FILE, "r") as f:
                return json.load(f)
        raise e

def fetch_offstreet_data():
    """Fetch bike off-street data for Boulder from Open Data portal or load from cache."""
    if os.path.exists(OFFSTREET_CACHE_FILE):
        try:
            with open(OFFSTREET_CACHE_FILE, "r") as f:
                return json.load(f)
        except Exception as e:
            print(f"Error reading off-street cache: {e}")
            
    print("Fetching bike off-street data from Boulder Open Data portal...")
    url = "https://opendata.arcgis.com/datasets/8cae0bbbd3154abe8264fa349b8f245f_0.geojson"
    headers = {
        "User-Agent": "BoulderCasualBikeRouter/1.0 (contact: support@bouldercasualrouter.local)"
    }
    try:
        response = requests.get(url, headers=headers, timeout=30)
        response.raise_for_status()
        data = response.json()
        with open(OFFSTREET_CACHE_FILE, "w") as f:
            json.dump(data, f)
        return data
    except Exception as e:
        print(f"Error fetching bike off-street data: {e}")
        if os.path.exists(OFFSTREET_CACHE_FILE):
            with open(OFFSTREET_CACHE_FILE, "r") as f:
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


def build_graph(weights=None):
    """Build the NetworkX routing graph from OSM JSON data."""
    global G_connected, nodes_global, safe_crossing_nodes_global, four_lane_nodes_global
    if weights is None:
        weights = DEFAULT_WEIGHTS

    data = fetch_osm_data()
    G = nx.Graph()

    # Load stress data and build spatial index
    try:
        stress_data = fetch_stress_data()
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
        print("Bicycle stress spatial index built successfully.")
    except Exception as e:
        print(f"Error building bicycle stress spatial index: {e}")
        spatial_index = None

    # Load off-street data and build spatial index
    try:
        offstreet_data = fetch_offstreet_data()
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
        print("Off-street spatial index built successfully.")
    except Exception as e:
        print(f"Error building off-street spatial index: {e}")
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
                            
                            G.add_edge(u_side1, v_side1,
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
                                       tags=tags)
                            G.add_edge(u_side2, v_side2,
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
                                       tags=tags)
                
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
                        
                        if not G.has_node(u_name):
                            G.add_node(u_name, lat=nodes[u]["lat"], lon=nodes[u]["lon"])
                        if not G.has_node(v_name):
                            G.add_node(v_name, lat=nodes[v]["lat"], lon=nodes[v]["lon"])
                            
                        G.add_edge(u_name, v_name,
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
                                   tags=tags)

    # Get largest connected component to ensure routes are reachable
    if len(G) > 0:
        largest_cc = max(nx.connected_components(G), key=len)
        G_connected = G.subgraph(largest_cc).copy()
        print(f"Graph loaded successfully: {G_connected.number_of_nodes()} nodes, {G_connected.number_of_edges()} edges.")
    else:
        G_connected = G
        print("Warning: Graph is empty.")

    # Store global references for API usage
    nodes_global = nodes
    safe_crossing_nodes_global = safe_crossing_nodes
    four_lane_nodes_global = four_lane_nodes
    
    # Pre-build bike routes GeoJSON
    build_bike_routes_geojson()

    # Pre-populate graph with default weights so CLI routing tools remain in sync
    print("Populating graph with default routing weights...")
    update_graph_weights(G_connected, weights)

def build_bike_routes_geojson():
    """Load, filter, and simplify official bike routes data into a lightweight FeatureCollection."""
    global bike_routes_geojson_global
    print("Compiling lightweight official bike routes GeoJSON...")
    
    features = []
    
    # 1. Process bike stress data (on-street network)
    if os.path.exists(STRESS_CACHE_FILE):
        try:
            with open(STRESS_CACHE_FILE, "r") as f:
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
            print(f"Error compiling stress routes: {e}")
            
    # 2. Process off-street data
    if os.path.exists(OFFSTREET_CACHE_FILE):
        try:
            with open(OFFSTREET_CACHE_FILE, "r") as f:
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
            print(f"Error compiling off-street routes: {e}")
            
    bike_routes_geojson_global = {
        "type": "FeatureCollection",
        "features": features
    }
    print(f"Successfully compiled {len(features)} official bike route features.")

def find_nearest_node(target_coord):
    """Find the nearest node in the connected graph to the target coordinate."""
    min_dist = float("inf")
    nearest_node = None
    for node, data in G_connected.nodes(data=True):
        dist = haversine_distance(target_coord, (data["lat"], data["lon"]))
        if dist < min_dist:
            min_dist = dist
            nearest_node = node
    return nearest_node, min_dist

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
        
    global G_connected
    data = request.json or {}
    
    start_lat = data.get("start_lat")
    start_lon = data.get("start_lon")
    end_lat = data.get("end_lat")
    end_lon = data.get("end_lon")
    custom_weights = data.get("weights") or DEFAULT_WEIGHTS
    
    if not all([start_lat, start_lon, end_lat, end_lon]):
        return jsonify({"error": "Missing coordinates"}), 400

    # Recalculate weights on the graph dynamically using client weights
    update_graph_weights(G_connected, custom_weights)

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
            
            sub_start_node, sub_start_dist = find_nearest_node((sub_start_lat, sub_start_lon))
            sub_end_node, sub_end_dist = find_nearest_node((sub_end_lat, sub_end_lon))
            
            if sub_start_node is None or sub_end_node is None:
                return jsonify({"error": f"Could not locate routing node for point {p+1}."}), 404
                
            if p == 0:
                start_node_dist = sub_start_dist
            if p == len(route_points) - 2:
                end_node_dist = sub_end_dist
                
            path_nodes = nx.shortest_path(G_connected, source=sub_start_node, target=sub_end_node, weight="weight")
            
            for i in range(len(path_nodes) - 1):
                u = path_nodes[i]
                v = path_nodes[i+1]
                edge_data = G_connected.get_edge_data(u, v)
                length = edge_data.get("length", 0)
                infra_type = edge_data.get("type", "residential")
                name = edge_data.get("name", "Unnamed Path")
                multiplier = edge_data.get("multiplier", 1.0)
                
                edge_weight = edge_data.get("weight", length * multiplier)
                total_length += length
                total_weight += edge_weight
                
                node_u_data = G_connected.nodes[u]
                node_v_data = G_connected.nodes[v]
                
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
                
        return jsonify({
            "segments": segments,
            "total_length_meters": total_length,
            "total_weight": total_weight,
            "start_node_dist_meters": start_node_dist,
            "end_node_dist_meters": end_node_dist
        })
        
    except nx.NetworkXNoPath:
        return jsonify({"error": "No route exists between the selected points."}), 404
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route("/api/inspect-edge", methods=["GET"])
def inspect_edge():
    """Inspect the nearest edge in the routing graph and return its full attributes and geometry."""
    global G_connected
    
    lat_val = request.args.get("lat")
    lon_val = request.args.get("lon")
    
    if not lat_val or not lon_val:
        return jsonify({"error": "Missing coordinates"}), 400
        
    try:
        click_coord = (float(lat_val), float(lon_val))
    except ValueError:
        return jsonify({"error": "Invalid coordinates"}), 400
        
    # Find nearest node
    nearest_node, _ = find_nearest_node(click_coord)
    if nearest_node is None:
        return jsonify({"error": "No road network found near click."}), 404
        
    best_edge = None
    min_dist = float("inf")
    
    # Check edges connected to nearest_node to find the closest segment line
    for neighbor in G_connected.neighbors(nearest_node):
        node_u_data = G_connected.nodes[nearest_node]
        node_v_data = G_connected.nodes[neighbor]
        pt_u = (node_u_data["lat"], node_u_data["lon"])
        pt_v = (node_v_data["lat"], node_v_data["lon"])
        
        dist = point_to_segment_distance(click_coord, pt_u, pt_v)
        if dist < min_dist:
            min_dist = dist
            best_edge = (nearest_node, neighbor)
            
    if best_edge is None:
        return jsonify({"error": "Could not identify an edge."}), 404
        
    u, v = best_edge
    edge_data = G_connected.get_edge_data(u, v)
    node_u_data = G_connected.nodes[u]
    node_v_data = G_connected.nodes[v]
    
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
        "name": "North Boulder ➔ Iris Ave",
        "desc": "Cedar Ave to 28th St & Iris",
        "start": [40.028446, -105.281088],
        "end": [40.038662, -105.263851],
        "waypoints": [],
        "route_type": None
    },
    {
        "name": "CU Campus ➔ North Park",
        "desc": "Broadway Path & residential streets",
        "start": [40.007, -105.263],
        "end": [40.028, -105.283],
        "waypoints": [],
        "route_type": None
    },
    {
        "name": "Valmont Park ➔ Pearl Street Mall",
        "desc": "Using off-street multi-use paths",
        "start": [40.030, -105.234],
        "end": [40.018, -105.279],
        "waypoints": [],
        "route_type": None
    },
    {
        "name": "Table Mesa ➔ CU Campus",
        "desc": "Safe commuting corridors",
        "start": [39.986, -105.262],
        "end": [40.007, -105.263],
        "waypoints": [],
        "route_type": None
    },
    {
        "name": "Boulder B-180 Loop",
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
        "name": "Boulder B-360 Loop",
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
    }
]

@app.route("/api/config", methods=["GET"])
def get_config():
    """Get the full list of dynamic configuration presets and sliders metadata."""
    pb_url = os.environ.get("POCKETBASE_URL", "http://127.0.0.1:8090")
    try:
        resp = requests.get(f"{pb_url}/api/collections/global_configs/records", timeout=2)
        if resp.status_code == 200:
            data = resp.json()
            items = data.get("items", [])
            configs_dict = {item.get("key"): item.get("value") for item in items if "key" in item and "value" in item}
            
            weights = configs_dict.get("weights")
            presets = configs_dict.get("presets")
            
            if weights and presets:
                return jsonify({
                    "weights": weights,
                    "presets": presets
                })
    except Exception as e:
        print(f"[-] Failed to fetch config from PocketBase: {e}. Falling back to default config.")
        
    return jsonify({
        "weights": WEIGHTS_METADATA,
        "presets": ROUTE_PRESETS
    })


@app.route("/api/crossings", methods=["GET"])
def get_crossings():
    """Get all crossing nodes on 4+ lane roads or safe crossings in the network."""
    global nodes_global, safe_crossing_nodes_global, four_lane_nodes_global
    
    crossings_list = []
    for nid, ndata in nodes_global.items():
        tags = ndata.get("tags", {})
        highway = tags.get("highway", "")
        if highway == "crossing" or highway == "traffic_signals":
            if nid in four_lane_nodes_global or nid in safe_crossing_nodes_global:
                lat = ndata["lat"]
                lon = ndata["lon"]
                
                # Classify type
                if nid in safe_crossing_nodes_global:
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
    """Get processed playground locations sorted alphabetically with display names and centroids."""
    from collections import Counter
    try:
        data = fetch_playground_data()
        features = data.get("features", [])
        
        # Filter for active playgrounds
        playgrounds = []
        for f in features:
            prop = f.get("properties", {})
            geom = f.get("geometry", {})
            if prop.get("PLAYTYPE") == "Park Playground" and geom and geom.get("type") == "Polygon":
                playgrounds.append(f)
                
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
        return jsonify({"error": str(e)}), 500

@app.route("/api/bike-routes", methods=["GET"])
def get_bike_routes():
    """API endpoint to get the compiled, lightweight official bike routes GeoJSON."""
    global bike_routes_geojson_global
    if bike_routes_geojson_global is None:
        build_bike_routes_geojson()
    return jsonify(bike_routes_geojson_global)

# Simple CORS support for development
@app.after_request
def add_cors_headers(response):
    response.headers["Access-Control-Allow-Origin"] = "*"
    response.headers["Access-Control-Allow-Headers"] = "Content-Type"
    response.headers["Access-Control-Allow-Methods"] = "POST, GET, OPTIONS"
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

@app.route("/api/navigation/start", methods=["POST", "OPTIONS"])
def nav_start():
    if request.method == "OPTIONS":
        return jsonify({}), 200
    data = request.json or {}
    pb_url = os.environ.get("POCKETBASE_URL", "http://127.0.0.1:8090")
    
    auth_header = request.headers.get("Authorization")
    user_id = get_auth_user_id(auth_header)
    
    import datetime
    now_str = datetime.datetime.utcnow().isoformat() + "Z"
    
    pb_payload = {
        "user": user_id,
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
        "weights": data.get("weights") or {}
    }
    
    try:
        resp = requests.post(f"{pb_url}/api/collections/navigation_routes/records", json=pb_payload, timeout=5)
        if resp.status_code in [200, 201]:
            record = resp.json()
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
    
    import datetime
    now_str = data.get("ended_at") or datetime.datetime.utcnow().isoformat() + "Z"
    status = data.get("status") or "completed"
    
    ticks = []
    started_at_str = None
    try:
        route_resp = requests.get(f"{pb_url}/api/collections/navigation_routes/records/{route_id}", timeout=5)
        if route_resp.status_code == 200:
            route_record = route_resp.json()
            started_at_str = route_record.get("started_at")
        
        ticks_resp = requests.get(f"{pb_url}/api/collections/navigation_ticks/records?filter=route='{route_id}'&sort=timestamp&limit=5000", timeout=5)
        if ticks_resp.status_code == 200:
            ticks = ticks_resp.json().get("items", [])
    except Exception as e:
        print(f"Error fetching ticks for calculations: {e}")
    
    actual_distance = 0.0
    if len(ticks) >= 2:
        for i in range(len(ticks) - 1):
            pt1 = (ticks[i].get("lat"), ticks[i].get("lon"))
            pt2 = (ticks[i+1].get("lat"), ticks[i+1].get("lon"))
            if pt1[0] is not None and pt1[1] is not None and pt2[0] is not None and pt2[1] is not None:
                actual_distance += haversine_distance(pt1, pt2)
    
    actual_duration = 0.0
    
    def parse_pb_date(d_str):
        if not d_str: return None
        d_str = d_str.replace("Z", "")
        if "." in d_str:
            d_str = d_str.split(".")[0]
        return datetime.datetime.fromisoformat(d_str)

    if started_at_str:
        try:
            t_start = parse_pb_date(started_at_str)
            t_end = parse_pb_date(now_str)
            if t_start and t_end:
                actual_duration = (t_end - t_start).total_seconds()
        except Exception as e:
            print(f"Error parsing dates: {e}")
            
    if actual_duration <= 0 and len(ticks) >= 2:
        try:
            t_start = parse_pb_date(ticks[0].get("timestamp"))
            t_end = parse_pb_date(ticks[-1].get("timestamp"))
            if t_start and t_end:
                actual_duration = (t_end - t_start).total_seconds()
        except:
            pass
    
    if actual_duration <= 0:
        actual_duration = 0.0
        
    average_speed = actual_distance / actual_duration if actual_duration > 0 else 0.0
    
    pb_update = {
        "status": status,
        "ended_at": now_str,
        "ended_lat": data.get("ended_lat"),
        "ended_lon": data.get("ended_lon"),
        "actual_distance_meters": actual_distance,
        "actual_duration_seconds": actual_duration,
        "average_speed": average_speed
    }
    
    try:
        resp = requests.patch(f"{pb_url}/api/collections/navigation_routes/records/{route_id}", json=pb_update, timeout=5)
        if resp.status_code == 200:
            return jsonify({
                "status": "success",
                "actual_distance_meters": actual_distance,
                "actual_duration_seconds": actual_duration,
                "average_speed": average_speed
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
    
    if user_id:
        url = f"{pb_url}/api/collections/navigation_routes/records?filter=user='{user_id}'&sort=-started_at&limit=50"
    else:
        route_ids_str = request.args.get("route_ids")
        if route_ids_str:
            route_ids = [rid.strip() for rid in route_ids_str.split(",") if rid.strip()]
            if not route_ids:
                return jsonify([])
            filter_query = "||".join([f"id='{rid}'" for rid in route_ids])
            url = f"{pb_url}/api/collections/navigation_routes/records?filter=({filter_query})&sort=-started_at&limit=50"
        else:
            return jsonify([])
            
    try:
        resp = requests.get(url, timeout=5)
        if resp.status_code == 200:
            items = resp.json().get("items", [])
            return jsonify(items)
        else:
            return jsonify({"error": f"PocketBase returned {resp.status_code}: {resp.text}"}), resp.status_code
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route("/api/navigation/<route_id>", methods=["GET"])
def nav_detail(route_id):
    pb_url = os.environ.get("POCKETBASE_URL", "http://127.0.0.1:8090")
    
    try:
        route_resp = requests.get(f"{pb_url}/api/collections/navigation_routes/records/{route_id}", timeout=5)
        if route_resp.status_code != 200:
            return jsonify({"error": "Route not found"}), 404
        route = route_resp.json()
        
        ticks_resp = requests.get(f"{pb_url}/api/collections/navigation_ticks/records?filter=route='{route_id}'&sort=timestamp&limit=5000", timeout=5)
        ticks = []
        if ticks_resp.status_code == 200:
            ticks = ticks_resp.json().get("items", [])
            
        route["ticks"] = ticks
        return jsonify(route)
    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == "__main__":
    # Pre-build graph on startup
    build_graph()
    
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

    app.run(host="0.0.0.0", port=3001, debug=True)

