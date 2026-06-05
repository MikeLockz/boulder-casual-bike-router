import json

CACHE_FILE = "backend/boulder_osm_data.json"

with open(CACHE_FILE) as f:
    data = json.load(f)

highway_counts = {}
for el in data.get("elements", []):
    if el.get("type") == "way":
        tags = el.get("tags", {})
        hw = tags.get("highway", "none")
        highway_counts[hw] = highway_counts.get(hw, 0) + 1

print("Highway type counts in cached data:")
for hw, count in sorted(highway_counts.items(), key=lambda x: x[1], reverse=True):
    print(f"  {hw}: {count}")
