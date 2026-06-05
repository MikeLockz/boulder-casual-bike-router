import urllib.request
import json
import os

url = "https://opendata.arcgis.com/datasets/b1297c2328b343528f70dfd78c6de459_1.geojson"
output_file = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "backend", "playgrounds_raw.geojson"))

try:
    print(f"Fetching from {url}...")
    with urllib.request.urlopen(url) as response:
        data = json.loads(response.read().decode('utf-8'))
    
    print(f"Successfully fetched GeoJSON! Type: {data.get('type')}")
    features = data.get('features', [])
    print(f"Number of features: {len(features)}")
    if features:
        first_feature = features[0]
        print("First feature properties keys:", list(first_feature.get('properties', {}).keys()))
        print("First feature properties:", json.dumps(first_feature.get('properties', {}), indent=2))
        print("First feature geometry type:", first_feature.get('geometry', {}).get('type'))
        
    with open(output_file, 'w') as f:
        json.dump(data, f, indent=2)
    print(f"Saved raw GeoJSON to {output_file}")
except Exception as e:
    print("Error:", e)
