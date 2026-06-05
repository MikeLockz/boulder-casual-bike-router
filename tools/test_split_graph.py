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

with open(CACHE_FILE) as f:
    data = json.load(f)

# Rebuild nodes dict
nodes = {}
for element in data.get("elements", []):
    if element.get("type") == "node":
        nodes[element["id"]] = {
            "lat": element["lat"],
            "lon": element["lon"],
            "tags": element.get("tags", {})
        }

# Identify safe crossing nodes
# Node 3338097013 is safe! Let's mock it for the test.
safe_crossing_nodes = {3338097013}

# Build Broadway nodes set
broadway_way_id = 400362582
broadway_nodes = set()
for element in data.get("elements", []):
    if element.get("type") == "way" and element["id"] == broadway_way_id:
        broadway_nodes.update(element.get("nodes", []))

print(f"Broadway nodes loaded: {len(broadway_nodes)}")

G = nx.Graph()

for element in data.get("elements", []):
    if element.get("type") == "way":
        way_nodes = element.get("nodes", [])
        highway = element.get("tags", {}).get("highway", "")
        name = element.get("tags", {}).get("name", "")
        
        if not highway or highway in ["motorway", "motorway_link", "trunk", "trunk_link"]:
            continue
            
        if element["id"] == broadway_way_id:
            # Duplicate Broadway into east and west sidewalks
            for i in range(len(way_nodes) - 1):
                u = way_nodes[i]
                v = way_nodes[i+1]
                if u in nodes and v in nodes:
                    # East side edges
                    u_east = f"{u}_east"
                    v_east = f"{v}_east"
                    G.add_node(u_east, lat=nodes[u]["lat"], lon=nodes[u]["lon"])
                    G.add_node(v_east, lat=nodes[v]["lat"], lon=nodes[v]["lon"])
                    G.add_edge(u_east, v_east, length=haversine_distance((nodes[u]["lat"], nodes[u]["lon"]), (nodes[v]["lat"], nodes[v]["lon"])), type="sidewalk_forced")
                    
                    # West side edges
                    u_west = f"{u}_west"
                    v_west = f"{v}_west"
                    G.add_node(u_west, lat=nodes[u]["lat"], lon=nodes[u]["lon"])
                    G.add_node(v_west, lat=nodes[v]["lat"], lon=nodes[v]["lon"])
                    G.add_edge(u_west, v_west, length=haversine_distance((nodes[u]["lat"], nodes[u]["lon"]), (nodes[v]["lat"], nodes[v]["lon"])), type="sidewalk_forced")
            
            # Connect the east and west sides at crossing nodes
            for nid in way_nodes:
                if nid in nodes:
                    nid_east = f"{nid}_east"
                    nid_west = f"{nid}_west"
                    if nid in safe_crossing_nodes:
                        # Safe crossing edge (short virtual length)
                        G.add_edge(nid_east, nid_west, length=15.0, type="crossing_safe")
                        print(f"Connected safe crossing at node {nid}")
                    else:
                        # Unsafe crossing edge (extremely high length to block it)
                        G.add_edge(nid_east, nid_west, length=99999.0, type="crossing_unsafe")
        else:
            # For other streets (like Cedar Ave), connect them to the east or west side of Broadway
            for i in range(len(way_nodes) - 1):
                u = way_nodes[i]
                v = way_nodes[i+1]
                if u in nodes and v in nodes:
                    # Determine node names
                    u_name = u
                    v_name = v
                    
                    # Check if u is on Broadway
                    if u in broadway_nodes:
                        # Connect to east or west based on neighbor v's longitude
                        if nodes[v]["lon"] > nodes[u]["lon"]:
                            u_name = f"{u}_east"
                        else:
                            u_name = f"{u}_west"
                            
                    # Check if v is on Broadway
                    if v in broadway_nodes:
                        if nodes[u]["lon"] > nodes[v]["lon"]:
                            v_name = f"{v}_east"
                        else:
                            v_name = f"{v}_west"
                            
                    G.add_node(u_name, lat=nodes[u]["lat"], lon=nodes[u]["lon"])
                    G.add_node(v_name, lat=nodes[v]["lat"], lon=nodes[v]["lon"])
                    G.add_edge(u_name, v_name, length=haversine_distance((nodes[u]["lat"], nodes[u]["lon"]), (nodes[v]["lat"], nodes[v]["lon"])), type="residential")

# Run route test
# Start: Cedar Ave east of Broadway (Node 4675671297)
# End: Cedar Ave west of Broadway (Node 176567449)
start_node = 4675671297
end_node = 176567449

try:
    path = nx.shortest_path(G, source=start_node, target=end_node, weight="length")
    print(f"\nShortest path found: {len(path)} nodes")
    for nid in path:
        if isinstance(nid, str):
            orig_id = nid.split("_")[0]
            lat, lon = nodes[int(orig_id)]["lat"], nodes[int(orig_id)]["lon"]
            print(f"  Node {nid}: lat={lat:.6f}, lon={lon:.6f}")
        else:
            print(f"  Node {nid}: lat={nodes[nid]['lat']:.6f}, lon={nodes[nid]['lon']:.6f}")
except Exception as e:
    print("Failed to route:", e)
