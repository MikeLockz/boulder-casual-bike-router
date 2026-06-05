import json

CACHE_FILE = "backend/boulder_osm_data.json"

with open(CACHE_FILE) as f:
    data = json.load(f)

nodes_dict = {}
for el in data.get("elements", []):
    if el.get("type") == "node":
        nodes_dict[el["id"]] = el

print("Searching for ALL ways inside North Boulder Park area...")
park_ways = []
for el in data.get("elements", []):
    if el.get("type") == "way":
        nodes_in_way = el.get("nodes", [])
        in_park = False
        for nid in nodes_in_way:
            if nid in nodes_dict:
                node = nodes_dict[nid]
                lat, lon = node["lat"], node["lon"]
                if 40.0260 <= lat <= 40.0305 and -105.2865 <= lon <= -105.2820:
                    in_park = True
                    break
        if in_park:
            park_ways.append(el)

print(f"Found {len(park_ways)} ways in the park area:")
for way in park_ways:
    tags = way.get("tags", {})
    print(f"  Way {way['id']}: Name={tags.get('name', 'Unnamed')}, Highway={tags.get('highway')}, Tags={tags}")
