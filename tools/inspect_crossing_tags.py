import json
import os
from collections import Counter

CACHE_FILE = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "backend", "boulder_osm_data.json"))

with open(CACHE_FILE) as f:
    data = json.load(f)

crossing_highway_types = Counter()
crossing_crossing_types = Counter()
crossing_signals = Counter()
traffic_signals_nodes = 0
all_crossing_nodes = 0

for el in data.get("elements", []):
    if el.get("type") == "node":
        tags = el.get("tags", {})
        highway = tags.get("highway")
        crossing = tags.get("crossing")
        
        if highway == "crossing":
            all_crossing_nodes += 1
            crossing_crossing_types[crossing] += 1
            for k, v in tags.items():
                if "signal" in k or "light" in k:
                    crossing_signals[f"{k}={v}"] += 1
        elif highway == "traffic_signals":
            traffic_signals_nodes += 1

print(f"Total crossing nodes (highway=crossing): {all_crossing_nodes}")
print(f"Total traffic signal nodes (highway=traffic_signals): {traffic_signals_nodes}")

print("\nTop 'crossing' tag values on highway=crossing nodes:")
for k, v in crossing_crossing_types.most_common(15):
    print(f"  {k}: {v}")

print("\nTop signal/light-related tags on highway=crossing nodes:")
for k, v in crossing_signals.most_common(15):
    print(f"  {k}: {v}")
