# Backend Graph Serialization, Cache Invalidation, and Hot Reloading

## Goal

Avoid rebuilding every regional NetworkX routing graph on each backend startup when the OSM/GIS inputs and graph-building implementation are unchanged. Persist the complete runtime graph state per region, invalidate it safely when source data changes, and enable development hot reloading without duplicate background graph builds.

## Current State

- `backend/app.py` builds Boulder and Broomfield graphs sequentially in a background thread.
- A usable region consists of more than `nx.DiGraph`: endpoints also depend on `nodes_by_region`, `safe_crossings_by_region`, `four_lane_nodes_by_region`, and `bike_routes_geojson_by_region`.
- Source data is read from the region-specific OSM, stress, off-street, and playground JSON files configured in `REGIONS`.
- `backend/sync_gis_data.py` atomically replaces GIS JSON files but does not invalidate a constructed graph.
- Flask currently runs with `debug=True` and `use_reloader=False`. Enabling the reloader directly would execute startup code in both the Werkzeug supervisor and serving child, risking duplicate graph-build threads.
- Docker copies the backend into the image and has no persistent graph-cache volume, so a cache written inside a container would be lost on forced recreation.

## Design Decisions

### Cache Unit

Store one versioned cache bundle per region, for example `boulder.graph-cache.pkl` and `broomfield.graph-cache.pkl`. The bundle must contain:

- The fully constructed, connected `nx.DiGraph`, including split-lane nodes, crossing edges, matched GIS attributes, lengths, tags, and default weights.
- Raw OSM node metadata used by edge inspection and nearest-node diagnostics.
- Safe-crossing and four-lane node sets.
- Compiled official bike-route GeoJSON.
- Metadata: cache format version, graph-build version, region ID, creation time, Python and NetworkX versions, source-file SHA-256 hashes, node/edge counts, and the graph-affecting region/default configuration fingerprint.

Use Python pickle for the trusted local artifact, optionally wrapped in gzip if measurements show worthwhile disk savings. Do not load cache files from user-controlled paths. NetworkX JSON formats are not preferred because they add conversion cost and can lose Python attribute types.

### Validation and Invalidation

Use both mechanisms:

1. **Content validation on every load:** stream-hash every configured input file that affects the region and compare it with bundle metadata. Include an explicit `GRAPH_CACHE_FORMAT_VERSION` and `GRAPH_BUILD_VERSION`; bump the build version whenever topology, matching, crossing, classification, or serialized derived-state logic changes.
2. **Proactive invalidation after sync writes:** `sync_gis_data.py` deletes the affected region's graph bundle whenever it replaces any source file. Hash validation remains the correctness backstop for manual edits, Git pulls, OSM cache replacement, or interrupted syncs.

Do not use modification times as the validity contract. Git checkouts, Docker copies, and restored files can preserve misleading timestamps.

### Atomicity and Failure Behavior

- Write cache bundles to a temporary file in the same directory, flush/fsync, then publish with `os.replace`.
- Create the cache directory on demand.
- Treat missing, stale, truncated, incompatible, or unpickling-failed bundles as cache misses. Log the reason, remove the bad artifact when safe, and rebuild from source JSON.
- Publish the bundle only after the graph and all companion state have been fully constructed and installed successfully.
- A cache-write failure must not make a successfully built in-memory graph unavailable.

### Hot Reload Scope

Hot reload is a local-development feature only. Production must run with the debugger and reloader disabled.

- Add environment-controlled `BACKEND_DEBUG` and `BACKEND_RELOAD` flags.
- Start the graph-loading/building thread only in the actual serving process. When reload is enabled, gate startup with `WERKZEUG_RUN_MAIN == "true"`; without reload, start normally.
- Keep graph initialization idempotent so tests and alternate launchers can invoke it explicitly.
- Mount backend source into the local Docker service so Python changes are visible without rebuilding the image.
- Persist serialized graph artifacts in a Docker volume outside the source bind mount.

## Implementation Workflow

### Phase 1: Introduce a Cache Module and Contract

