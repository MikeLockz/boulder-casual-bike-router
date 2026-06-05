import urllib.request
import json
import os
from collections import Counter

url = "https://opendata.arcgis.com/datasets/8cae0bbbd3154abe8264fa349b8f245f_0.geojson"
out_path = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "backend", "boulder_bike_offstreet_data.json"))

try:
    print(f"Fetching from {url}...")
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    with urllib.request.urlopen(req) as response:
        data = json.loads(response.read().decode('utf-8'))
        
    print(f"Successfully fetched GeoJSON! Type: {data.get('type')}")
    features = data.get('features', [])
    print(f"Number of features: {len(features)}")
    
    if features:
        print("\nKeys present in a feature:")
        print("keys:", list(features[0].keys()))
        print("properties keys:", list(features[0].get('properties', {}).keys()))
        print("geometry type:", features[0].get('geometry', {}).get('type'))
        
        # Count values for relevant properties
        facility_types = Counter()
        bicycles_vals = Counter()
        ebike_vals = Counter()
        
        for f in features:
            props = f.get('properties', {})
            # Handle capitalization
            facility_type = props.get('FACILITYTYPE')
            bicycles = props.get('BICYCLES')
            ebike = props.get('EBIKE')
            
            facility_types[facility_type] += 1
            bicycles_vals[bicycles] += 1
            ebike_vals[ebike] += 1
            
        print("\nFACILITYTYPE counts:")
        for k, v in facility_types.most_common():
            print(f"  {k}: {v}")
            
        print("\nBICYCLES counts:")
        for k, v in bicycles_vals.most_common():
            print(f"  {k}: {v}")
            
        print("\nEBIKE counts:")
        for k, v in ebike_vals.most_common():
            print(f"  {k}: {v}")
            
        # Save full data
        with open(out_path, "w") as f:
            json.dump(data, f)
        print(f"Saved full GeoJSON to {out_path}")
        
except Exception as e:
    print("Error:", e)
