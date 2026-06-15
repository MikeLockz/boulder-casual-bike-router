import os
import sys
import json
import hashlib
import pickle
import gzip
import tempfile
import datetime
import networkx as nx

# --- Constants & Versioning ---
# GRAPH_CACHE_FORMAT_VERSION should be bumped whenever the structure of the serialized bundle changes.
GRAPH_CACHE_FORMAT_VERSION = 1

# GRAPH_BUILD_VERSION should be bumped whenever the graph building or weighting logic in app.py changes.
GRAPH_BUILD_VERSION = 1

BACKEND_DIR = os.path.dirname(os.path.abspath(__file__))
GRAPH_CACHE_DIR = os.path.join(BACKEND_DIR, ".graph_cache")

# --- Configuration & Defaults ---
# Moved from app.py to prevent circular imports during CLI/sync usage.
REGIONS = {
    "boulder": {
        "name": "Boulder",
        "bbox": (39.96, -105.30, 40.09, -105.18),
        "center": (40.015, -105.24),
        "default_zoom": 13,
        "capabilities": {"playgrounds": True, "official_routes": True},
        "build_priority": 0,
        "osm_cache_file": os.path.join(BACKEND_DIR, "boulder_osm_data.json"),
        "playgrounds_cache_file": os.path.join(BACKEND_DIR, "boulder_playground_data.json"),
        "stress_cache_file": os.path.join(BACKEND_DIR, "boulder_bike_stress_data.json"),
        "offstreet_cache_file": os.path.join(BACKEND_DIR, "boulder_bike_offstreet_data.json"),
        "playground_url": "https://opendata.arcgis.com/datasets/b1297c2328b343528f70dfd78c6de459_1.geojson",
        "stress_url": "https://opendata.arcgis.com/datasets/e20bc9b72c3b4d0fac167d722a7cf1b7_0.geojson",
        "offstreet_url": "https://opendata.arcgis.com/datasets/8cae0bbbd3154abe8264fa349b8f245f_0.geojson",
    },
    "broomfield": {
        "name": "Broomfield",
        "bbox": (39.88, -105.17, 40.03, -104.98),
        "center": (39.94, -105.075),
        "default_zoom": 13,
        "capabilities": {"playgrounds": False, "official_routes": True},
        "build_priority": 1,
        "osm_cache_file": os.path.join(BACKEND_DIR, "broomfield_osm_data.json"),
        "playgrounds_cache_file": None,
        "stress_cache_file": None,
        "offstreet_cache_file": os.path.join(BACKEND_DIR, "broomfield_bike_offstreet_data.json"),
        "playground_url": None,
        "stress_url": None,
        "offstreet_url": "https://services1.arcgis.com/vXSRPZbyyOmH9pek/arcgis/rest/services/Trails/FeatureServer/0/query?where=1%3D1&outFields=*&returnGeometry=true&outSR=4326&f=geojson",
    }
}

DEFAULT_WEIGHTS = {
    "separated_path": 0.5,
    "sharrow_minor": 1.5,
    "sidewalk": 2.0,
    "residential": 0.7,
    "busy_with_lane": 5.0,
    "busy_with_sharrow": 8.0,
    "busy_undesignated": 15.0,
    "sidewalk_forced": 6.0,
    "crossing_safe": 1.0,
    "crossing_unsafe": 6.0,
    "stress_low": 0.7,
    "stress_high": 2.0,
    "offstreet_multiuse": 0.8,
    "offstreet_soft_surface": 1.0,
    "ebike_restricted": 1.0,
    "facility_designated_route": 0.55,
    "facility_protected_lane": 0.20,
    "facility_onstreet_lane": 0.55,
    "facility_bikeable_shoulder": 0.65,
    "facility_contraflow": 0.45
}

# --- Cache Utilities ---

def hash_file(filepath):
    """Compute SHA-256 hash of a file in 64KB chunks to keep memory usage low."""
    if not filepath or not os.path.exists(filepath):
        return None
    sha256 = hashlib.sha256()
    try:
        with open(filepath, "rb") as f:
            for chunk in iter(lambda: f.read(65536), b""):
                sha256.update(chunk)
        return sha256.hexdigest()
    except Exception as e:
        print(f"[Cache] Error hashing file {filepath}: {e}")
        return None

