import sys
import os
import networkx as nx

# Add backend to path
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "backend")))
import app

# Build the graph
app.build_graph()
G = app.G_connected

# Coordinates:
# Start: South of Iris (Hermosa Dr area)
start_coords = (40.0360, -105.2682) 
# End: North of Iris (22nd St Path area)
end_coords = (40.0370, -105.2680)

start_node, start_dist = app.find_nearest_node(start_coords)
end_node, end_dist = app.find_nearest_node(end_coords)

print(f"Start Node: {start_node} (dist {start_dist:.2f}m)")
print(f"End Node: {end_node} (dist {end_dist:.2f}m)")

try:
    path = nx.shortest_path(G, source=start_node, target=end_node, weight="weight")
    print("\n=== ROUTE PATH ===")
    total_length = 0
    total_weight = 0
    for i in range(len(path) - 1):
        u = path[i]
        v = path[i+1]
        edge_data = G[u][v]
        name = edge_data.get("name", "unnamed")
        infra_type = edge_data.get("type", "residential")
        length = edge_data.get("length", 0.0)
        weight = edge_data.get("weight", 0.0)
        u_lat = G.nodes[u]["lat"]
        u_lon = G.nodes[u]["lon"]
        v_lat = G.nodes[v]["lat"]
        v_lon = G.nodes[v]["lon"]
        print(f"Edge {i+1}: {u} -> {v}")
        print(f"  Name: {name}, Type: {infra_type}")
        print(f"  Length: {length:.2f}m, Weight: {weight:.2f}")
        print(f"  Coords: ({u_lat}, {u_lon}) -> ({v_lat}, {v_lon})")
        total_length += length
        total_weight += weight
    print(f"\nTotal length: {total_length:.2f}m, Total weight: {total_weight:.2f}")
except Exception as e:
    print(f"Routing failed: {e}")
