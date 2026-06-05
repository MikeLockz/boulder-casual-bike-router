import json
import math
import os

CACHE_FILE = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "backend", "boulder_osm_data.json"))
TARGET_COORDS = (40.0363519821661, -105.26798529931916)

def haversine_distance(coord1, coord2):
    lat1, lon1 = coord1
    lat2, lon2 = coord2
    R = 6371000
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    delta_phi = math.radians(lat2 - lat1)
    delta_lambda = math.radians(lon2 - lon1)
    a = math.sin(delta_phi/2)**2 + math.cos(phi1) * math.cos(phi2) * math.sin(delta_lambda/2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
    return R * c

with open(CACHE_FILE) as f:
    data = json.load(f)

# Find all nodes within 100 meters
nodes_near = []
for el in data.get("elements", []):
    if el.get("type") == "node":
        dist = haversine_distance(TARGET_COORDS, (el["lat"], el["lon"]))
        if dist < 100.0:
            nodes_near.append((el["id"], el["lat"], el["lon"], dist, el.get("tags", {})))

nodes_near.sort(key=lambda x: x[3])

print("=== NODES WITHIN 100M ===")
node_ids = set()
for nid, lat, lon, dist, tags in nodes_near[:20]:
    node_ids.add(nid)
    print(f"Node {nid}: dist={dist:.2f}m, coords=({lat}, {lon}), tags={tags}")

print("\n=== WAYS CONTAINING THESE NODES ===")
for el in data.get("elements", []):
    if el.get("type") == "way":
        way_nodes = el.get("nodes", [])
        shared_nodes = [nid for nid in way_nodes if nid in node_ids]
        if shared_nodes:
            print(f"Way {el.get('id')} ({el.get('tags', {}).get('name', 'unnamed')}, highway={el.get('tags', {}).get('highway')}): tags={el.get('tags')}")
            print(f"  Shared nodes: {shared_nodes}")
            print(f"  All nodes in way: {way_nodes}")
