import json
import requests

API_URL = "http://localhost:3001/api/route"

def run_test(weights=None, description=""):
    print(f"\n--- {description} ---")
    payload = {
        "start_lat": 40.028446,
        "start_lon": -105.281088,
        "end_lat": 40.0280,
        "end_lon": -105.2831
    }
    if weights:
        payload["weights"] = weights
        
    try:
        response = requests.post(API_URL, json=payload)
        response.raise_for_status()
        data = response.json()
        
        print(f"Success! Path calculated.")
        print(f"Total Distance: {data['total_length_meters']:.2f} meters")
        print(f"Total Weight Cost: {data['total_weight']:.2f}")
        
        # Display route segments
        for idx, seg in enumerate(data["segments"]):
            print(f"  [{idx}] {seg['name']} ({seg['type']}): {seg['length']:.1f}m (mult {seg['multiplier']}x)")
            
    except Exception as e:
        print(f"Failed: {e}")

if __name__ == "__main__":
    # Test 1: Default Weights (should detour)
    run_test(description="Default Weights (Expecting Detour to Safe Crosswalk)")
    
    # Test 2: Unsafe Crossing multiplier = 1.0 (should cross directly)
    custom_weights = {
        "separated_path": 0.5,
        "sharrow_minor": 1.5,
        "sidewalk": 2.0,
        "residential": 1.0,
        "busy_with_lane": 5.0,
        "busy_with_sharrow": 8.0,
        "busy_undesignated": 15.0,
        "sidewalk_forced": 6.0,
        "crossing_safe": 1.0,
        "crossing_unsafe": 1.0
    }
    run_test(weights=custom_weights, description="Unsafe Crossing Multiplier = 1.0x (Expecting Direct Unsafe Crossing)")
