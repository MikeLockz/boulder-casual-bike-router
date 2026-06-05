import json
import math

CACHE_FILE = "backend/boulder_osm_data.json"

def haversine_distance(coord1, coord2):
    lat1, lon1 = coord1
    lat2, lon2 = coord2
    R = 6371000  # meters
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    delta_phi = math.radians(lat2 - lat1)
    delta_lambda = math.radians(lon2 - lon1)
    a = math.sin(delta_phi/2)**2 + math.cos(phi1) * math.cos(phi2) * math.sin(delta_lambda/2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
    return R * c

target = (40.0284974952006, -105.28202961430686)

with open(CACHE_FILE) as f:
    data = json.load(f)

print(f"Searching for nodes/ways within 100 meters of {target} with crossing/footway/sidewalk properties...")

close_nodes = []
close_ways = []

for el in data.get("elements", []):
    if el.get("type") == "node":
        lat, lon = el["lat"], el["lon"]
        dist = haversine_distance(target, (lat, lon))
        if dist <= 100:
            close_nodes.append((dist, el))
    elif el.get("type") == "way":
        # Check if way has nodes close to target
        # We don't have node geometries inline, but we can look up afterwards.
        pass

# Index nodes by ID
nodes_dict = {}
for el in data.get("elements", []):
    if el.get("type") == "node":
        nodes_dict[el["id"]] = el

for el in data.get("elements", []):
    if el.get("type") == "way":
        nodes_in_way = el.get("nodes", [])
        is_close = False
        for nid in nodes_in_way:
            if nid in nodes_dict:
                node = nodes_dict[nid]
                dist = haversine_distance(target, (node["lat"], node["lon"]))
                if dist <= 100:
                    is_close = True
                    break
        if is_close:
            close_ways.append(el)

print(f"\n--- Close Nodes (within 100m) with tags: ---")
for dist, node in sorted(close_nodes, key=lambda x: x[0]):
    tags = node.get("tags", {})
    if tags:
        print(f"Node {node['id']}: dist={dist:.1f}m, lat={node['lat']:.6f}, lon={node['lon']:.6f}, tags={tags}")

print(f"\n--- Close Ways (within 100m): ---")
for way in close_ways:
    tags = way.get("tags", {})
    name = tags.get("name", "Unnamed")
    hw = tags.get("highway", "")
    # Check if way is crossing or footway
    if "crossing" in str(tags) or hw in ["footway", "pedestrian", "cycleway", "path"] or "sidewalk" in tags:
        print(f"Way {way['id']}: Name={name}, Highway={hw}, Tags={tags}")
        print(f"  Nodes: {way['nodes']}")
