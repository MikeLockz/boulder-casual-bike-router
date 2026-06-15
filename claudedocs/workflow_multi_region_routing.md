# Multi-Region Routing Support: Boulder and Broomfield

## Goal

Support Boulder and Broomfield as independent routing regions with separate graph data, build state, routing boundaries, and formal web/iOS client selection. A route must remain entirely inside one supported region. Requests that cross regions or include unsupported coordinates must fail with a clear `400 Bad Request` instead of snapping to the wrong graph.

## Current Repository State

The repository already contains a partial implementation that should be hardened rather than replaced:

- `backend/app.py` defines Boulder and Broomfield region configuration and stores graphs and derived data in per-region dictionaries.
- `/api/config` exposes regions, and route/crossing/playground/bike-route/edge-inspection endpoints accept a region.
- The backend currently builds both graphs sequentially at startup.
- `frontend/index.html` already contains a header region selector, but the required long-term location is Settings and there is no equivalent iOS control.
- `frontend/app.js` can switch regions, send the active region with route requests, and select a region after successful geolocation.
- No Broomfield OSM cache is currently checked into the repository. Broomfield off-street and official-route data can be sourced from the City and County of Broomfield public Trails Feature Service, but it is not yet integrated.
- There are no focused multi-region tests.

The current implementation has correctness gaps: coordinates outside all regions fall back to Boulder inside the backend membership helper; only the destination is checked for cross-region routing; waypoints are not checked; an explicitly supplied region is not verified against the start point; health only represents Boulder; startup blocks before Flask can expose build state; graph weights are mutated per request; and saved frontend state can conflict with the required startup auto-selection behavior.

## User Review Required

### 1. Region Selection Behavior

**Approved behavior:** determine the initial region from location once per application session. If location is unavailable, denied, fails, or is outside every supported bounding box, use Boulder. Add the region selector to Settings in both web and iOS. A manual selection overrides automatic selection for the remainder of that session only and resets on the next fresh application session.

- Web stores the override in `sessionStorage`, not `localStorage`.
- iOS stores the override in shared in-memory application state, not `UserDefaults` or SwiftData.
- Returning from background does not start a new session or replace a manual selection.
- A fresh browser tab/window or a cold iOS launch performs automatic location selection again.

### 2. Broomfield Comfort Data

**Approved source:** build the Broomfield base graph from OSM using the same fetch, cache, topology, crossing, classification, connected-component, and weighting pipeline as Boulder. Supplement it with the City and County of Broomfield Trails dataset:

- Dataset page: `https://opendata.broomfield.org/datasets/a3e0fb66f336431d8de7a72e143e2ee7_0/explore`
- ArcGIS item: `a3e0fb66f336431d8de7a72e143e2ee7`
- Feature layer: `https://services1.arcgis.com/vXSRPZbyyOmH9pek/arcgis/rest/services/Trails/FeatureServer/0`
- GeoJSON query: `/query?where=1%3D1&outFields=*&returnGeometry=true&outSR=4326&f=geojson`

The service is paginated with a 1,000-record transfer limit. The sync process must page deterministically until all records are retrieved, retain source metadata and retrieval time, and validate that the result is a non-empty WGS84 line dataset before replacing the last known-good cache.

Normalize Broomfield fields into the router's common off-street schema. At minimum, use `STATUS`, `BAT_BIKE`, `TRAIL_TYPE`, `BAT_SURTYPE`, `SITE_NAME`, and `ALTERNATE_NAME`. Include existing, bike-allowed trails; exclude planned/closed or bicycle-prohibited features; and map trail/surface types to explicit comfort modifiers through reviewed test fixtures. Boulder-specific GIS fields must not be assumed to exist in Broomfield data.

### 3. Graph Residency and RAM

**Recommended for two regions:** retain both independently built graphs in memory, build them sequentially, and measure node count, edge count, build duration, and process RSS. Put graph access behind a region manager so lazy loading, LRU eviction, or one backend process per region can be added later without changing the API.

Partitioning improves isolation and per-graph operations, but two eagerly resident graphs still consume approximately the sum of their memory. A hard RAM ceiling would require a lazy-loading or multi-process deployment decision.

## Target Design

### Region Definition

Create one canonical region registry in the backend. Each region record should include:

- Stable ID and display name.
- Bounding box and map center/default zoom.
- OSM cache path.
- Optional stress, off-street, playground, and official-route sources.
- Capability flags for UI features that are unavailable in a region.
- Build priority, with Boulder first.

Expose only frontend-safe metadata from `/api/config`; do not expose filesystem paths or source URLs.

### Region Resolution

Separate these concepts:

