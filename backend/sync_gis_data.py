import argparse
import datetime
import hashlib
import json
import os
import tempfile
import urllib.parse
import urllib.request
from graph_cache import invalidate_graph_cache


BOULDER_DATASETS = {
    "boulder_bike_stress_data.json": "https://opendata.arcgis.com/datasets/e20bc9b72c3b4d0fac167d722a7cf1b7_0.geojson",
    "boulder_bike_offstreet_data.json": "https://opendata.arcgis.com/datasets/8cae0bbbd3154abe8264fa349b8f245f_0.geojson",
    "boulder_playground_data.json": "https://opendata.arcgis.com/datasets/b1297c2328b343528f70dfd78c6de459_1.geojson",
}

BROOMFIELD_TRAILS_ITEM_ID = "a3e0fb66f336431d8de7a72e143e2ee7"
BROOMFIELD_TRAILS_URL = "https://services1.arcgis.com/vXSRPZbyyOmH9pek/arcgis/rest/services/Trails/FeatureServer/0/query"
BROOMFIELD_TRAILS_CACHE = "broomfield_bike_offstreet_data.json"
BROOMFIELD_PAGE_SIZE = 1000


def request_json(url, params=None):
    if params:
        url = f"{url}?{urllib.parse.urlencode(params)}"
    request = urllib.request.Request(url, headers={"User-Agent": "BoulderCasualBikeRouter/1.0"})
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.loads(response.read().decode("utf-8"))


def atomic_json_write(path, data):
    directory = os.path.dirname(path)
    with tempfile.NamedTemporaryFile("w", dir=directory, delete=False, suffix=".tmp") as handle:
        json.dump(data, handle, separators=(",", ":"))
        temp_path = handle.name
    os.replace(temp_path, path)
    os.chmod(path, 0o644)


def iter_line_coordinates(geometry):
    if geometry.get("type") == "LineString":
        yield geometry.get("coordinates", [])
    elif geometry.get("type") == "MultiLineString":
        yield from geometry.get("coordinates", [])


def normalize_broomfield_trail(feature):
    properties = feature.get("properties") or {}
    status = str(properties.get("STATUS") or "").strip().upper()
    bike_allowed = str(properties.get("BAT_BIKE") or "").strip().lower()
    geometry = feature.get("geometry") or {}
    if status != "EXISTING" or bike_allowed not in {"yes", "y", "true", "1"}:
        return None
    if geometry.get("type") not in {"LineString", "MultiLineString"}:
        return None

    trail_type = str(properties.get("TRAIL_TYPE") or properties.get("BAT_TRAILTYPE") or "").strip()
    surface_type = str(properties.get("BAT_SURTYPE") or "").strip()
    facility_types = {
        "multi-use path": "Multi-Use Path",
        "soft surface trail": "Soft Surface Trail",
        "on-street bike lane": "On-Street Bike Lane",
        "detached sidewalk": "Sidewalk",
        "attached sidewalk": "Sidewalk",
        "8ft attached sidewalk": "Sidewalk",
        "cross-walk": "Pedestrian Path",
    }
    facility_type = facility_types.get(trail_type.lower())
    if facility_type is None:
        return None
    normalized = dict(properties)
    normalized.update({
        "FACILITYTYPE": facility_type,
        "BICYCLES": "Yes",
        "EBIKE": "Yes",
        "NAME": properties.get("SITE_NAME") or properties.get("ALTERNATE_NAME") or "Unnamed Broomfield Trail",
        "SOURCE_REGION": "broomfield",
        "SOURCE_TRAIL_TYPE": trail_type,
        "SOURCE_SURFACE_TYPE": surface_type,
        "COMFORT_CLASS": "soft_surface" if "soft" in surface_type.lower() else "hard_surface",
    })
    return {"type": "Feature", "id": feature.get("id"), "geometry": geometry, "properties": normalized}


