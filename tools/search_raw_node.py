import json

CACHE_FILE = "backend/boulder_osm_data.json"
node_id = 3338097013

with open(CACHE_FILE) as f:
    data = json.load(f)

for el in data.get("elements", []):
    if el.get("type") == "node" and el["id"] == node_id:
        print(f"Found node {node_id} in JSON:")
        print(json.dumps(el, indent=2))
