import urllib.request
import json

url = "https://opendata.arcgis.com/datasets/e20bc9b72c3b4d0fac167d722a7cf1b7_0.geojson"

try:
    print(f"Fetching from {url}...")
    req = urllib.request.Request(
        url, 
        headers={'User-Agent': 'Mozilla/5.0'}
    )
    with urllib.request.urlopen(req) as response:
        data = json.loads(response.read().decode('utf-8'))
    
    print(f"Successfully fetched GeoJSON! Type: {data.get('type')}")
    features = data.get('features', [])
    print(f"Number of features: {len(features)}")
    
    if features:
        print("Keys present in a feature:")
        print("keys:", list(features[0].keys()))
        print("properties keys:", list(features[0].get('properties', {}).keys()))
        print("geometry type:", features[0].get('geometry', {}).get('type'))
        
        # Let's count unique values of bikestress and other relevant properties
        stress_values = set()
        for f in features:
            stress = f.get('properties', {}).get('bikestress')
            if stress:
                stress_values.add(stress)
        print("Unique bikestress values found in dataset:", stress_values)
        
        # Print a sample feature
        print("\nSample feature properties:")
        print(json.dumps(features[0].get('properties', {}), indent=2))
        
        # Write the full GeoJSON
        import os
        out_path = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "backend", "boulder_bike_stress_data.json"))
        with open(out_path, "w") as out:
            json.dump(data, out)
        print(f"Saved full GeoJSON to {out_path}")
            
except Exception as e:
    print("Error:", e)