- `find_region_for_coordinate(lat, lon) -> region_id | None`: strict membership with no fallback.
- `default_region_id = "boulder"`: a UI/startup fallback only.
- `resolve_route_region(points, requested_region)`: validates the complete route request.

Every start, destination, and waypoint must belong to the same region. If the client supplies `region`, it must match every point. Coordinates outside all supported regions must be rejected rather than snapped to the nearest node in Boulder.

Use structured `400` responses with stable error codes:

- `invalid_region`
- `unsupported_coordinate`
- `cross_region_route`
- `region_mismatch`

Include a human-readable message and point/region details so web and native clients can present useful errors without parsing text.

### Graph Manager

Replace parallel global dictionaries with a small `RegionGraphState`/manager abstraction that owns, per region:

- Routing graph.
- Source nodes and crossing sets.
- Compiled bike-route GeoJSON.
- Build state and timestamps.
- Node/edge counts and last error.

The manager should provide validated lookup methods and prevent endpoint code from manually coordinating multiple dictionaries.

Do not mutate shared edge weights for each request. Use a NetworkX weight callback derived from request weights, precomputed immutable edge attributes, or a per-region lock as a temporary fallback. A callback is preferred because concurrent requests with different comfort profiles must not affect each other.

## Implementation Workflow

### Phase 1: Lock the Contract and Region Data

1. Add canonical Boulder and Broomfield metadata, including non-overlapping bounding boxes, map defaults, client display metadata, and capability flags.
2. Confirm Broomfield's production boundary and map center with representative coordinates near each edge.
3. Extend `backend/sync_gis_data.py` or add a region-data sync command that downloads Broomfield OSM for the configured bounding box using the same Overpass query and cache format as Boulder.
4. Fetch the Broomfield Trails FeatureServer in pages with `resultOffset`/`resultRecordCount`, `outSR=4326`, and `f=geojson`; merge pages into one validated `FeatureCollection`.
5. Normalize and cache Broomfield trails as `backend/broomfield_bike_offstreet_data.json`, preserving source attributes needed for debugging and future reclassification.
6. Generate and validate `backend/broomfield_osm_data.json`; commit both deterministic Broomfield caches alongside the Boulder caches so container startup does not depend on Overpass or ArcGIS availability.
7. Add source item ID, source URL, retrieval timestamp, feature count, bounds, and checksum to cache metadata or a companion manifest.
8. Add a `region` field to every preset instead of inferring ownership from route type or coordinates.
9. Require all maintained clients to send an explicit `region`; retain backend inference temporarily for backward compatibility and diagnostics.

**Checkpoint:** config output contains both regions, their capabilities, and region-tagged presets; Broomfield OSM and trail caches pass schema/bounds/count validation; and a clean production build does not depend on an unpredictable first-start network request.

### Phase 2: Harden Backend Region Isolation

1. Add strict coordinate parsing and region membership helpers.
2. Validate start, destination, and every waypoint before graph lookup or nearest-node matching.
3. Return structured `400` errors for cross-region, mismatched-region, invalid-region, and outside-region requests.
4. Include the resolved `region` in successful route responses, navigation route records, history API responses, and route analytics metadata.
5. Apply the same strict region lookup to `/api/inspect-edge`; keep query endpoints such as crossings and bike routes explicitly region-scoped.
6. Refactor graph and derived-data storage into the graph manager.
7. Replace request-time graph mutation in `update_graph_weights` with a concurrency-safe weight calculation.

**Checkpoint:** no request can use a graph whose region differs from any supplied route point, including waypoints and explicitly selected regions.

### Phase 3: Make Builds and Health Region-Aware

1. Start Flask before graph construction and run graph builds in a controlled background worker.
2. Build Boulder first, then Broomfield, to reduce peak build pressure and restore the default region quickly.
3. Keep `/api/graph-status` as an aggregate map keyed by region.
4. Extend `/api/health` to support `?region=<id>` and define aggregate readiness:
   - Default health checks Boulder readiness so the existing deployment can become available quickly.
   - Region-specific health returns `200` only when that region is ready.
   - The payload always reports every region's state for diagnostics.
5. Return `503` with the region's current build state when a valid route request targets a graph that is still building or failed.
6. Add build metrics to logs: cache source, duration, nodes, edges, and process RSS after each region.
7. Update Docker health checks and startup documentation to use the intended readiness contract.

**Checkpoint:** health and graph-status endpoints are reachable while graphs build, Boulder can become ready before Broomfield, and a Broomfield failure does not make Boulder routing unavailable.

### Phase 4: Add Formal Web Region Support

