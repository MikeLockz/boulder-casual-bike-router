import json

CACHE_FILE = "backend/boulder_osm_data.json"

with open(CACHE_FILE) as f:
    data = json.load(f)

min_lat, max_lat = 90, -90
min_lon, max_lon = 180, -180

nodes_count = 0
ways_count = 0

for el in data.get("elements", []):
    if el.get("type") == "node":
        nodes_count += 1
        lat, lon = el["lat"], el["lon"]
        if lat < min_lat: min_lat = lat
        if lat > max_lat: max_lat = lat
        if lon < min_lon: min_lon = lon
        if lon > max_lon: max_lon = lon
    elif el.get("type") == "way":
        ways_count += 1

print(f"Cache summary:")
print(f"  Nodes count: {nodes_count}")
print(f"  Ways count: {ways_count}")
print(f"  Lat range: {min_lat} to {max_lat}")
print(f"  Lon range: {min_lon} to {max_lon}")