def make_config_fingerprint(region_id, region_config, weights):
    """Generate a stable fingerprint from region configuration and default weights."""
    relevant_config = {
        "name": region_config.get("name"),
        "bbox": region_config.get("bbox"),
        "capabilities": region_config.get("capabilities"),
    }
    payload = {
        "region_id": region_id,
        "region_config": relevant_config,
        "weights": weights
    }
    dumped = json.dumps(payload, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(dumped.encode("utf-8")).hexdigest()

def get_cache_dir():
    """Get the target cache directory, prioritizing GRAPH_CACHE_DIR environment variable."""
    return os.environ.get("GRAPH_CACHE_DIR", GRAPH_CACHE_DIR)

def get_cache_path(region_id):
    """Get absolute path to the cached bundle file for a region."""
    return os.path.join(get_cache_dir(), f"{region_id}.graph-cache.pkl")

def save_graph_bundle(region_id, G, nodes, safe_crossings, four_lane_nodes, bike_routes_geojson, region_config, weights):
    """Atomically write the graph and companion state to a gzipped pickle cache bundle."""
    try:
        cache_dir = get_cache_dir()
        os.makedirs(cache_dir, exist_ok=True)
        cache_path = get_cache_path(region_id)
        
        # Capture current hashes for graph-affecting source files
        source_hashes = {}
        for key in ["osm_cache_file", "stress_cache_file", "offstreet_cache_file"]:
            filepath = region_config.get(key)
            if filepath:
                source_hashes[key] = hash_file(filepath)
            else:
                source_hashes[key] = None

        metadata = {
            "cache_format_version": GRAPH_CACHE_FORMAT_VERSION,
            "graph_build_version": GRAPH_BUILD_VERSION,
            "region_id": region_id,
            "created_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "python_version": sys.version_info[:2],
            "networkx_version": nx.__version__,
            "source_file_hashes": source_hashes,
            "node_count": G.number_of_nodes() if G is not None else 0,
            "edge_count": G.number_of_edges() if G is not None else 0,
            "config_fingerprint": make_config_fingerprint(region_id, region_config, weights),
        }

        bundle = {
            "G": G,
            "nodes": nodes,
            "safe_crossings": safe_crossings,
            "four_lane_nodes": four_lane_nodes,
            "bike_routes_geojson": bike_routes_geojson,
            "metadata": metadata
        }

        # Write to temporary file first to ensure atomicity
        fd, temp_path = tempfile.mkstemp(dir=cache_dir, suffix=".tmp")
        try:
            with os.fdopen(fd, "wb") as f_raw:
                with gzip.GzipFile(fileobj=f_raw, mode="wb") as f_gz:
                    pickle.dump(bundle, f_gz, protocol=pickle.HIGHEST_PROTOCOL)
                f_raw.flush()
                os.fsync(f_raw.fileno())
            os.replace(temp_path, cache_path)
            print(f"[Cache] Successfully serialized graph bundle for {region_id} to {cache_path}")
            return True, "success"
        except Exception as e:
            if os.path.exists(temp_path):
                try:
                    os.remove(temp_path)
                except Exception:
                    pass
            raise e
    except Exception as e:
        print(f"[Cache] Error saving graph bundle for {region_id}: {e}")
        return False, str(e)

def load_graph_bundle(region_id, region_config, weights):
    """Load and validate the graph cache bundle for a region.
    Returns (bundle, "hit" or miss_reason_string)."""
    cache_path = get_cache_path(region_id)
    if not os.path.exists(cache_path):
        return None, "cache_missing"

    try:
        with gzip.open(cache_path, "rb") as f:
            bundle = pickle.load(f)
    except Exception as e:
        print(f"[Cache] Failed to load/unpickle cache bundle for {region_id}: {e}")
        try:
            os.remove(cache_path)
        except Exception as remove_err:
            print(f"[Cache] Failed to delete corrupted cache file {cache_path}: {remove_err}")
        return None, f"pickle_load_failed: {str(e)}"

    metadata = bundle.get("metadata", {})

    # 1. Version validation
    if metadata.get("cache_format_version") != GRAPH_CACHE_FORMAT_VERSION:
        return None, f"format_version_mismatch: got {metadata.get('cache_format_version')}, expected {GRAPH_CACHE_FORMAT_VERSION}"
    if metadata.get("graph_build_version") != GRAPH_BUILD_VERSION:
        return None, f"build_version_mismatch: got {metadata.get('graph_build_version')}, expected {GRAPH_BUILD_VERSION}"

    # 2. Environment compatibility
    if tuple(metadata.get("python_version", [])) != sys.version_info[:2]:
        return None, f"python_version_mismatch: got {metadata.get('python_version')}, expected {sys.version_info[:2]}"
    if metadata.get("networkx_version") != nx.__version__:
        return None, f"networkx_version_mismatch: got {metadata.get('networkx_version')}, expected {nx.__version__}"

    # 3. Region metadata matching
    if metadata.get("region_id") != region_id:
        return None, f"region_id_mismatch: got {metadata.get('region_id')}, expected {region_id}"

    # 4. Configuration Fingerprint validation
    current_fingerprint = make_config_fingerprint(region_id, region_config, weights)
    if metadata.get("config_fingerprint") != current_fingerprint:
        return None, "config_fingerprint_mismatch"

    # 5. Content hash validation of every configured source file
    source_hashes = metadata.get("source_file_hashes", {})
    for key in ["osm_cache_file", "stress_cache_file", "offstreet_cache_file"]:
        filepath = region_config.get(key)
        expected_hash = source_hashes.get(key)
        if filepath:
            if not os.path.exists(filepath):
                return None, f"source_file_missing: {os.path.basename(filepath)}"
            current_hash = hash_file(filepath)
            if current_hash != expected_hash:
                return None, f"hash_mismatch for {os.path.basename(filepath)}"
        else:
            if expected_hash is not None:
                return None, f"source_file_config_mismatch for {key}"

    return bundle, "hit"

def invalidate_graph_cache(region_id):
    """Proactively remove the cached bundle for a region."""
    cache_path = get_cache_path(region_id)
    if os.path.exists(cache_path):
        try:
            os.remove(cache_path)
            print(f"[Cache] Proactively invalidated cache file: {cache_path}")
            return True, "invalidated"
        except Exception as e:
            print(f"[Cache] Failed to delete cache file {cache_path}: {e}")
            return False, str(e)
    return False, "no_cache_to_invalidate"