1. Add `backend/graph_cache.py` so cache path, hashing, metadata validation, atomic serialization, and invalidation are shared without importing the Flask application from the GIS sync script.
2. Define `GRAPH_CACHE_FORMAT_VERSION` and `GRAPH_BUILD_VERSION` constants and document when each must change.
3. Add `GRAPH_CACHE_DIR`, defaulting to `backend/.graph_cache` for direct local runs and overridable in Docker.
4. Implement a canonical list of graph-affecting files for each region from `REGIONS`: OSM, stress, and off-street caches. Include playground data only if it becomes part of the serialized bundle; otherwise continue loading playgrounds independently.
5. Hash file contents in chunks and create a stable fingerprint for relevant region configuration and `DEFAULT_WEIGHTS` using sorted JSON.
6. Implement `load_graph_bundle`, `save_graph_bundle`, and `invalidate_graph_cache` with explicit result/reason data for logging and status reporting.

**Checkpoint:** a fixture bundle round-trips a graph containing integer and split-lane string node IDs, sets, nested tags, GIS attributes, and GeoJSON without type or value loss.

### Phase 2: Integrate Cache-First Startup

1. Split the current `build_graph` orchestration into clear stages: mark loading/building state, attempt cache load, construct from source on miss, install region state, and persist after a successful build.
2. On a valid hit, install the graph and every companion object into `RegionGraphManager` before marking the region ready.
3. On a miss, retain the existing graph-construction algorithm unchanged, then serialize its final connected graph and companion state.
4. Ensure the normal build path returns or installs one complete region bundle rather than updating several global dictionaries at unrelated points.
5. Extend graph status with `source` (`cache` or `build`), `cache_hit`, cache validation/miss reason, cache creation time, and load/build duration. Do not expose sensitive filesystem paths through public APIs.
6. Log region ID, source hashes/fingerprint prefix, cache load duration, node/edge counts, and rebuild reason.

**Checkpoint:** first startup builds and writes one bundle per region; second startup reaches ready state from those bundles and produces equivalent route, inspection, crossings, and official-route responses.

### Phase 3: Connect GIS Sync to Invalidation

1. Import only the cache helper and a small region-to-source mapping in `backend/sync_gis_data.py`; do not import `app.py` or trigger Flask globals.
2. Track whether any file for a region was replaced. Invalidate that region's graph cache in a `finally` path once the first replacement occurs, so a later download/write failure cannot leave a cache claiming to represent partially updated source files.
3. Keep the current last-known-good JSON validation and atomic replacement behavior.
4. Print a clear invalidation result for each selected region, including the no-existing-cache case.
5. Add an optional `--no-invalidate-graph-cache` only if a concrete operational need appears; default behavior must always invalidate.

**Checkpoint:** syncing Boulder removes only Boulder’s graph bundle; syncing Broomfield removes only Broomfield’s; the next backend start rebuilds only invalidated or fingerprint-mismatched regions.

### Phase 4: Enable Development Hot Reloading

1. Refactor backend startup into `start_graph_initialization()` and `run_server()` helpers.
2. Parse `BACKEND_DEBUG` and `BACKEND_RELOAD` with strict boolean handling; default both to false in application code.
3. Under `__main__`, launch graph initialization only when reload is disabled or `WERKZEUG_RUN_MAIN` identifies the serving child.
4. Call `app.run(..., debug=debug_enabled, use_reloader=reload_enabled)` and log the active mode.
5. Update `start.sh` to set local development flags explicitly and preserve clean child-process shutdown when Ctrl-C terminates the Werkzeug supervisor.
6. Add a local Compose override or development-specific service configuration that:
   - Sets `BACKEND_DEBUG=1`, `BACKEND_RELOAD=1`, and `GRAPH_CACHE_DIR=/app/.cache/graphs`.
   - Bind-mounts `./backend:/app/backend`.
   - Mounts a named graph-cache volume at `/app/.cache/graphs`.
7. Keep the production image/compose command with reload disabled. Add a persistent production graph-cache volume because `--force-recreate` otherwise discards generated bundles on every deployment.
8. Confirm cache writes do not trigger reload loops; do not configure the cache directory as an extra watched path.

