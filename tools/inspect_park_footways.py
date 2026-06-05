import json
import math

CACHE_FILE = "backend/boulder_osm_data.json"

with open(CACHE_FILE) as f:
    data = json.load(f)

nodes_dict = {}
for el in data.get("elements", []):
    if el.get("type") == "node":
        nodes_dict[el["id"]] = el

park_footway_ids = [34417992, 34417993, 34417994, 34417996]

for fid in park_footway_ids:
    for el in data.get("elements", []):
        if el.get("type") == "way" and el["id"] == fid:
            print(f"\nWay {fid}: Tags={el.get('tags')}")
            for nid in el["nodes"]:
                if nid in nodes_dict:
                    node = nodes_dict[nid]
                    print(f"  Node {nid}: lat={node['lat']:.6f}, lon={node['lon']:.6f}")
                else:
                    print(f"  Node {nid}: NOT FOUND")
                    
# Let's see which other ways contain any of these nodes
all_nodes = []
for fid in park_footway_ids:
    for el in data.get("elements", []):
        if el.get("type") == "way" and el["id"] == fid:
            all_nodes.extend(el["nodes"])
            
all_nodes = set(all_nodes)
print("\nChecking which other ways share nodes with these park footways:")
for el in data.get("elements", []):
    if el.get("type") == "way" and el["id"] not in park_footway_ids:
        nodes_in_way = el.get("nodes", [])
        overlap = all_nodes.intersection(nodes_in_way)
        if overlap:
            print(f"  Way {el['id']} ({el.get('tags', {}).get('name', 'Unnamed')}, {el.get('tags', {}).get('highway')}) shares nodes {list(overlap)}")
