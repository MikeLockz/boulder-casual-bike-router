#!/usr/bin/env python3
"""Sync searchable Boulder places from open place data into PocketBase."""

import argparse
import json
import os
import re
import sys
import time

import requests

DEFAULT_BBOX = "39.96,-105.30,40.09,-105.18"
DEFAULT_PLACE_CACHE_FILE = "backend/boulder_place_osm_data.json"
DEFAULT_PLAYGROUND_CACHE_FILE = "backend/boulder_playground_data.json"
OVERPASS_URLS = (
    "https://overpass-api.de/api/interpreter",
    "https://z.overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
)
PLACE_TAG_KEYS = (
    "amenity",
    "shop",
    "tourism",
    "leisure",
    "natural",
    "historic",
    "highway",
    "public_transport",
    "place",
)
ALLOWED_PLACE_TYPES = {
    "bar",
    "bench",
    "bicycle_parking",
    "bicycle_rental",
    "bus_stop",
    "cafe",
    "community_centre",
    "drinking_water",
    "fast_food",
    "fuel",
    "library",
    "park",
    "parking",
    "peak",
    "pharmacy",
    "place_of_worship",
    "playground",
    "pub",
    "restaurant",
    "school",
    "shelter",
    "toilets",
    "trailhead",
    "university",
    "viewpoint",
}
PLACE_FOCUSED_HIGHWAY_TYPES = {
    "bus_stop",
    "pedestrian",
    "trailhead",
}


def normalize_search_name(value):
    return re.sub(r"\s+", " ", str(value or "").strip().lower())


def auth_headers(pb_url, email, password):
    if not email or not password:
        raise RuntimeError("Set POCKETBASE_ADMIN_EMAIL and POCKETBASE_ADMIN_PASSWORD.")

    candidates = [
        f"{pb_url}/api/collections/_superusers/auth-with-password",
        f"{pb_url}/api/admins/auth-with-password",
    ]
    last_error = None
    for url in candidates:
        try:
            resp = requests.post(url, json={"identity": email, "email": email, "password": password}, timeout=10)
            if resp.status_code == 200:
                token = resp.json().get("token")
                if token:
                    return {"Authorization": f"Bearer {token}"}
            last_error = f"{resp.status_code}: {resp.text}"
        except requests.RequestException as exc:
            last_error = str(exc)
    raise RuntimeError(f"PocketBase admin authentication failed: {last_error}")


def fetch_osm_places(bbox):
    query = f"""
    [out:json][timeout:180];
    (
      node["name"]["amenity"]({bbox});
      way["name"]["amenity"]({bbox});
      relation["name"]["amenity"]({bbox});
      node["name"]["shop"]({bbox});
      way["name"]["shop"]({bbox});
      relation["name"]["shop"]({bbox});
      node["name"]["tourism"]({bbox});
      way["name"]["tourism"]({bbox});
      relation["name"]["tourism"]({bbox});
      node["name"]["leisure"]({bbox});
      way["name"]["leisure"]({bbox});
      relation["name"]["leisure"]({bbox});
      node["name"]["natural"]({bbox});
      way["name"]["natural"]({bbox});
      relation["name"]["natural"]({bbox});
      node["name"]["historic"]({bbox});
      way["name"]["historic"]({bbox});
      relation["name"]["historic"]({bbox});
      node["name"]["public_transport"]({bbox});
      way["name"]["public_transport"]({bbox});
      relation["name"]["public_transport"]({bbox});
      node["name"]["place"]({bbox});
      way["name"]["place"]({bbox});
      relation["name"]["place"]({bbox});
      node["name"]["highway"~"^(bus_stop|pedestrian|trailhead)$"]({bbox});
      way["name"]["highway"~"^(pedestrian|trailhead)$"]({bbox});
      relation["name"]["highway"~"^(pedestrian|trailhead)$"]({bbox});
    );
    out center tags;
    """
    headers = {"User-Agent": "BoulderBikeRouterPlaces/1.0"}
    errors = []
    for url in OVERPASS_URLS:
        try:
            resp = requests.post(url, data={"data": query}, headers=headers, timeout=180)
            resp.raise_for_status()
            return resp.json().get("elements", [])
        except requests.RequestException as exc:
            errors.append(f"{url}: {exc}")
    raise RuntimeError("All Overpass endpoints failed: " + "; ".join(errors))


def load_or_fetch_osm_places(cache_file, bbox, refresh=False):
    if cache_file and os.path.exists(cache_file) and not refresh:
        return load_cached_osm_places(cache_file)

    elements = fetch_osm_places(bbox)
    if cache_file:
        with open(cache_file, "w", encoding="utf-8") as f:
            json.dump({"elements": elements}, f)
    return elements


