#!/usr/bin/env python3
"""
analyze_route.py — Boulder Bike Router: Route Analyzer

Builds the routing graph and prints a detailed edge-by-edge breakdown of the
shortest path between two lat/lon coordinates. Useful for debugging routing
decisions, verifying crossing logic, and tuning weights.

Usage:
    ./venv/bin/python3 tools/analyze_route.py <start_lat> <start_lon> <end_lat> <end_lon>

Examples:
    # South of Iris Ave bike path crossing to North (22nd St Path area)
    ./venv/bin/python3 tools/analyze_route.py 40.0360 -105.2682 40.0370 -105.2680

    # Downtown Boulder to North Boulder
    ./venv/bin/python3 tools/analyze_route.py 40.0150 -105.2705 40.0600 -105.2800
"""

import sys
import os
import argparse
import networkx as nx

# Make `backend/app` importable from the project root
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "backend"))
import app


def format_node(node_id):
    """Return a short, readable representation of a node ID."""
    s = str(node_id)
    if s.endswith("_side1"):
        return f"{s[:-6]} [side1]"
    if s.endswith("_side2"):
        return f"{s[:-6]} [side2]"
    return s


def analyze_route(start_lat, start_lon, end_lat, end_lon, verbose=False):
    print("Building routing graph...")
    app.build_graph()
    G = app.G_connected

    start_node, start_dist = app.find_nearest_node((start_lat, start_lon))
    end_node, end_dist = app.find_nearest_node((end_lat, end_lon))

    print(f"\nStart: ({start_lat}, {start_lon})")
    print(f"  → Snapped to node {format_node(start_node)} ({start_dist:.1f}m away)")
    print(f"End:   ({end_lat}, {end_lon})")
    print(f"  → Snapped to node {format_node(end_node)} ({end_dist:.1f}m away)")

    try:
        path = nx.shortest_path(G, source=start_node, target=end_node, weight="weight")
    except nx.NetworkXNoPath:
        print("\n[ERROR] No route found between these points.")
        sys.exit(1)
    except Exception as e:
        print(f"\n[ERROR] Routing failed: {e}")
        sys.exit(1)

    print(f"\n{'='*60}")
    print(f"ROUTE BREAKDOWN  ({len(path)-1} segments)")
    print(f"{'='*60}")

    total_length = 0.0
    total_weight = 0.0
    type_summary = {}

    for i in range(len(path) - 1):
        u = path[i]
        v = path[i + 1]
        d = G[u][v]

        name       = d.get("name", "Unnamed")
        infra_type = d.get("type", "residential")
        length     = d.get("length", 0.0)
        weight     = d.get("weight", 0.0)
        stress     = d.get("bikestress", "None")
        offstreet  = d.get("offstreet_type", "None")
        u_lat      = G.nodes[u].get("lat", "?")
        u_lon      = G.nodes[u].get("lon", "?")
        v_lat      = G.nodes[v].get("lat", "?")
        v_lon      = G.nodes[v].get("lon", "?")

        total_length += length
        total_weight += weight
        type_summary[infra_type] = type_summary.get(infra_type, 0) + 1

        seg_num = f"#{i+1:>3}"
        print(f"\n{seg_num}  {name}  [{infra_type}]")
        print(f"     Length: {length:>8.2f}m   Weight: {weight:>8.2f}")
        if stress != "None":
            print(f"     Bike Stress: {stress}   Off-street: {offstreet}")
        if verbose:
            print(f"     {format_node(u)} ({u_lat}, {u_lon})")
            print(f"       → {format_node(v)} ({v_lat}, {v_lon})")

    print(f"\n{'='*60}")
    print(f"SUMMARY")
    print(f"{'='*60}")
    print(f"  Total distance : {total_length:>8.1f} m  ({total_length/1000:.2f} km, {total_length*0.000621371:.2f} mi)")
    print(f"  Total weight   : {total_weight:>8.1f}")
    print(f"\n  Segment type breakdown:")
    for t, count in sorted(type_summary.items(), key=lambda x: -x[1]):
        print(f"    {t:<25} {count:>4} segment(s)")


def main():
    parser = argparse.ArgumentParser(
        description="Analyze a bike route between two lat/lon coordinates.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument("start_lat", type=float, help="Start latitude")
    parser.add_argument("start_lon", type=float, help="Start longitude")
    parser.add_argument("end_lat",   type=float, help="End latitude")
    parser.add_argument("end_lon",   type=float, help="End longitude")
    parser.add_argument(
        "-v", "--verbose",
        action="store_true",
        help="Also print node IDs and exact coordinates for each segment",
    )
    args = parser.parse_args()

    analyze_route(
        args.start_lat, args.start_lon,
        args.end_lat,   args.end_lon,
        verbose=args.verbose,
    )


if __name__ == "__main__":
    main()
