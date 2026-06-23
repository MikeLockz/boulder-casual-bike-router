import unittest

import networkx as nx

import app as router
import sync_gis_data


class MultiRegionContractTests(unittest.TestCase):
    def setUp(self):
        self.client = router.app.test_client()
        self.original_graphs = dict(router.graphs_by_region)
        router.graphs_by_region.clear()
        for region_id, coordinate in {
            "boulder": (40.015, -105.24),
            "broomfield": (39.94, -105.075),
        }.items():
            graph = nx.DiGraph()
            graph.add_node("a", lat=coordinate[0], lon=coordinate[1])
            graph.add_node("b", lat=coordinate[0] + 0.001, lon=coordinate[1] + 0.001)
            graph.add_edge("a", "b", length=100.0, type="residential", tags={})
            graph.add_edge("b", "a", length=100.0, type="residential", tags={})
            router.graphs_by_region[region_id] = graph
            router.graph_build_statuses[region_id] = {**router.get_default_build_status(), "state": "ready"}

    def tearDown(self):
        router.graphs_by_region.clear()
        router.graphs_by_region.update(self.original_graphs)

    def route(self, start, end, region=None, waypoints=None, weights=None):
        payload = {
            "start_lat": start[0], "start_lon": start[1],
            "end_lat": end[0], "end_lon": end[1],
            "waypoints": waypoints or [],
            "weights": weights or router.DEFAULT_WEIGHTS,
        }
        if region is not None:
            payload["region"] = region
        return self.client.post("/api/route", json=payload)

    def test_outside_coordinate_has_no_fallback(self):
        self.assertIsNone(router.find_region_for_coordinate(0, 0))

    def test_each_region_routes_on_its_own_graph(self):
        for region_id, start in [("boulder", (40.015, -105.24)), ("broomfield", (39.94, -105.075))]:
            response = self.route(start, (start[0] + 0.001, start[1] + 0.001), region_id)
            self.assertEqual(response.status_code, 200)
            self.assertEqual(response.get_json()["region"], region_id)

    def test_cross_region_route_is_rejected(self):
        response = self.route((40.015, -105.24), (39.94, -105.075), "boulder")
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.get_json()["error"]["code"], "cross_region_route")

    def test_cross_region_waypoint_is_rejected(self):
        response = self.route(
            (40.015, -105.24),
            (40.016, -105.239),
            "boulder",
            waypoints=[[39.94, -105.075]],
        )
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.get_json()["error"]["code"], "cross_region_route")

    def test_unsupported_waypoint_is_rejected(self):
        response = self.route(
            (40.015, -105.24),
            (40.016, -105.239),
            "boulder",
            waypoints=[[0, 0]],
        )
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.get_json()["error"]["code"], "unsupported_coordinate")

    def test_explicit_region_mismatch_is_rejected(self):
        response = self.route((40.015, -105.24), (40.016, -105.239), "broomfield")
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.get_json()["error"]["code"], "region_mismatch")

    def test_request_weights_do_not_mutate_graph(self):
        graph = router.graphs_by_region["boulder"]
        before = dict(graph["a"]["b"])
        response = self.route(
            (40.015, -105.24),
            (40.016, -105.239),
            "boulder",
            weights={**router.DEFAULT_WEIGHTS, "residential": 9.0},
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(graph["a"]["b"], before)

    def test_region_health_is_independent(self):
        router.graphs_by_region.pop("broomfield")
        router.graph_build_statuses["broomfield"] = {**router.get_default_build_status(), "state": "error", "error": "fixture"}
        self.assertEqual(self.client.get("/api/health").status_code, 200)
        self.assertEqual(self.client.get("/api/health?region=broomfield").status_code, 503)

    def test_broomfield_trail_normalization_filters_and_maps_fields(self):
        base = {
            "geometry": {"type": "LineString", "coordinates": [[-105.05, 39.95], [-105.04, 39.96]]},
            "properties": {"STATUS": "EXISTING", "BAT_BIKE": "Yes", "TRAIL_TYPE": "Soft Surface Trail", "BAT_SURTYPE": "SoftSurface", "SITE_NAME": "Test Trail"},
        }
        normalized = sync_gis_data.normalize_broomfield_trail(base)
        self.assertEqual(normalized["properties"]["FACILITYTYPE"], "Soft Surface Trail")
        self.assertEqual(normalized["properties"]["COMFORT_CLASS"], "soft_surface")

        planned = {**base, "properties": {**base["properties"], "STATUS": "PLANNED"}}
        prohibited = {**base, "properties": {**base["properties"], "BAT_BIKE": "No"}}
        driveway = {**base, "properties": {**base["properties"], "TRAIL_TYPE": "Driveway"}}
        self.assertIsNone(sync_gis_data.normalize_broomfield_trail(planned))
        self.assertIsNone(sync_gis_data.normalize_broomfield_trail(prohibited))
        self.assertIsNone(sync_gis_data.normalize_broomfield_trail(driveway))

    def test_bike_edge_direction_honors_oneway_without_bicycle_exception(self):
        tags = {
            "highway": "residential",
            "name": "Grandview Avenue",
            "oneway": "yes",
        }
        self.assertEqual(router._bike_edge_direction(tags, "residential"), "forward")

    def test_bike_edge_direction_allows_explicit_bicycle_contraflow(self):
        tags = {
            "highway": "residential",
            "oneway": "yes",
            "cycleway": "opposite_lane",
        }
        self.assertEqual(router._bike_edge_direction(tags, "residential"), "both")

    def test_bike_edge_direction_allows_gis_contraflow_facility(self):
        tags = {
            "highway": "residential",
            "oneway": "yes",
            "cycleway": "shared_lane",
        }
        self.assertEqual(router._bike_edge_direction(tags, "residential", "Contra Flow Bike Lane"), "both")

    def test_nearby_contraflow_facility_is_detected(self):
        nodes = {
            "a": {"lat": 40.0170, "lon": -105.2782},
            "b": {"lat": 40.0180, "lon": -105.2786},
        }
        index = router.SpatialGridIndex(cell_size=0.001)
        index.add_segment(
            40.0170,
            -105.27825,
            40.0180,
            -105.27865,
            1,
            {"FACILITYTYPE": "Contra Flow Bike Lane"},
        )
        self.assertTrue(
            router.has_nearby_stress_facility_for_edge(
                "a", "b", nodes, index, "Contra Flow Bike Lane"
            )
        )

    def test_bike_edge_direction_honors_reverse_oneway(self):
        tags = {"highway": "service", "oneway": "-1"}
        self.assertEqual(router._bike_edge_direction(tags, "residential"), "reverse")


if __name__ == "__main__":
    unittest.main()
