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

nodes_dict = {}
for el in data.get("elements", []):
    if el.get("type") == "node":
        nodes_dict[el["id"]] = el

cedar_ways = [17026283, 17026284, 473451129]

for wid in cedar_ways:
    for el in data.get("elements", []):
        if el.get("type") == "way" and el["id"] == wid:
            print(f"\nWay {wid}: Name={el.get('tags', {}).get('name')}")
            for nid in el["nodes"]:
                if nid in nodes_dict:
                    node = nodes_dict[nid]
                    dist = haversine_distance(target, (node["lat"], node["lon"]))
                    print(f"  Node {nid}: lat={node['lat']:.6f}, lon={node['lon']:.6f}, dist_to_target={dist:.1f}m")