def load_cached_osm_places(cache_file):
    with open(cache_file, encoding="utf-8") as f:
        data = json.load(f)

    elements = data.get("elements", []) if isinstance(data, dict) else data
    node_coords = {
        element.get("id"): (element.get("lat"), element.get("lon"))
        for element in elements
        if element.get("type") == "node" and element.get("lat") is not None and element.get("lon") is not None
    }

    cached_places = []
    for element in elements:
        if element.get("lat") is not None or element.get("center"):
            cached_places.append(element)
            continue

        node_ids = element.get("nodes") or []
        coords = [node_coords[node_id] for node_id in node_ids if node_id in node_coords]
        if not coords:
            continue

        lat = sum(coord[0] for coord in coords) / len(coords)
        lon = sum(coord[1] for coord in coords) / len(coords)
        cached_places.append({**element, "center": {"lat": lat, "lon": lon}})

    return cached_places


def place_type(tags, osm_type):
    for key in PLACE_TAG_KEYS:
        value = tags.get(key)
        if value:
            return str(value)
    return osm_type


def should_include(tags, feature_type):
    if not tags.get("name"):
        return False
    if "highway" in tags:
        return feature_type in PLACE_FOCUSED_HIGHWAY_TYPES
    if feature_type in ALLOWED_PLACE_TYPES:
        return True
    return any(key in tags for key in PLACE_TAG_KEYS if key != "highway")


def element_payload(element):
    tags = element.get("tags") or {}
    name = str(tags.get("name") or "").strip()
    feature_type = place_type(tags, element.get("type") or "osm")
    if not should_include(tags, feature_type):
        return None

    center = element.get("center") or {}
    lat = element.get("lat", center.get("lat"))
    lng = element.get("lon", center.get("lon"))
    if lat is None or lng is None:
        return None

    return {
        "osm_type": str(element.get("type")),
        "osm_id": str(element.get("id")),
        "name": name,
        "search_name": normalize_search_name(name),
        "type": feature_type[:80],
        "lat": float(lat),
        "lng": float(lng),
        "source": "osm",
        "tags": {key: tags[key] for key in PLACE_TAG_KEYS if key in tags},
    }


def calculate_ring_centroid(coords):
    points = [(float(lon), float(lat)) for lon, lat, *_ in coords if lon is not None and lat is not None]
    if not points:
        return None
    area = 0.0
    cx = 0.0
    cy = 0.0
    for i, (x1, y1) in enumerate(points):
        x2, y2 = points[(i + 1) % len(points)]
        cross = x1 * y2 - x2 * y1
        area += cross
        cx += (x1 + x2) * cross
        cy += (y1 + y2) * cross
    if abs(area) < 1e-12:
        lon = sum(point[0] for point in points) / len(points)
        lat = sum(point[1] for point in points) / len(points)
        return lat, lon
    area *= 0.5
    return cy / (6 * area), cx / (6 * area)


def playground_payloads(cache_file):
    if not cache_file or not os.path.exists(cache_file):
        return []
    with open(cache_file, encoding="utf-8") as f:
        data = json.load(f)
    payloads = []
    for feature in data.get("features", []):
        properties = feature.get("properties") or {}
        geometry = feature.get("geometry") or {}
        if properties.get("PLAYTYPE") != "Park Playground":
            continue
        coords = (geometry.get("coordinates") or [[]])[0]
        centroid = calculate_ring_centroid(coords)
        if not centroid:
            continue
        lat, lng = centroid
        object_id = properties.get("OBJECTID") or properties.get("GLOBALID") or properties.get("NAME")
        park_name = str(properties.get("PROPNAME") or "").strip()
        play_name = str(properties.get("NAME") or "").strip()
        name = park_name or play_name
        if not name:
            continue
        payloads.append({
            "osm_type": "boulder_playground",
            "osm_id": str(object_id),
            "name": name,
            "search_name": normalize_search_name(name),
            "type": "playground",
            "lat": float(lat),
            "lng": float(lng),
            "source": "boulder_open_data",
            "tags": {
                "park_name": park_name,
                "playground_name": play_name,
                "play_type": properties.get("PLAYTYPE"),
            },
        })
    return payloads


def find_existing_place(pb_url, headers, payload):
    resp = requests.get(
        f"{pb_url}/api/collections/places/records",
        headers=headers,
        params={
            "filter": f'osm_type="{payload["osm_type"]}" && osm_id="{payload["osm_id"]}"',
            "perPage": 1,
        },
        timeout=10,
    )
    resp.raise_for_status()
    items = resp.json().get("items", [])
    return items[0] if items else None


def upsert_place(pb_url, headers, payload):
    existing = find_existing_place(pb_url, headers, payload)
    if existing:
        resp = requests.patch(
            f'{pb_url}/api/collections/places/records/{existing["id"]}',
            headers=headers,
            json=payload,
            timeout=10,
        )
        resp.raise_for_status()
        return "updated"

    resp = requests.post(f"{pb_url}/api/collections/places/records", headers=headers, json=payload, timeout=10)
    resp.raise_for_status()
    return "created"


