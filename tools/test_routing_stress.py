import os
import sys
import networkx as nx

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from backend.app import build_graph, find_nearest_node, DEFAULT_WEIGHTS

def test_routing():
    print("Building the graph with bike stress and off-street data...")
    # This will load OSM, GIS stress data, GIS off-street data, snap edges, and build graph
    build_graph()
    
    from backend.app import G_connected
    
    # Check that some edges have bikestress and off-street attributes
    low_stress_edges = []
    high_stress_edges = []
    multiuse_edges = []
    no_bike_edges = []
    no_ebike_edges = []
    
    for u, v, d in G_connected.edges(data=True):
        stress = d.get("bikestress", "None")
        if stress == "Low":
            low_stress_edges.append((u, v, d))
        elif stress == "High":
            high_stress_edges.append((u, v, d))
            
        offstreet = d.get("offstreet_type", "None")
        if offstreet == "Multi-Use Path":
            multiuse_edges.append((u, v, d))
            
        if d.get("bicycles_allowed") == "No":
            no_bike_edges.append((u, v, d))
            
        if d.get("ebike_allowed") == "No":
            no_ebike_edges.append((u, v, d))
            
    print(f"Total edges in G_connected: {G_connected.number_of_edges()}")
    print(f"  Low stress edges: {len(low_stress_edges)}")
    print(f"  High stress edges: {len(high_stress_edges)}")
    print(f"  Multi-Use Path edges: {len(multiuse_edges)}")
    print(f"  Bicycles Prohibited edges: {len(no_bike_edges)}")
    print(f"  E-Bikes Prohibited edges: {len(no_ebike_edges)}")
    
    assert len(low_stress_edges) > 0, "No low-stress edges matched!"
    assert len(high_stress_edges) > 0, "No high-stress edges matched!"
    assert len(multiuse_edges) > 0, "No multi-use path edges matched!"
    assert len(no_ebike_edges) > 0, "No e-bike prohibited edges matched!"
    
    # Preset coordinates (North Boulder to Iris Ave)
    start_coord = (40.028446, -105.281088)
    end_coord = (40.03866227818636, -105.26385171093987)
    
    start_node, _ = find_nearest_node(start_coord)
    end_node, _ = find_nearest_node(end_coord)
    
    print(f"Routing from {start_node} to {end_node}...")
    
    # Helper to calculate weights with customizable settings
    def get_route_with_custom_weights(stress_low, stress_high, offstreet_multiuse, ebike_restricted):
        weights = DEFAULT_WEIGHTS.copy()
        weights["stress_low"] = stress_low
        weights["stress_high"] = stress_high
        weights["offstreet_multiuse"] = offstreet_multiuse
        weights["ebike_restricted"] = ebike_restricted
        
        # Recalculate weights on all edges
        for u, v, d in G_connected.edges(data=True):
            infra_type = d.get("type", "residential")
            base_multiplier = weights.get(infra_type, DEFAULT_WEIGHTS.get(infra_type, 1.0))
            
            # Stress modifier
            stress = d.get("bikestress", "None")
            stress_modifier = 1.0
            if stress == "Low":
                stress_modifier = weights.get("stress_low", 0.7)
            elif stress == "High":
                stress_modifier = weights.get("stress_high", 2.0)
                
            # Offstreet modifiers
            offstreet_modifier = 1.0
            bicycles_allowed = d.get("bicycles_allowed", "Yes")
            
            if bicycles_allowed == "No":
                final_multiplier = 999999.0
            else:
                offstreet_type = d.get("offstreet_type", "None")
                if offstreet_type == "Multi-Use Path":
                    offstreet_modifier = weights.get("offstreet_multiuse", 0.8)
                    
                ebike_allowed = d.get("ebike_allowed", "Yes")
                ebike_modifier = 1.0
                if ebike_allowed == "No":
                    ebike_modifier = weights.get("ebike_restricted", 1.0)
                    
                final_multiplier = base_multiplier * stress_modifier * offstreet_modifier * ebike_modifier
                
            G_connected[u][v]["weight"] = d.get("length", 0.0) * final_multiplier
            
        path = nx.shortest_path(G_connected, source=start_node, target=end_node, weight="weight")
        
        # Count segments of interest on path
        high_stress_count = 0
        low_stress_count = 0
        multiuse_count = 0
        no_ebike_count = 0
        no_bike_count = 0
        total_length = 0
        
        for i in range(len(path) - 1):
            u, v = path[i], path[i+1]
            d = G_connected[u][v]
            total_length += d.get("length", 0.0)
            
            if d.get("bikestress") == "High":
                high_stress_count += 1
            elif d.get("bikestress") == "Low":
                low_stress_count += 1
                
            if d.get("offstreet_type") == "Multi-Use Path":
                multiuse_count += 1
                
            if d.get("bicycles_allowed") == "No":
                no_bike_count += 1
                
            if d.get("ebike_allowed") == "No":
                no_ebike_count += 1
                
        return path, total_length, low_stress_count, high_stress_count, multiuse_count, no_bike_count, no_ebike_count

    # Route 1: No modifiers (all 1.0)
    p1, len1, low1, high1, mu1, b1, eb1 = get_route_with_custom_weights(1.0, 1.0, 1.0, 1.0)
    print(f"Route 1 (No modifiers): Length={len1:.0f}m, Low Stress={low1}, High Stress={high1}, Multi-Use={mu1}, Bicycles Prohibited={b1}, E-Bikes Prohibited={eb1}")
    
    # Route 2: Multi-Use path priority (offstreet_multiuse = 0.2)
    p2, len2, low2, high2, mu2, b2, eb2 = get_route_with_custom_weights(1.0, 1.0, 0.2, 1.0)
    print(f"Route 2 (Multi-Use Priority 0.2x): Length={len2:.0f}m, Low Stress={low2}, High Stress={high2}, Multi-Use={mu2}, Bicycles Prohibited={b2}, E-Bikes Prohibited={eb2}")
    
    # Route 3: E-bike restriction penalty (ebike_restricted = 15.0)
    p3, len3, low3, high3, mu3, b3, eb3 = get_route_with_custom_weights(1.0, 1.0, 1.0, 15.0)
    print(f"Route 3 (E-Bike Prohibited Penalty 15x): Length={len3:.0f}m, Low Stress={low3}, High Stress={high3}, Multi-Use={mu3}, Bicycles Prohibited={b3}, E-Bikes Prohibited={eb3}")
    
    # Asserts to make sure restrictions work
    assert b1 == 0, "Route 1 contains Bicycles Prohibited segments!"
    assert b2 == 0, "Route 2 contains Bicycles Prohibited segments!"
    assert b3 == 0, "Route 3 contains Bicycles Prohibited segments!"
    
    print("\nVerification completed successfully!")

if __name__ == "__main__":
    test_routing()
