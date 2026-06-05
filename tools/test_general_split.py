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

nodes = {}
for element in data.get("elements", []):
    if element.get("type") == "node":
        nodes[element["id"]] = {
            "lat": element["lat"],
            "lon": element["lon"],
            "tags": element.get("tags", {})
        }

# Pre-identify all ways that have lanes >= 4
four_lane_ways = {}
four_lane_nodes = set()
node_to_four_lane_ways = {}
way_orientations = {}

for element in data.get("elements", []):
    if element.get("type") == "way":
        way_id = element["id"]
        way_nodes = element.get("nodes", [])
        tags = element.get("tags", {})
        
        lanes_str = tags.get("lanes", "")
        try:
            if ";" in lanes_str:
                lanes = max([int(x) for x in lanes_str.split(";") if x.isdigit()])
            else:
                lanes = int(lanes_str) if lanes_str.isdigit() else 2
        except:
            lanes = 2
            
        if lanes >= 4:
            four_lane_ways[way_id] = tags
            for nid in way_nodes:
                four_lane_nodes.add(nid)
                if nid not in node_to_four_lane_ways:
                    node_to_four_lane_ways[nid] = set()
                node_to_four_lane_ways[nid].add(way_id)
            
            lats = [nodes[n]["lat"] for n in way_nodes if n in nodes]
            lons = [nodes[n]["lon"] for n in way_nodes if n in nodes]
            if lats and lons:
                lat_span = max(lats) - min(lats)
                lon_span = max(lons) - min(lons)
                orientation = "NS" if lat_span > lon_span else "EW"
            else:
                orientation = "NS"
            way_orientations[way_id] = orientation

print(f"Loaded {len(four_lane_ways)} 4+ lane ways and {len(four_lane_nodes)} nodes.")

# We will treat node 3338097013 as a safe crossing node
safe_crossing_nodes = {3338097013}

G = nx.Graph()

for element in data.get("elements", []):
    if element.get("type") == "way":
        way_id = element["id"]
        way_nodes = element.get("nodes", [])
        tags = element.get("tags", {})
        highway = tags.get("highway", "")
        
        if not highway or highway in ["motorway", "motorway_link", "trunk", "trunk_link"]:
            continue
            
        if way_id in four_lane_ways:
            # Reconstruct parallel sides for 4+ lane way
            orientation = way_orientations[way_id]
            for i in range(len(way_nodes) - 1):
                u = way_nodes[i]
                v = way_nodes[i+1]
                if u in nodes and v in nodes:
                    u_side1 = f"{u}_side1"
                    v_side1 = f"{v}_side1"
                    u_side2 = f"{u}_side2"
                    v_side2 = f"{v}_side2"
                    
                    G.add_node(u_side1, lat=nodes[u]["lat"], lon=nodes[u]["lon"])
                    G.add_node(v_side1, lat=nodes[v]["lat"], lon=nodes[v]["lon"])
                    G.add_node(u_side2, lat=nodes[u]["lat"], lon=nodes[u]["lon"])
                    G.add_node(v_side2, lat=nodes[v]["lat"], lon=nodes[v]["lon"])
                    
                    dist = haversine_distance((nodes[u]["lat"], nodes[u]["lon"]), (nodes[v]["lat"], nodes[v]["lon"]))
                    G.add_edge(u_side1, v_side1, length=dist, type="sidewalk_forced")
                    G.add_edge(u_side2, v_side2, length=dist, type="sidewalk_forced")
                    
            # Connect side1 and side2 at each node on this way
            for nid in way_nodes:
                if nid in nodes:
                    nid_side1 = f"{nid}_side1"
                    nid_side2 = f"{nid}_side2"
                    
                    if nid in safe_crossing_nodes:
                        G.add_edge(nid_side1, nid_side2, length=15.0, type="crossing_safe")
                    else:
                        G.add_edge(nid_side1, nid_side2, length=9999.0, type="crossing_unsafe")
        else:
            # For other streets, connect to side1 or side2 if they touch a 4+ lane node
            for i in range(len(way_nodes) - 1):
                u = way_nodes[i]
                v = way_nodes[i+1]
                if u in nodes and v in nodes:
                    u_name = u
                    v_name = v
                    
                    if u in four_lane_nodes:
                        # Find 4+ lane way it belongs to
                        parent_way_id = list(node_to_four_lane_ways[u])[0]
                        orientation = way_orientations[parent_way_id]
                        if orientation == "NS":
                            # East is side1, West is side2
                            if nodes[v]["lon"] > nodes[u]["lon"]:
                                u_name = f"{u}_side1"
                            else:
                                u_name = f"{u}_side2"
                        else:
                            # North is side1, South is side2
                            if nodes[v]["lat"] > nodes[u]["lat"]:
                                u_name = f"{u}_side1"
                            else:
                                u_name = f"{u}_side2"
                                
                    if v in four_lane_nodes:
                        parent_way_id = list(node_to_four_lane_ways[v])[0]
                        orientation = way_orientations[parent_way_id]
                        if orientation == "NS":
                            if nodes[u]["lon"] > nodes[v]["lon"]:
                                v_name = f"{v}_side1"
                            else:
                                v_name = f"{v}_side2"
                        else:
                            if nodes[u]["lat"] > nodes[v]["lat"]:
                                v_name = f"{v}_side1"
                            else:
                                v_name = f"{v}_side2"
                                
                    G.add_node(u_name, lat=nodes[u]["lat"], lon=nodes[u]["lon"])
                    G.add_node(v_name, lat=nodes[v]["lat"], lon=nodes[v]["lon"])
                    dist = haversine_distance((nodes[u]["lat"], nodes[u]["lon"]), (nodes[v]["lat"], nodes[v]["lon"]))
                    G.add_edge(u_name, v_name, length=dist, type="residential")

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
