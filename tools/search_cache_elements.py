import json

CACHE_FILE = "backend/boulder_osm_data.json"

with open(CACHE_FILE) as f:
    data = json.load(f)

print("Searching for ways named 'Cedar' or 'North Boulder Park' in cached data...")
for el in data.get("elements", []):
    if el.get("type") == "way":
        tags = el.get("tags", {})
        name = tags.get("name", "")
        if "Cedar" in name or "North Boulder" in name:
            print(f"Way {el['id']}: Name={name}, Highway={tags.get('highway')}, Tags={tags}")
