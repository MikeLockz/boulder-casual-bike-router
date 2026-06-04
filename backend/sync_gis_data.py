import os
import urllib.request
import json

DATASETS = {
    "boulder_bike_stress_data.json": "https://opendata.arcgis.com/datasets/e20bc9b72c3b4d0fac167d722a7cf1b7_0.geojson",
    "boulder_bike_offstreet_data.json": "https://opendata.arcgis.com/datasets/8cae0bbbd3154abe8264fa349b8f245f_0.geojson",
    "boulder_playground_data.json": "https://opendata.arcgis.com/datasets/b1297c2328b343528f70dfd78c6de459_1.geojson"
}

def sync():
    backend_dir = os.path.dirname(os.path.abspath(__file__))
    print(f"Syncing GIS datasets to {backend_dir}...")
    
    for filename, url in DATASETS.items():
        dest_path = os.path.join(backend_dir, filename)
        print(f"\nDownloading {filename} from {url}...")
        try:
            req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
            with urllib.request.urlopen(req) as response:
                data = json.loads(response.read().decode('utf-8'))
            
            with open(dest_path, "w") as f:
                json.dump(data, f)
            print(f"✓ Saved {filename} ({len(data.get('features', []))} features)")
        except Exception as e:
            print(f"✗ Failed to download {filename}: {e}")

if __name__ == "__main__":
    sync()