def sync_places(pb_url, headers, elements):
    counts = {"created": 0, "updated": 0, "skipped": 0, "failed": 0}
    seen = set()
    for element in elements:
        payload = element_payload(element)
        if not payload:
            counts["skipped"] += 1
            continue

        dedupe_key = (payload["osm_type"], payload["osm_id"])
        if dedupe_key in seen:
            counts["skipped"] += 1
            continue
        seen.add(dedupe_key)

        try:
            outcome = upsert_place(pb_url, headers, payload)
            counts[outcome] += 1
        except requests.RequestException as exc:
            counts["failed"] += 1
            print(f'Failed {payload["name"]} ({payload["osm_type"]}/{payload["osm_id"]}): {exc}', file=sys.stderr)

        time.sleep(0.02)
    return counts


def delete_generated_places(pb_url, headers):
    counts = {"deleted": 0, "failed": 0}
    for source in ("osm", "boulder_open_data"):
        while True:
            resp = requests.get(
                f"{pb_url}/api/collections/places/records",
                headers=headers,
                params={"filter": f'source="{source}"', "perPage": 200},
                timeout=10,
            )
            resp.raise_for_status()
            items = resp.json().get("items", [])
            if not items:
                break
            for item in items:
                try:
                    delete_resp = requests.delete(
                        f'{pb_url}/api/collections/places/records/{item["id"]}',
                        headers=headers,
                        timeout=10,
                    )
                    delete_resp.raise_for_status()
                    counts["deleted"] += 1
                except requests.RequestException as exc:
                    counts["failed"] += 1
                    print(f'Failed to delete stale place {item.get("id")}: {exc}', file=sys.stderr)
    return counts


def sync_payloads(pb_url, headers, payloads):
    counts = {"created": 0, "updated": 0, "skipped": 0, "failed": 0}
    seen = set()
    for payload in payloads:
        dedupe_key = (payload["osm_type"], payload["osm_id"])
        if dedupe_key in seen:
            counts["skipped"] += 1
            continue
        seen.add(dedupe_key)
        try:
            outcome = upsert_place(pb_url, headers, payload)
            counts[outcome] += 1
        except requests.RequestException as exc:
            counts["failed"] += 1
            print(f'Failed {payload["name"]} ({payload["osm_type"]}/{payload["osm_id"]}): {exc}', file=sys.stderr)
        time.sleep(0.02)
    return counts


def main():
    parser = argparse.ArgumentParser(description="Sync Boulder open-data places into PocketBase.")
    parser.add_argument("--bbox", default=DEFAULT_BBOX, help="Overpass bbox as south,west,north,east.")
    parser.add_argument("--pb-url", default=os.environ.get("POCKETBASE_URL", "http://127.0.0.1:8090"))
    parser.add_argument("--place-cache-file", default=DEFAULT_PLACE_CACHE_FILE, help="Dedicated place-focused OSM JSON cache.")
    parser.add_argument("--refresh-place-cache", action="store_true", help="Fetch place-focused OSM data even if the cache exists.")
    parser.add_argument("--playground-cache-file", default=DEFAULT_PLAYGROUND_CACHE_FILE, help="Boulder playground open-data cache.")
    parser.add_argument("--replace-generated", action="store_true", help="Delete existing generated place records before syncing.")
    parser.add_argument("--cache-file", help=argparse.SUPPRESS)
    args = parser.parse_args()

    pb_url = args.pb_url.rstrip("/")
    headers = auth_headers(
        pb_url,
        os.environ.get("POCKETBASE_ADMIN_EMAIL"),
        os.environ.get("POCKETBASE_ADMIN_PASSWORD"),
    )
    if args.replace_generated:
        deleted = delete_generated_places(pb_url, headers)
        print(f'Pruned generated places: {deleted["deleted"]} deleted, {deleted["failed"]} failed.')

    if args.cache_file:
        print("Warning: --cache-file is deprecated for place search. Use --place-cache-file.", file=sys.stderr)
        elements = load_cached_osm_places(args.cache_file)
    else:
        elements = load_or_fetch_osm_places(args.place_cache_file, args.bbox, args.refresh_place_cache)
    counts = sync_places(pb_url, headers, elements)
    playground_counts = sync_payloads(pb_url, headers, playground_payloads(args.playground_cache_file))
    print(
        "OSM places sync complete: "
        f'{counts["created"]} created, {counts["updated"]} updated, '
        f'{counts["skipped"]} skipped, {counts["failed"]} failed.'
    )
    print(
        "Boulder playground places sync complete: "
        f'{playground_counts["created"]} created, {playground_counts["updated"]} updated, '
        f'{playground_counts["skipped"]} skipped, {playground_counts["failed"]} failed.'
    )
    return 1 if counts["failed"] or playground_counts["failed"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