1. Load `/api/config` before choosing or rendering the active region.
2. Run one startup region-selection flow only when no session override exists:
   - Geolocation inside a region selects that region.
   - Outside all regions selects Boulder.
   - Permission denial, timeout, unavailable location, or unsupported geolocation selects Boulder.
3. Replace `localStorage.active_routing_region` with a session-only override in `sessionStorage`.
4. Move the primary region selector into Settings. The current header control should be removed or reduced to a read-only active-region label so there is one authoritative editing surface.
5. Populate the Settings selector from backend metadata and keep it synchronized with automatic and manual changes.
6. On manual switching, clear route markers, waypoints, route details, crossing layers, official-route layers, autocomplete results, and region-specific destination caches before fitting the new bounds.
7. Add a switch generation/request token so delayed Boulder requests cannot overwrite Broomfield data after a rapid toggle.
8. Filter presets by their explicit `region` field.
9. Load Broomfield's normalized Trails data through the existing official-routes endpoint and legend, with region-appropriate labels and styles.
10. Use capability flags to hide or explain genuinely unavailable region features such as playground destinations rather than showing empty controls.
11. Validate map clicks, search results, home locations, and current-location route points against the active region before requesting a route. Offer to switch regions when a point belongs to the other supported region.
12. Send `region` on route, crossing, playground, bike-route, inspect-edge, analytics, and navigation creation requests where applicable.
13. Present backend `cross_region_route` and `unsupported_coordinate` errors in the planner UI without a generic browser alert.

**Checkpoint:** web startup behavior matches the requirement in every permission state, the Settings selector lasts only for the browser session, Broomfield trails render and influence routing, and cross-region selections are blocked with a clear explanation.

### Phase 5: Add Formal iOS Region Support

1. Add a shared `RoutingRegion` model decoded from `/api/config`, including ID, name, bounds, map defaults, and capabilities.
2. Add one app-wide region session state owned above `MapViewModel` so Settings, planner, map, routes, history, and API services observe the same active region.
3. On cold launch, request/use location once after config loads. Select the containing region or Boulder on denial, failure, timeout, or outside-region location.
4. Add a Region row/picker to `SettingsTabView`. A manual choice updates in-memory session state and must not be written to `UserDefaults`, SwiftData, or synced settings.
5. Preserve the manual choice across tab changes and background/foreground transitions. Reset it only when a new app process/session begins.
6. On region change, cancel in-flight region requests; clear planned route, waypoints, selected playground, cached playgrounds/presets/overlays, and region-specific errors; then move the map to the new region bounds.
7. Update `APIService` request models so route, config-dependent resources, analytics, and navigation creation carry the explicit active region.
8. Filter iOS presets and destination resources by region, and expose Broomfield trails/official routes using the same normalized backend endpoint as web.
9. Validate current location, dropped pins, search results, Home, and history `View on Map` against the active region. A historical route should switch the current session to its stored region after user confirmation when necessary.
10. Decode structured backend region errors into typed Swift errors and show actionable UI rather than generic routing failures.
11. Add `region` to local navigation models and sync payloads so route history preserves where a route belongs. Provide a Boulder default only for legacy records whose coordinates resolve to Boulder; otherwise infer and backfill safely.

**Checkpoint:** iOS can automatically enter Broomfield, manually switch regions from Settings for the app session, plan and navigate Broomfield routes, display Broomfield trails, and preserve region identity in history/sync.

### Phase 6: Compatibility and Data Migration

1. Keep `region` optional in the backend route API during one compatibility window, while web and iOS always send it.
2. Add a PocketBase migration for `navigation_routes.region` and any analytics collection fields that require explicit region filtering.
3. Backfill existing navigation routes by resolving stored start coordinates against canonical bounds; log unresolved or ambiguous records instead of forcing them to Boulder.
4. Update navigation sync conflict handling so region is immutable after route creation except during the controlled legacy backfill.
5. Keep Watch navigation snapshots region-neutral unless the watch initiates routing; ensure snapshots continue to render routes created in either region.

**Checkpoint:** existing Boulder web and iOS routing behavior remains backward compatible.

### Phase 7: Tests and Quality Gates

#### Backend Unit Tests

- Boundary inclusion for each side of both bounding boxes.
- Outside-all-regions returns `None`, not Boulder.
- Invalid coordinates and unknown region IDs.
- Boulder-to-Boulder and Broomfield-to-Broomfield requests succeed with fixture graphs.
- Boulder-to-Broomfield and Broomfield-to-Boulder requests return `400 cross_region_route`.
- A waypoint in another region returns `400 cross_region_route`.
- An outside-region waypoint returns `400 unsupported_coordinate`.
- Explicit region conflicting with the start or destination returns `400 region_mismatch`.
- A building or failed target graph returns region-specific `503` data.
- Concurrent requests with different weight profiles do not mutate each other's results.
- Broomfield Trails pagination retrieves every page and rejects partial/empty replacement data.
- Trail normalization includes only existing bike-allowed features and maps reviewed trail/surface types correctly.