**Checkpoint:** editing `backend/app.py` causes exactly one serving child restart and one cache load/build sequence. No duplicate graph builder appears in logs, and production configuration never enables Werkzeug debug mode.

### Phase 5: Tests and Verification

#### Unit Tests

- Valid bundle round-trip preserves graph topology, node ID types, edge attributes, sets, and derived GeoJSON.
- A changed OSM, stress, or off-street file hash causes a miss.
- A changed graph-build version, cache format version, region config fingerprint, default-weight fingerprint, Python compatibility marker, or NetworkX compatibility marker causes a miss.
- Missing optional source files are represented consistently and do not invalidate forever.
- Corrupt/truncated pickle data falls back to rebuild without crashing startup.
- Atomic save leaves the previous valid bundle intact if serialization fails before `os.replace`.
- Cache-write failure still leaves the region ready in memory.
- GIS sync invalidates only regions whose files were replaced, including partial-sync failure after one successful replacement.
- Reload startup gating starts initialization in the serving child only.

#### Integration Tests

1. Start with an empty graph-cache directory and record build durations plus graph node/edge counts.
2. Restart without source changes and verify `source=cache`, matching counts, and materially lower readiness time.
3. Run one representative route and `/api/inspect-edge` per region before and after serialization; compare geometry, segment metadata, and costs.
4. Run `sync_gis_data.py --broomfield`, verify only its bundle disappears, restart, and confirm Boulder loads while Broomfield rebuilds.
5. Modify a copied fixture source file without calling the sync script and verify hash validation still forces rebuild.
6. In local Docker, edit a Python file and confirm reload through `http://localhost:8081/api/graph-status`; verify one builder sequence and successful proxied routing after readiness.
7. Recreate the backend container and verify the named volume allows cache hits across container lifetimes.

#### Performance Acceptance

- Record cold build time, warm cache-load time, artifact size, peak RSS, and ready time per region.
- Warm startup should avoid JSON parsing, spatial matching, lane splitting, connected-component construction, and bike-route compilation.
- Cache loading must not increase steady-state graph memory materially beyond the existing in-memory representation.

### Phase 6: Documentation and Rollout

1. Update `README.md` with cache location, invalidation behavior, manual cache removal, development reload commands, and production flags.
2. Update `AGENTS.md` startup guidance: backend code changes reload automatically only in configured development modes; source-data or graph-algorithm changes may rebuild graphs.
3. Add `backend/.graph_cache/` and temporary cache files to `.gitignore`; never commit pickle artifacts.
4. Deploy with an empty persistent graph-cache volume, wait for both regions to build once, restart the service, and confirm both regions report cache hits.
5. Verify `/api/health`, `/api/health?region=broomfield`, `/api/graph-status`, and representative production routes through `https://boulder.lockdev.com`.
6. Keep raw OSM/GIS JSON as the source of truth. Serialized graph bundles are disposable derived artifacts and must never be the only copy of routing data.

## Dependencies and Execution Order

1. Define the bundle schema, input fingerprint, and versioning contract first.
2. Implement serialization and tests before changing startup orchestration.
3. Integrate GIS invalidation after the shared cache helper exists.
4. Add reload process gating before enabling `use_reloader` anywhere.
5. Add Docker source/cache mounts after cache paths and reload flags are stable.
6. Measure warm startup and perform local integration checks before production rollout.

Phases 3 and the Docker portion of Phase 4 can proceed in parallel after Phase 1. Cache-first startup and reload gating both modify `backend/app.py` and should be integrated sequentially to avoid process-lifecycle regressions.

## Definition of Done

- Each configured region can load a complete, validated runtime bundle without rebuilding its graph.
- Any graph-affecting source-file change or graph-build version change forces only the affected region to rebuild.
- GIS sync proactively invalidates affected bundles, including partial update failures.
- Corrupt or incompatible caches degrade to a normal rebuild rather than backend failure.
- Cache writes are atomic and cache artifacts persist across Docker container recreation.
- Local direct and Docker development modes hot reload backend Python changes with exactly one graph initialization per serving process.
- Production runs with debug/reload disabled.
- Warm-start API behavior matches cold-build behavior for routing and graph-derived endpoints.
