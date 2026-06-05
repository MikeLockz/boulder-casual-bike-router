import sys
import networkx as nx

import os
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "backend")))
import app

app.build_graph()
G = app.G_connected

crossing_node = 1773983960
side1 = f"{crossing_node}_side1"
side2 = f"{crossing_node}_side2"

print(f"Graph has node {side1}: {G.has_node(side1)}")
print(f"Graph has node {side2}: {G.has_node(side2)}")

if G.has_node(side1):
    print(f"\nNeighbors of {side1}:")
    for nbr in G.neighbors(side1):
        print(f"  {nbr}: {G[side1][nbr]}")

if G.has_node(side2):
    print(f"\nNeighbors of {side2}:")
    for nbr in G.neighbors(side2):
        print(f"  {nbr}: {G[side2][nbr]}")

# Let's check other nodes nearby like 13099844036 and 10971354980
for node in ["13099844036", "10971354980"]:
    if G.has_node(node):
        print(f"\nNeighbors of {node}:")
        for nbr in G.neighbors(node):
            print(f"  {nbr}: {G[node][nbr]}")
    else:
         print(f"\nGraph does not have node {node}")

# Check if there is a path from side1 to side2 and what is its weight
if G.has_node(side1) and G.has_node(side2):
    has_path = nx.has_path(G, side1, side2)
    print(f"\nHas path between {side1} and {side2}: {has_path}")
    if has_path:
        path = nx.shortest_path(G, side1, side2, weight="weight")
        print(f"Path: {path}")
        weight = nx.shortest_path_length(G, side1, side2, weight="weight")
        print(f"Weight: {weight}")
