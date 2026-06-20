import unittest
import os
import shutil
import tempfile
import sys
import gzip
import pickle
import networkx as nx
from unittest.mock import patch, MagicMock

import graph_cache
import app as router
import sync_gis_data

class GraphCacheTests(unittest.TestCase):
    def setUp(self):
        # Create a temporary directory for cache files
        self.test_dir = tempfile.mkdtemp()
        self.orig_cache_dir = graph_cache.GRAPH_CACHE_DIR
        graph_cache.GRAPH_CACHE_DIR = self.test_dir

        # Create temporary dummy files for hash tests
        self.temp_files = []

    def tearDown(self):
        # Clean up temporary cache dir
        shutil.rmtree(self.test_dir)
        graph_cache.GRAPH_CACHE_DIR = self.orig_cache_dir

        # Clean up dummy files
        for path in self.temp_files:
            if os.path.exists(path):
                os.remove(path)

    def create_dummy_file(self, content):
        fd, path = tempfile.mkstemp(dir=self.test_dir)
        with os.fdopen(fd, "w") as f:
            f.write(content)
        self.temp_files.append(path)
        return path

    def test_bundle_round_trip(self):
        """1. Valid bundle round-trip preserves graph topology, node ID types, edge attributes, sets, and derived GeoJSON."""
        G = nx.DiGraph()
        # Mix of integer and split-lane string node IDs
        G.add_node(1, lat=40.0, lon=-105.0)
        G.add_node("123_lane_1", lat=40.1, lon=-105.1)
        G.add_edge(1, "123_lane_1", length=10.0, type="separated_path", tags={"name": "Broadway Path"})
        G.add_edge("123_lane_1", 1, length=10.0, type="separated_path", tags={"name": "Broadway Path"})

        nodes = {
            1: {"lat": 40.0, "lon": -105.0, "tags": {"amenity": "bench"}},
            "123_lane_1": {"lat": 40.1, "lon": -105.1, "tags": {}}
        }
        safe_crossings = {1, "123_lane_1"}
        four_lane_nodes = {"123_lane_1"}
        bike_routes_geojson = {
            "type": "FeatureCollection",
            "features": [{
                "type": "Feature",
                "geometry": {"type": "LineString", "coordinates": [[-105.0, 40.0], [-105.1, 40.1]]},
                "properties": {"FACILITYTYPE": "Multi-Use Path"}
            }]
        }

        region_config = {
            "name": "Test Region",
            "bbox": (39.9, -105.2, 40.2, -104.9),
            "capabilities": {"playgrounds": True, "official_routes": True},
            "osm_cache_file": None,
            "stress_cache_file": None,
            "offstreet_cache_file": None,
        }
        weights = graph_cache.DEFAULT_WEIGHTS

        # Save the bundle
        success, reason = graph_cache.save_graph_bundle(
            "test_region", G, nodes, safe_crossings, four_lane_nodes, bike_routes_geojson, region_config, weights
        )
        self.assertTrue(success)
        self.assertEqual(reason, "success")

        # Load the bundle
        bundle, hit_reason = graph_cache.load_graph_bundle("test_region", region_config, weights)
        self.assertEqual(hit_reason, "hit")
        self.assertIsNotNone(bundle)

        # Assert round-trip correctness
        loaded_G = bundle["G"]
        self.assertEqual(list(loaded_G.nodes), list(G.nodes))
        self.assertEqual(loaded_G.nodes[1]["lat"], 40.0)
        self.assertEqual(loaded_G.nodes["123_lane_1"]["lat"], 40.1)
        self.assertEqual(loaded_G[1]["123_lane_1"]["length"], 10.0)
        self.assertEqual(loaded_G[1]["123_lane_1"]["type"], "separated_path")

        self.assertEqual(bundle["nodes"], nodes)
        self.assertEqual(bundle["safe_crossings"], safe_crossings)
        self.assertEqual(bundle["four_lane_nodes"], four_lane_nodes)
        self.assertEqual(bundle["bike_routes_geojson"], bike_routes_geojson)

        # Check metadata
        meta = bundle["metadata"]
        self.assertEqual(meta["region_id"], "test_region")
        self.assertEqual(meta["node_count"], 2)
        self.assertEqual(meta["edge_count"], 2)

    def test_hash_invalidation(self):
        """2. A changed OSM, stress, or off-street file hash causes a miss."""
        osm_path = self.create_dummy_file("osm_content")
        stress_path = self.create_dummy_file("stress_content")

        region_config = {
            "name": "Test Region",
            "bbox": (39.9, -105.2, 40.2, -104.9),
            "capabilities": {"playgrounds": True},
            "osm_cache_file": osm_path,
            "stress_cache_file": stress_path,
            "offstreet_cache_file": None,
        }
        weights = graph_cache.DEFAULT_WEIGHTS
        G = nx.DiGraph()

        # Save with original hashes
        graph_cache.save_graph_bundle(
            "test_region", G, {}, set(), set(), {}, region_config, weights
        )

        # Verify initial load is a hit
        bundle, hit_reason = graph_cache.load_graph_bundle("test_region", region_config, weights)
        self.assertEqual(hit_reason, "hit")

        # Mutate OSM file
        with open(osm_path, "w") as f:
            f.write("modified_osm_content")

        # Verify load is now a miss
        bundle, hit_reason = graph_cache.load_graph_bundle("test_region", region_config, weights)
        self.assertIsNone(bundle)
        self.assertTrue(hit_reason.startswith("hash_mismatch"))

    def test_version_fingerprint_invalidation(self):
        """3. A changed graph-build version, cache format version, region config fingerprint, default-weight fingerprint, Python compatibility marker, or NetworkX compatibility marker causes a miss."""
        region_config = {
            "name": "Test Region",
            "bbox": (39.9, -105.2, 40.2, -104.9),
            "capabilities": {"playgrounds": True},
            "osm_cache_file": None,
            "stress_cache_file": None,
            "offstreet_cache_file": None,
        }
        weights = graph_cache.DEFAULT_WEIGHTS
        G = nx.DiGraph()

        # Save base cache
        graph_cache.save_graph_bundle(
            "test_region", G, {}, set(), set(), {}, region_config, weights
        )

        # Change cache format version
        with patch("graph_cache.GRAPH_CACHE_FORMAT_VERSION", 999):
            bundle, hit_reason = graph_cache.load_graph_bundle("test_region", region_config, weights)
            self.assertIsNone(bundle)
            self.assertTrue(hit_reason.startswith("format_version_mismatch"))

        # Change graph build version
        with patch("graph_cache.GRAPH_BUILD_VERSION", 999):
            bundle, hit_reason = graph_cache.load_graph_bundle("test_region", region_config, weights)
            self.assertIsNone(bundle)
            self.assertTrue(hit_reason.startswith("build_version_mismatch"))

        # Change Python version info tuple
        with patch("sys.version_info", (2, 7)):
            bundle, hit_reason = graph_cache.load_graph_bundle("test_region", region_config, weights)
            self.assertIsNone(bundle)
            self.assertTrue(hit_reason.startswith("python_version_mismatch"))

        # Change NetworkX version
        with patch("networkx.__version__", "1.0"):
            bundle, hit_reason = graph_cache.load_graph_bundle("test_region", region_config, weights)
            self.assertIsNone(bundle)
            self.assertTrue(hit_reason.startswith("networkx_version_mismatch"))

        # Change config fingerprint (by changing weights)
        changed_weights = {**weights, "separated_path": 9.9}
        bundle, hit_reason = graph_cache.load_graph_bundle("test_region", region_config, changed_weights)
        self.assertIsNone(bundle)
        self.assertEqual(hit_reason, "config_fingerprint_mismatch")

    def test_missing_optional_source_files(self):
        """4. Missing optional source files are represented consistently and do not invalidate forever."""
        region_config = {
            "name": "Broomfield",
            "bbox": (39.88, -105.17, 40.03, -104.98),
            "capabilities": {"playgrounds": False},
            "osm_cache_file": None,
            "stress_cache_file": None,  # Broomfield has stress file set to None
            "offstreet_cache_file": None,
        }
        weights = graph_cache.DEFAULT_WEIGHTS
        G = nx.DiGraph()

        # Save cache
        graph_cache.save_graph_bundle(
            "broomfield", G, {}, set(), set(), {}, region_config, weights
        )

        # Load cache
        bundle, hit_reason = graph_cache.load_graph_bundle("broomfield", region_config, weights)
        self.assertEqual(hit_reason, "hit")
        self.assertIsNotNone(bundle)

    def test_corrupt_pickle_recovery(self):
        """5. Corrupt/truncated pickle data falls back to rebuild without crashing startup."""
        cache_path = graph_cache.get_cache_path("test_region")
        os.makedirs(os.path.dirname(cache_path), exist_ok=True)
        # Write garbage non-pickle data
        with open(cache_path, "wb") as f:
            f.write(b"garbage data")

        region_config = {
            "name": "Test Region",
            "bbox": (39.9, -105.2, 40.2, -104.9),
            "capabilities": {},
            "osm_cache_file": None,
            "stress_cache_file": None,
            "offstreet_cache_file": None,
        }

        # Verify load returns None but doesn't throw
        bundle, hit_reason = graph_cache.load_graph_bundle("test_region", region_config, graph_cache.DEFAULT_WEIGHTS)
        self.assertIsNone(bundle)
        self.assertTrue(hit_reason.startswith("pickle_load_failed"))
        # Cache file should be cleaned up/removed
        self.assertFalse(os.path.exists(cache_path))

    def test_atomic_save_failure(self):
        """6. Atomic save leaves the previous valid bundle intact if serialization fails before os.replace."""
        region_config = {
            "name": "Test Region",
            "bbox": (39.9, -105.2, 40.2, -104.9),
            "capabilities": {},
            "osm_cache_file": None,
            "stress_cache_file": None,
            "offstreet_cache_file": None,
        }
        weights = graph_cache.DEFAULT_WEIGHTS
        G = nx.DiGraph()

        # First, save a valid cache
        success, _ = graph_cache.save_graph_bundle("test_region", G, {}, set(), set(), {}, region_config, weights)
        self.assertTrue(success)

        # Mock pickle.dump to fail during next write
        with patch("pickle.dump", side_effect=Exception("Pickling error")):
            success, reason = graph_cache.save_graph_bundle(
                "test_region", G, {"new": "data"}, set(), set(), {}, region_config, weights
            )
            self.assertFalse(success)
            self.assertEqual(reason, "Pickling error")

        # Verify previous valid bundle is still intact and can be loaded
        bundle, hit_reason = graph_cache.load_graph_bundle("test_region", region_config, weights)
        self.assertEqual(hit_reason, "hit")
        self.assertNotIn("new", bundle["nodes"])

    def test_cache_write_failure_leaves_region_ready(self):
        """7. Cache-write failure still leaves the region ready in memory."""
        # Mock save_graph_bundle to fail
        with patch("app.save_graph_bundle", return_value=(False, "disk full")):
            # Clear test state
            router.graphs_by_region.clear()
            router.graph_build_statuses.clear()

            # Execute build graph (with mocks)
            with patch("app.fetch_osm_data", return_value={"elements": []}):
                router.build_graph("boulder")

            # Graph status should still be ready in memory
            status = router.get_graph_build_status("boulder")
            self.assertTrue(status["ready"])
            self.assertEqual(status["state"], "ready")
            self.assertIsNotNone(router.graphs_by_region.get("boulder"))

    def test_successful_build_reports_cache_creation_time(self):
        """8. A successful cold build exposes the cache publication timestamp."""
        router.graphs_by_region.clear()
        router.graph_build_statuses.clear()
        with patch("app.load_graph_bundle", return_value=(None, "cache_missing")), \
             patch("app.get_source_hashes", return_value={}), \
             patch("app.fetch_osm_data", return_value={"elements": []}), \
             patch("app.fetch_stress_data", return_value={"features": []}), \
             patch("app.fetch_offstreet_data", return_value={"features": []}), \
             patch("app.build_bike_routes_geojson", return_value={"type": "FeatureCollection", "features": []}), \
             patch("app.save_graph_bundle", return_value=(True, "success")):
            router.build_graph("boulder")

        status = router.get_graph_build_status("boulder")
        self.assertTrue(status["ready"])
        self.assertEqual(status["source"], "build")
        self.assertIsNotNone(status["cache_creation_time"])

    def test_sync_invalidation(self):
        """9. GIS sync invalidates only regions whose files were replaced, including partial-sync failure after one successful replacement."""
        # Write dummy files representing cached bundles
        for r_id in ["boulder", "broomfield"]:
            cache_path = graph_cache.get_cache_path(r_id)
            os.makedirs(os.path.dirname(cache_path), exist_ok=True)
            with open(cache_path, "wb") as f:
                f.write(b"dummy cache")

        # Verify both caches exist
        self.assertTrue(os.path.exists(graph_cache.get_cache_path("boulder")))
        self.assertTrue(os.path.exists(graph_cache.get_cache_path("broomfield")))

        # Test invalidating just boulder
        success, reason = graph_cache.invalidate_graph_cache("boulder")
        self.assertTrue(success)
        self.assertEqual(reason, "invalidated")
        self.assertFalse(os.path.exists(graph_cache.get_cache_path("boulder")))
        self.assertTrue(os.path.exists(graph_cache.get_cache_path("broomfield")))

        # Restore boulder dummy
        with open(graph_cache.get_cache_path("boulder"), "wb") as f:
            f.write(b"dummy cache")

        # Mock sync_boulder success but sync_broomfield failure
        def mock_sync_boulder(backend_dir, replaced_regions):
            replaced_regions.add("boulder")
            
        def mock_sync_broomfield(backend_dir, replaced_regions):
            replaced_regions.add("broomfield")
            raise Exception("Broomfield sync failed midway")

        with patch("sync_gis_data.sync_boulder", side_effect=mock_sync_boulder):
            with patch("sync_gis_data.sync_broomfield", side_effect=mock_sync_broomfield):
                with patch("argparse.ArgumentParser.parse_args", return_value=MagicMock(boulder=True, broomfield=True)):
                    with self.assertRaises(Exception):
                        sync_gis_data.main()

        # Due to partial failure, BOTH boulder and broomfield registered writes and must be invalidated
        self.assertFalse(os.path.exists(graph_cache.get_cache_path("boulder")))
        self.assertFalse(os.path.exists(graph_cache.get_cache_path("broomfield")))

    def test_source_change_during_save_does_not_replace_cache(self):
        """10. A source update during serialization leaves the previous cache intact."""
        osm_path = self.create_dummy_file("original")
        region_config = {
            "name": "Test Region",
            "bbox": (39.9, -105.2, 40.2, -104.9),
            "capabilities": {},
            "osm_cache_file": osm_path,
            "stress_cache_file": None,
            "offstreet_cache_file": None,
        }
        graph_cache.save_graph_bundle("test_region", nx.DiGraph(), {"old": True}, set(), set(), {}, region_config, graph_cache.DEFAULT_WEIGHTS)
        expected_hashes = graph_cache.get_source_hashes(region_config)
        original_dump = pickle.dump

        def mutate_source(*args, **kwargs):
            result = original_dump(*args, **kwargs)
            with open(osm_path, "w") as handle:
                handle.write("changed")
            return result

        with patch("pickle.dump", side_effect=mutate_source):
            success, reason = graph_cache.save_graph_bundle(
                "test_region", nx.DiGraph(), {"new": True}, set(), set(), {}, region_config,
                graph_cache.DEFAULT_WEIGHTS, expected_source_hashes=expected_hashes,
            )

        self.assertFalse(success)
        self.assertEqual(reason, "source_files_changed_during_build")
        with open(osm_path, "w") as handle:
            handle.write("original")
        bundle, hit_reason = graph_cache.load_graph_bundle("test_region", region_config, graph_cache.DEFAULT_WEIGHTS)
        self.assertEqual(hit_reason, "hit")
        self.assertEqual(bundle["nodes"], {"old": True})

    def test_reload_startup_gating(self):
        """11. Reload startup gating starts initialization in the serving child only."""
        self.assertTrue(router.should_start_graph_initialization(False, {}))
        self.assertFalse(router.should_start_graph_initialization(True, {}))
        self.assertTrue(router.should_start_graph_initialization(True, {"WERKZEUG_RUN_MAIN": "true"}))
        self.assertFalse(router.should_start_graph_initialization(True, {"WERKZEUG_RUN_MAIN": "false"}))

if __name__ == "__main__":
    unittest.main()
