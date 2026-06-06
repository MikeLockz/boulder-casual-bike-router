import requests
import json
import time

BASE_URL = "http://localhost:8081/api"  # Curl through Nginx to test proxy mapping too

def test_navigation_flow():
    print("=== Testing Start Navigation ===")
    start_payload = {
        "start_lat": 40.015,
        "start_lon": -105.27,
        "end_lat": 40.02,
        "end_lon": -105.26,
        "start_point_name": "Boulder Downtown",
        "end_point_name": "Boulder Junction",
        "route_geojson": {
            "type": "Feature",
            "geometry": {
                "type": "LineString",
                "coordinates": [
                    [-105.27, 40.015],
                    [-105.265, 40.018],
                    [-105.26, 40.02]
                ]
            },
            "properties": {}
        },
        "total_length_meters": 1200.0,
        "total_estimated_time_seconds": 300,
        "device_type": "tester",
        "weights": {"quietness": 0.5}
    }
    
    start_resp = requests.post(f"{BASE_URL}/navigation/start", json=start_payload)
    print(f"Status Code: {start_resp.status_code}")
    print(f"Response: {start_resp.text}")
    assert start_resp.status_code == 201, "Start navigation failed"
    start_data = start_resp.json()
    route_id = start_data["route_id"]
    print(f"Route ID: {route_id}")

    print("\n=== Testing Send Ticks ===")
    ticks = [
        {"lat": 40.0151, "lon": -105.2699, "speed": 4.5, "direction": 45, "accuracy": 5, "altitude": 1630, "battery_level": 85},
        {"lat": 40.0179, "lon": -105.2651, "speed": 4.8, "direction": 50, "accuracy": 4, "altitude": 1632, "battery_level": 84},
        {"lat": 40.0199, "lon": -105.2601, "speed": 4.2, "direction": 40, "accuracy": 6, "altitude": 1635, "battery_level": 83}
    ]
    
    for i, tick_payload in enumerate(ticks):
        print(f"Sending tick {i+1}...")
        tick_resp = requests.post(f"{BASE_URL}/navigation/{route_id}/tick", json=tick_payload)
        print(f"Status Code: {tick_resp.status_code}")
        print(f"Response: {tick_resp.text}")
        assert tick_resp.status_code == 201, "Tick insert failed"

    print("\n=== Testing End Navigation ===")
    end_payload = {
        "ended_lat": 40.0201,
        "ended_lon": -105.2599,
        "status": "completed"
    }
    end_resp = requests.post(f"{BASE_URL}/navigation/{route_id}/end", json=end_payload)
    print(f"Status Code: {end_resp.status_code}")
    print(f"Response: {end_resp.text}")
    assert end_resp.status_code == 200, "End navigation failed"
    end_data = end_resp.json()
    print(f"Calculated distance: {end_data.get('actual_distance_meters')} meters")
    print(f"Calculated duration: {end_data.get('actual_duration_seconds')} seconds")
    print(f"Average speed: {end_data.get('average_speed')} m/s")

    print("\n=== Testing Get Navigation Details ===")
    detail_resp = requests.get(f"{BASE_URL}/navigation/{route_id}")
    print(f"Status Code: {detail_resp.status_code}")
    # print first 500 chars of detail response
    print(f"Response (truncated): {detail_resp.text[:500]}...")
    assert detail_resp.status_code == 200, "Get detail failed"
    detail_data = detail_resp.json()
    assert len(detail_data.get("ticks", [])) == 3, "Ticks count mismatch"

    print("\n=== Testing Get History ===")
    history_resp = requests.get(f"{BASE_URL}/navigation/history?route_ids={route_id}")
    print(f"Status Code: {history_resp.status_code}")
    print(f"Response: {history_resp.text}")
    assert history_resp.status_code == 200, "Get history failed"
    history_data = history_resp.json()
    assert len(history_data) >= 1, "History empty"
    assert history_data[0]["id"] == route_id, "Route ID mismatch in history"

    print("\n[+] ALL API ENDPOINT TESTS PASSED SUCCESSFULLY!")

if __name__ == "__main__":
    test_navigation_flow()
