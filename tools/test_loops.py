import requests
import json

API_URL = "http://localhost:3001/api/route"

def test_loop(name, start, end, waypoints):
    print(f"\n==========================================")
    print(f"Testing Loop: {name}")
    print(f"==========================================")
    payload = {
        "start_lat": start[0],
        "start_lon": start[1],
        "end_lat": end[0],
        "end_lon": end[1],
        "waypoints": waypoints
    }
    
    try:
        response = requests.post(API_URL, json=payload)
        response.raise_for_status()
        data = response.json()
        
        print("Success! Loop calculated successfully.")
        print(f"  Total Length: {data['total_length_meters']/1609.34:.2f} miles ({data['total_length_meters']:.1f} meters)")
        print(f"  Total Cost Weight: {data['total_weight']:.2f}")
        print(f"  Segments Count: {len(data['segments'])}")
        
        # Breakdown by infrastructure type
        type_lengths = {}
        for seg in data["segments"]:
            t = seg["type"]
            type_lengths[t] = type_lengths.get(t, 0) + seg["length"]
            
        print("  Composition by infrastructure type:")
        for t, length in sorted(type_lengths.items(), key=lambda x: x[1], reverse=True):
            print(f"    - {t}: {length/1609.34:.2f} mi ({length:.1f} meters)")
            
    except Exception as e:
        print(f"Failed: {e}")
        if 'response' in locals() and response is not None:
            print("Response:", response.text)

if __name__ == "__main__":
    # Boulder B-180 Loop Preset
    # Start/End: Valmont Bike Park [40.030, -105.234]
    # Waypoints:
    #   WP1: [40.040, -105.265] (North-Central)
    #   WP2: [40.015, -105.292] (West)
    #   WP3: [39.998, -105.263] (South/Campus)
    test_loop(
        name="Boulder B-180 (12-mile Loop)",
        start=(40.030, -105.234),
        end=(40.030, -105.234),
        waypoints=[
            [40.040, -105.265],
            [40.015, -105.292],
            [39.998, -105.263]
        ]
    )
    
    # Boulder B-360 Loop Preset
    # Start/End: Valmont Bike Park [40.030, -105.234]
    # Waypoints:
    #   WP1: [40.060, -105.275] (Far North/Wonderland)
    #   WP2: [39.998, -105.283] (Far West/Chautauqua)
    #   WP3: [39.970, -105.245] (Far South/Marshall)
    #   WP4: [40.045, -105.210] (Far East/Gunbarrel)
    test_loop(
        name="Boulder B-360 (24-mile Loop)",
        start=(40.030, -105.234),
        end=(40.030, -105.234),
        waypoints=[
            [40.060, -105.275],
            [39.998, -105.283],
            [39.970, -105.245],
            [40.045, -105.210]
        ]
    )