#### Frontend Tests and Browser Verification

- Mock location in Boulder selects Boulder.
- Mock location in Broomfield selects Broomfield.
- Mock location outside both selects Boulder.
- Denied and timed-out geolocation select Boulder.
- A web manual selection survives reloads in the same tab session but not a fresh session.
- Manual selector switching resets route state and reloads only target-region resources.
- Rapid switching does not display stale crossings, playgrounds, or official routes.
- Cross-region start/destination attempts show the intended message.
- Broomfield unavailable capabilities are hidden or explained.
- Existing Boulder presets, custom routes, navigation start, history view-on-map, and debug edge inspection still work.

#### iOS Tests and Simulator Verification

- Location in Boulder/Broomfield/outside selects Boulder/Broomfield/Boulder respectively on cold launch.
- Manual Settings selection survives tab changes and backgrounding but not process termination and relaunch.
- Region changes cancel stale tasks and clear region-specific planner resources.
- Broomfield route planning, official trail display, navigation start/end, sync, and history detail work end to end.
- Cross-region Home, search, pin, and history interactions produce the intended switch prompt or validation error.
- Legacy Boulder history records remain readable after the region migration.

#### Routing Quality Sampling

- Select representative short, medium, and arterial-crossing routes in each region.
- Inspect OSM tags, selected facilities, crossing behavior, detours, and endpoint snap distance.
- Establish acceptable maximum endpoint snap distance and reject requests beyond it to prevent boundary snapping.
- Record graph node/edge counts, build duration, route latency, and RSS for Boulder-only and both-region startup.

**Checkpoint:** automated contract tests, browser scenarios, and iPhone 17 Pro simulator scenarios pass, and sampled Broomfield routes meet the agreed comfort threshold.

### Phase 8: Documentation and Rollout

1. Update `README.md`, `AGENTS.md`, local startup instructions, and API examples for region-aware routing and health.
2. Document cache generation/refresh procedures independently for each region, including the exact Broomfield ArcGIS item/service IDs, pagination, WGS84 conversion, validation, and last-known-good replacement behavior.
3. Rebuild the backend container so production cannot run stale single-region code.
4. Deploy with Boulder as the default and verify both graph states through the proxied public host.
5. Run production smoke routes wholly inside each region and verify cross-region requests return the expected `400` payload.
6. Monitor build time, RSS, route error rate by region, endpoint snap distance, and Broomfield route feedback.
7. If measured RSS exceeds the deployment budget, move the graph manager to lazy loading with bounded eviction or deploy one backend process per region behind the existing API proxy.

## Dependencies and Execution Order

1. Region boundaries, Broomfield data policy, and selection precedence must be approved first.
2. Backend strict resolution and graph-manager work can proceed once region metadata is fixed.
3. Web and iOS startup/Settings selector work depends on the finalized `/api/config` shape, session semantics, and error contract.
4. Health/deployment changes depend on the graph manager's build-state API.
5. Routing quality validation depends on a deterministic Broomfield cache.
6. Production rollout occurs only after backend contract tests, frontend browser verification, and iOS simulator verification pass.

Backend graph work and web/iOS Settings UI can proceed in parallel after the API/config contract and shared session semantics are fixed. Data-quality sampling can run in parallel with client implementation once the Broomfield OSM and trail caches are deterministic.

## Definition of Done

- Boulder and Broomfield have independent graph, derived-data, and build state.
- Startup selects the user's containing region, with Boulder as the exact fallback outside all regions or when location is unavailable.
- Web and iOS automatically select the initial region and provide a Settings selector whose manual override lasts only for the current application session.
- Both maintained clients explicitly send the active region and support Broomfield planning, navigation, overlays, history, and errors.
- Every route point is validated against one region before nearest-node matching.
- Cross-region routes return a stable, clean `400 Bad Request` response.
- Broomfield uses the same OSM graph-processing pipeline as Boulder and integrates the official Broomfield Trails Feature Service as normalized off-street comfort and overlay data.
- Health and diagnostics expose per-region readiness and failures.
- Concurrent custom-weight requests are isolated.
- Existing Boulder web and iOS behavior remains functional.
- Broomfield cache, build performance, memory use, and representative route quality are verified before production release.
