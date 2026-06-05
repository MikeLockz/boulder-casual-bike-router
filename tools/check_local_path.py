import json
import math
import networkx as nx

CACHE_FILE = "backend/boulder_osm_data.json"

def haversine_distance(coord1, coord2):
    lat1, lon1 = coord1
    lat2, lon2 = coord2
    R = 6371000  # meters
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    delta_phi = math.radians(lat2 - lat1)
    delta_lambda = math.radians(lon2 - lon1)
    a = math.sin(delta_phi/2)**2 + math.cos(phi1) * math.cos(phi2) * math.sin(delta_lambda/2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
    return R * c

target_start = (40.028446, -105.281088) # Cedar Ave
target_end = (40.0280, -105.2831) # North Boulder Park

with open(CACHE_FILE) as f:
    data = json.load(f)

# Rebuild graph like backend/app.py does
G = nx.Graph()
nodes = {}
for element in data.get("elements", []):
    if element.get("type") == "node":
        nodes[element["id"]] = {
            "lat": element["lat"],
            "lon": element["lon"]
        }

for element in data.get("elements", []):
    if element.get("type") == "way":
        way_nodes = element.get("nodes", [])
        highway = element.get("tags", {}).get("highway", "")
        if highway and highway not in ["motorway", "motorway_link", "trunk", "trunk_link"]:
            for i in range(len(way_nodes) - 1):
                u = way_nodes[i]
                v = way_nodes[i+1]
                if u in nodes and v in nodes:
                    G.add_node(u, lat=nodes[u]["lat"], lon=nodes[u]["lon"])
                    G.add_node(v, lat=nodes[v]["lat"], lon=nodes[v]["lon"])
                    G.add_edge(u, v, length=haversine_distance((nodes[u]["lat"], nodes[u]["lon"]), (nodes[v]["lat"], nodes[v]["lon"])))

print(f"Nodes loaded in dict: {len(nodes)}")
print(f"Nodes in Graph: {len(G)}")

if len(G) > 0:
    min_dist_start = float("inf")
    nearest_start = None
    min_dist_end = float("inf")
    nearest_end = None

    for node, ndata in G.nodes(data=True):
        d_start = haversine_distance(target_start, (ndata["lat"], ndata["lon"]))
        if d_start < min_dist_start:
            min_dist_start = d_start
            nearest_start = node
            
        d_end = haversine_distance(target_end, (ndata["lat"], ndata["lon"]))
        if d_end < min_dist_end:
            min_dist_end = d_end
            nearest_end = node

    print(f"Nearest node to Cedar Ave: Node {nearest_start} at distance {min_dist_start:.1f}m, lat={G.nodes[nearest_start]['lat']:.6f}, lon={G.nodes[nearest_start]['lon']:.6f}")
    print(f"Nearest node to North Boulder Park: Node {nearest_end} at distance {min_dist_end:.1f}m, lat={G.nodes[nearest_end]['lat']:.6f}, lon={G.nodes[nearest_end]['lon']:.6f}")

    for el in data.get("elements", []):
        if el.get("type") == "way":
            nodes_in_way = el.get("nodes", [])
            if nearest_start in nodes_in_way:
                print(f"Start node is in way {el['id']}: {el.get('tags', {}).get('name')}, highway={el.get('tags', {}).get('highway')}")
            if nearest_end in nodes_in_way:
                print(f"End node is in way {el['id']}: {el.get('tags', {}).get('name')}, highway={el.get('tags', {}).get('highway')}")
                
    try:
        path = nx.shortest_path(G, source=nearest_start, target=nearest_end, weight="length")
        print(f"\nShortest path nodes count: {len(path)}")
        for nid in path:
            print(f"  Node {nid}: lat={G.nodes[nid]['lat']:.6f}, lon={G.nodes[nid]['lon']:.6f}")
    except Exception as e:
        print("No path found:", e)
else:
    print("Graph G is empty!")
