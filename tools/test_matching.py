import os
import json
import math
from collections import Counter

# Bounding box for Boulder, CO: [South, West, North, East]
BOULDER_BBOX = (39.96, -105.30, 40.09, -105.18)
OSM_FILE = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "backend", "boulder_osm_data.json"))
STRESS_FILE = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "backend", "boulder_bike_stress_data.json"))

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
        min_lat, max_lat = min(lat1, lat2), max(lat1, lat2)
        min_lon, max_lon = min(lon1, lon2), max(lon1, lon2)
        
        start_cell_x, start_cell_y = self._get_cell(min_lat, min_lon)
        end_cell_x, end_cell_y = self._get_cell(max_lat, max_lon)
        
        segment_data = (lat1, lon1, lat2, lon2, feature_idx, properties)
        
        for x in range(start_cell_x - 1, end_cell_x + 2):
            for y in range(start_cell_y - 1, end_cell_y + 2):
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
        
        for lat1, lon1, lat2, lon2, feat_idx, props in candidates:
            seg_key = (lat1, lon1, lat2, lon2, feat_idx)
            if seg_key in checked_segments:
                continue
            checked_segments.add(seg_key)
            
            # Check bearing first
            gis_bearing = get_segment_bearing(lat1, lon1, lat2, lon2)
            if bearing_difference_undirected(osm_bearing, gis_bearing) > bearing_tolerance:
                continue
                
            dist = point_to_segment_distance((lat, lon), (lat1, lon1), (lat2, lon2))
            if dist < min_dist:
                min_dist = dist
                best_candidate = (props, dist)
                
        if min_dist <= max_dist_meters:
            return best_candidate
        return None

def test():
    print("Loading datasets...")
    with open(OSM_FILE) as f:
        osm_data = json.load(f)
    with open(STRESS_FILE) as f:
        stress_data = json.load(f)
        
    print("Parsing GIS stress data and populating spatial index...")
    spatial_index = SpatialGridIndex(cell_size=0.001)
    
    for idx, feature in enumerate(stress_data.get("features", [])):
        geom = feature.get("geometry", {})
        props = feature.get("properties", {})
        if geom.get("type") == "LineString":
            coords = geom.get("coordinates", [])
            # Add each segment of the GIS LineString to the spatial index
            for i in range(len(coords) - 1):
                lon1, lat1 = coords[i]
                lon2, lat2 = coords[i+1]
                spatial_index.add_segment(lat1, lon1, lat2, lon2, idx, props)
                
    # Now load OSM nodes and ways
    nodes = {}
    for element in osm_data.get("elements", []):
        if element.get("type") == "node":
            nodes[element["id"]] = (element["lat"], element["lon"])
            
    print(f"Loaded {len(nodes)} OSM nodes.")
    
    matched_counts = Counter()
    unmatched_count = 0
    total_edges = 0
    
    sample_matches = []
    
    for element in osm_data.get("elements", []):
        if element.get("type") == "way":
            way_nodes = element.get("nodes", [])
            way_name = element.get("tags", {}).get("name", "Unnamed")
            highway = element.get("tags", {}).get("highway", "")
            if not highway or highway in ["motorway", "motorway_link", "trunk", "trunk_link"]:
                continue
                
            for i in range(len(way_nodes) - 1):
                u = way_nodes[i]
                v = way_nodes[i+1]
                if u in nodes and v in nodes:
                    total_edges += 1
                    lat_u, lon_u = nodes[u]
                    lat_v, lon_v = nodes[v]
                    
                    midpoint = ((lat_u + lat_v) / 2.0, (lon_u + lon_v) / 2.0)
                    osm_bearing = get_segment_bearing(lat_u, lon_u, lat_v, lon_v)
                    
                    match = spatial_index.query_nearest_with_bearing(
                        midpoint[0], midpoint[1], osm_bearing, 
                        max_dist_meters=15.0, bearing_tolerance=30.0
                    )
                    
                    if match:
                        props, dist = match
                        stress = props.get("BIKESTRESS", "None")
                        matched_counts[stress] += 1
                        
                        if len(sample_matches) < 5:
                            sample_matches.append({
                                "osm_way_name": way_name,
                                "highway": highway,
                                "gis_street_name": props.get("STREETNAME"),
                                "gis_facility_type": props.get("FACILITYTYPE"),
                                "bikestress": stress,
                                "dist_meters": dist
                            })
                    else:
                        unmatched_count += 1
                        
    print(f"\nMatching Results (Total OSM segments checked: {total_edges}):")
    print(f"  Matched Low Stress: {matched_counts['Low']}")
    print(f"  Matched High Stress: {matched_counts['High']}")
    print(f"  Matched None Stress: {matched_counts['None']}")
    print(f"  Unmatched: {unmatched_count}")
    print(f"  Match Rate: {((total_edges - unmatched_count) / total_edges) * 100:.1f}%")
    
    print("\nSample Matches:")
    for sm in sample_matches:
        print(json.dumps(sm, indent=2))

if __name__ == "__main__":
    test()
