import os
import sys
import json

# Add project root to python path
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from backend.app import app, build_graph

def test_inspect_edge():
    print("Building routing graph...")
    build_graph()
    
    from backend.app import G_connected
    
    # 1. Verify edges have way_id and tags
    edges_with_tags = 0
    total_edges = 0
    for u, v, d in G_connected.edges(data=True):
        total_edges += 1
        if "way_id" in d and "tags" in d:
            edges_with_tags += 1
            
    print(f"Graph check: total edges = {total_edges}, edges with tags/way_id = {edges_with_tags}")
    assert edges_with_tags > 0, "No edges have way_id and tags saved!"
    
    # 2. Test the API endpoint using Flask's test client
    print("\nTesting /api/inspect-edge API endpoint...")
    client = app.test_client()
    
    # Coordinates for a point on 13th St (near Canyon/Arapahoe)
    lat, lon = 40.0156, -105.2762
    
    response = client.get(f"/api/inspect-edge?lat={lat}&lon={lon}")
    print(f"Status Code: {response.status_code}")
    assert response.status_code == 200, "API returned non-200 status!"
    
    data = json.loads(response.data)
    print("\nAPI Response JSON structure:")
    print(json.dumps(data, indent=2))
    
    assert "name" in data
    assert "type" in data
    assert "multiplier" in data
    assert "bikestress" in data
    assert "offstreet_type" in data
    assert "tags" in data
    assert "way_id" in data
    assert "coords" in data
    
    print("\nVerification successful! All checks passed.")

if __name__ == "__main__":
    test_inspect_edge()
