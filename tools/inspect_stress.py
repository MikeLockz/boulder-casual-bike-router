import json
from collections import Counter

# Read sample or full? Let's download the full GeoJSON in a script and inspect it.
url = "https://opendata.arcgis.com/datasets/e20bc9b72c3b4d0fac167d722a7cf1b7_0.geojson"

import urllib.request
req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
with urllib.request.urlopen(req) as response:
    data = json.loads(response.read().decode('utf-8'))

features = data.get('features', [])
print(f"Total features: {len(features)}")

# Let's count unique values of BIKESTRESS
bikestress_counts = Counter()
pedstress_counts = Counter()
facility_types = Counter()

for f in features:
    props = f.get('properties', {})
    bikestress_counts[props.get('BIKESTRESS')] += 1
    pedstress_counts[props.get('PEDSTRESS')] += 1
    facility_types[props.get('FACILITYTYPE')] += 1

print("\nBIKESTRESS values:")
for val, count in bikestress_counts.most_common():
    print(f"  {val}: {count}")

print("\nPEDSTRESS values:")
for val, count in pedstress_counts.most_common():
    print(f"  {val}: {count}")

print("\nFACILITYTYPE values:")
for val, count in facility_types.most_common():
    print(f"  {val}: {count}")