def validate_line_collection(features):
    if not features:
        raise ValueError("Broomfield Trails returned no eligible bike trail features")
    bounds = [180.0, 90.0, -180.0, -90.0]
    coordinate_count = 0
    for feature in features:
        for line in iter_line_coordinates(feature["geometry"]):
            for coordinate in line:
                if len(coordinate) < 2:
                    raise ValueError("Trail geometry contains an invalid coordinate")
                lon, lat = coordinate[:2]
                if not (-180 <= lon <= 180 and -90 <= lat <= 90):
                    raise ValueError("Trail geometry is not WGS84")
                bounds = [min(bounds[0], lon), min(bounds[1], lat), max(bounds[2], lon), max(bounds[3], lat)]
                coordinate_count += 1
    if coordinate_count == 0:
        raise ValueError("Broomfield Trails contains no line coordinates")
    return bounds


def fetch_broomfield_trails():
    features = []
    offset = 0
    while True:
        page = request_json(BROOMFIELD_TRAILS_URL, {
            "where": "1=1",
            "outFields": "*",
            "returnGeometry": "true",
            "outSR": 4326,
            "f": "geojson",
            "orderByFields": "OBJECTID",
            "resultOffset": offset,
            "resultRecordCount": BROOMFIELD_PAGE_SIZE,
        })
        page_features = page.get("features", [])
        features.extend(page_features)
        if len(page_features) < BROOMFIELD_PAGE_SIZE:
            break
        offset += len(page_features)

    normalized = [item for feature in features if (item := normalize_broomfield_trail(feature))]
    bounds = validate_line_collection(normalized)
    checksum = hashlib.sha256(json.dumps(normalized, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
    return {
        "type": "FeatureCollection",
        "features": normalized,
        "metadata": {
            "source_item_id": BROOMFIELD_TRAILS_ITEM_ID,
            "source_url": BROOMFIELD_TRAILS_URL,
            "retrieved_at": datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00", "Z"),
            "source_feature_count": len(features),
            "feature_count": len(normalized),
            "bounds": bounds,
            "sha256": checksum,
        },
    }


def sync_boulder(backend_dir, replaced_regions):
    for filename, url in BOULDER_DATASETS.items():
        data = request_json(url)
        if not data.get("features"):
            raise ValueError(f"{filename} returned no features")
        atomic_json_write(os.path.join(backend_dir, filename), data)
        # Only trigger invalidation for graph-affecting datasets
        if filename in ["boulder_bike_stress_data.json", "boulder_bike_offstreet_data.json"]:
            replaced_regions.add("boulder")
        print(f"Saved {filename} ({len(data['features'])} features)")


def sync_broomfield(backend_dir, replaced_regions):
    data = fetch_broomfield_trails()
    atomic_json_write(os.path.join(backend_dir, BROOMFIELD_TRAILS_CACHE), data)
    replaced_regions.add("broomfield")
    print(f"Saved {BROOMFIELD_TRAILS_CACHE} ({len(data['features'])} features)")


def main():
    parser = argparse.ArgumentParser(description="Refresh validated routing GIS caches")
    parser.add_argument("--boulder", action="store_true", help="refresh Boulder GIS caches")
    parser.add_argument("--broomfield", action="store_true", help="refresh Broomfield Trails cache")
    args = parser.parse_args()
    backend_dir = os.path.dirname(os.path.abspath(__file__))
    if not args.boulder and not args.broomfield:
        args.boulder = args.broomfield = True
    
    replaced_regions = set()
    try:
        if args.boulder:
            sync_boulder(backend_dir, replaced_regions)
        if args.broomfield:
            sync_broomfield(backend_dir, replaced_regions)
    finally:
        for region_id in sorted(replaced_regions):
            success, reason = invalidate_graph_cache(region_id)
            print(f"Proactive cache invalidation for {region_id}: {reason}")


if __name__ == "__main__":
    main()
