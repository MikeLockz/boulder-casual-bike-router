# Agent Memory: Boulder Bike Router

Use this file as the first stop in fresh chats. It captures durable context from prior Boulder Bike Router chats plus the current repo state.

## Project Identity

- Repo/workspace: `/Users/mbp/.gemini/antigravity/scratch/boulder-bike-router`.
- GitHub repo discussed in prior chats: `MikeLockz/boulder-casual-bike-router`.
- Product: Boulder casual cycling router for comfortable routes, safe crossings, playground/loop routing, navigation history, and iOS/web clients.
- Public production host from prior chats and current iOS code: `https://boulder.lockdev.com`.
- There is a Codex project/thread cluster for this repo. In fresh Codex chats, use `list_threads` with query `boulder` and `read_thread` for recent project memory before relying only on this file.

## Codex Project History

- Recent Codex project threads include:
  - `Align route history and settings`
  - `Fix history route detail UI`
  - `Add home location settings`
  - `Fix route history metrics`
  - `Investigate route metrics mismatch`
  - `Test iOS route navigation`
  - `Plan route history CRUD`
  - `Plan route weights CRUD sync`
- Shared product IA decision: web and iOS should align on primary destinations `Plan`, `Routes`, `History`, and `Settings`; debug tools must be isolated from normal UI and shown only through debug/simulator affordances.
- Web IA was refactored so `Plan`, `Routes`, `History`, `Settings`, and debug are separate surfaces. History `View on Map` returns to `Plan`; debug street inspection is gated behind debug mode.
- iOS History route detail flow was fixed so `View on Map` can show the map while keeping `History` active in the bottom tab, and the map banner button is `Back`, returning to the route detail. History list shows start/end coordinates; route detail preview uses a non-interactive map instead of a placeholder.
- Home location was added as authenticated per-user settings via `/api/settings/home` backed by PocketBase `user_configs`. Both web and iOS have Home settings/editing flows.
- Home route semantics were debated and changed: Home shortcut should usually mean route from current location to Home, not from Home. Later route planner controls added Home as the middle icon in both start and destination rows, so check current code before assuming exact semantics.
- A CORS/stale-container issue happened locally: source had correct CORS headers, but the running Docker backend was stale. Rebuild/recreate backend if browser preflight errors show missing `Authorization` or missing newer endpoints.
- Flask debug reloader caused slow/double graph initialization in Docker; backend startup was patched to avoid the reloader loop.
- A server route metric investigation found route `pfp2a86n43myb4q` had clean GeoJSON/planned distance but 69,341 ticks across 27.65 h, accumulating 209.93 mi from a stale active session near the destination. The bug class is session lifecycle/GPS jitter, not route geometry.

## Architecture

- Backend: Flask app in `backend/app.py`, Python 3.11 in Docker, NetworkX routing graph, cached Boulder OSM/GIS JSON files.
- Web frontend: static Leaflet-style app in `frontend/`, served by nginx in Docker or `python -m http.server` locally.
- iOS app: Swift/SwiftUI project under `ios/BoulderBikeRouter/`; simulator defaults to `http://localhost:8081`, device/prod defaults to `https://boulder.lockdev.com`.
- Persistence/auth/config: PocketBase `ghcr.io/muchobien/pocketbase:0.39.1`, local data in `./pb_data`, schema in `pb_migrations/`.
- Local Docker services: `pocketbase` on `8090`, Flask backend on `3001`, nginx frontend on `8081`.
- nginx proxies `/api/` to `boulder-backend:3001/api/` and `/pb/` to `pocketbase:8090/`.

## Prior Chat Deployment Decisions

- Target server: NUC10 behind Proxmox, reachable over Tailscale/SSH as `root@100.127.44.82`.
- Desired deployment style: add containers to existing docker compose stack on the host; build from GitHub source directly, no Docker Hub publishing.
- Domain: `boulder.lockdev.com`; user handles DNS/ingress routing manually across multiple ingress servers.
- Traefik labels were expected on service definitions. Prior frontend example used:
  - `traefik.enable=true`
  - `traefik.http.middlewares.boulder.compress=true`
  - `traefik.http.routers.boulder.entrypoints=web,websecure`
  - `traefik.http.routers.boulder.rule=Host(\`boulder.lockdev.com\`)`
  - `traefik.http.services.boulder.loadbalancer.server.port=3012`
  - `com.centurylinklabs.watchtower.enable=true`
- Backend does not need a separate public domain if nginx frontend proxies `/api/` and `/pb/`; expose one public app host unless a native client must call backend/PocketBase directly.
- Cert issue history: browser showed `boulder.lockdev.com` as insecure; fix is on ingress/Traefik certificate issuance and DNS/routing, not Flask app code.

## CI/CD

- GitHub Actions workflow: `.github/workflows/deploy.yml`.
- Trigger: push to `main`.
- Steps:
  - `tailscale/github-action@v2` with secrets `TS_OAUTH_CLIENT_ID`, `TS_OAUTH_SECRET`, and tags `tag:deploy`.
  - `appleboy/ssh-action@v1.0.3` to host `100.127.44.82`, username `root`, key `${{ secrets.SSH_PRIVATE_KEY }}`, script `/opt/boulder-casual-bike-router/update.sh`.
- Prior chat noted a failed run: `https://github.com/MikeLockz/boulder-casual-bike-router/actions/runs/26962162741`.
- Tailscale OAuth client setup was a sticking point. The OAuth client needs device auth-key scope permission and should be allowed to use the tag `tag:deploy` in the tailnet ACL/tag owner setup.
- `update.sh` expects repo at `/opt/boulder-casual-bike-router` and compose working dir `/root/lockdev-home`; it resets local changes, pulls GitHub, then runs `docker compose up -d --build --force-recreate boulder-backend boulder-frontend`.

## Local Run Commands

- Recommended local start: `./start.sh`; uses `./venv/bin/python3`, writes `backend.log` and `frontend.log`, opens `http://localhost:8081`.
- Manual backend: `./venv/bin/python3 backend/app.py` or `python backend/app.py` after activating venv.
- Manual frontend: `./venv/bin/python3 -m http.server 8081 --directory frontend`.
- Docker stack: `docker compose up -d --build`.
- PocketBase health through backend: `curl http://localhost:3001/api/pocketbase-status`.
- Full proxied app locally: `http://localhost:8081`; direct backend: `http://localhost:3001`; PocketBase admin/API: `http://localhost:8090`.

## Xcode, Simulator, And iPhone Runs

- Xcode project: `ios/BoulderBikeRouter/BoulderBikeRouter.xcodeproj`.
- Scheme: `BoulderBikeRouter`.
- Open in Xcode: `open ios/BoulderBikeRouter/BoulderBikeRouter.xcodeproj`.
- Before running the iOS simulator against local services, start the local web/backend stack first with `./start.sh` or `docker compose up -d --build`.
- Simulator API base URL is compiled as `http://localhost:8081`, so simulator builds should hit the local nginx proxy directly.
- Physical iPhone/device API base URL is compiled as `https://boulder.lockdev.com`; a real phone will not use Mac `localhost` unless the code's base URL is overridden or changed.
- List available simulators: `xcrun simctl list devices available`.
- Current known available simulator names include `iPhone 16`, `iPhone 16 Pro`, `iPhone 16 Pro Max`, and a booted `iPhone 17 Pro`. If a note says `iphone60`, treat it as likely shorthand/typo for the `iPhone 16` simulator and verify with `simctl`.
- Build for iPhone 16 simulator:
  ```bash
  xcodebuild -project ios/BoulderBikeRouter/BoulderBikeRouter.xcodeproj -scheme BoulderBikeRouter -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16' build
  ```
- Run tests on simulator:
  ```bash
  xcodebuild test -project ios/BoulderBikeRouter/BoulderBikeRouter.xcodeproj -scheme BoulderBikeRouter -destination 'platform=iOS Simulator,name=iPhone 16'
  ```
- If the named simulator is unavailable, use a listed device UUID:
  ```bash
  xcodebuild -project ios/BoulderBikeRouter/BoulderBikeRouter.xcodeproj -scheme BoulderBikeRouter -destination 'platform=iOS Simulator,id=<SIMULATOR-UUID>' build
  ```
- For a physical iPhone, use Xcode's device picker, signing team settings, and the `BoulderBikeRouter` scheme. Check that `https://boulder.lockdev.com/api/config` is reachable from the phone before debugging app code.

## Routing Engine Notes

- `backend/app.py` owns graph construction, routing endpoints, config fallback, PocketBase proxy calls, and navigation metrics.
- Cached data files:
  - `backend/boulder_osm_data.json`
  - `backend/boulder_playground_data.json`
  - `backend/boulder_bike_stress_data.json`
  - `backend/boulder_bike_offstreet_data.json`
- On cache miss, backend may fetch from Overpass/Boulder Open Data. Do not assume network fetches are cheap or stable.
- Core endpoint: `POST /api/route` with start/end/waypoints/weights. Routing returns GeoJSON and segment metadata.
- Important debug endpoint: `GET /api/inspect-edge?lat=...&lon=...`.
- Weight formula from tools guide: edge cost = length * base multiplier * facility modifier * stress modifier * off-street modifier * e-bike modifier.
- When changing default route weights, keep defaults in sync across `backend/app.py`, `frontend/app.js`, `frontend/index.html`, and PocketBase seed/migration config if applicable.

## PocketBase Data Model

- `pb_migrations/1780629673_init_configs.js`: `global_configs` and `user_configs`, seeded weights/presets.
- `pb_migrations/1780629674_navigation_system.js`: `navigation_routes` and `navigation_ticks`.
- Later migrations add route tuning profiles, navigation metadata, and display metrics.
- Auth validation in Flask uses PocketBase `users/auth-refresh` with `Authorization: Bearer <token>`.
- Authenticated iOS/web features use PocketBase token from local storage/UserDefaults. Anonymous navigation history can fall back to route IDs.

## Production Database Access

- Production PocketBase runs in the `pocketbase` Docker container on `root@100.127.44.82`.
- The live SQLite file is bind-mounted at `/root/lockdev-home/data/pocketbase/data.db` on the host and `/pb_data/data.db` inside the container.
- The server may not have the `sqlite3` CLI installed. Use Python's sqlite module over SSH for read-only inspection:
  ```bash
  ssh -o BatchMode=yes root@100.127.44.82 'python3 - <<'"'"'PY'"'"'
  import sqlite3
  con = sqlite3.connect("/root/lockdev-home/data/pocketbase/data.db")
  con.row_factory = sqlite3.Row
  for row in con.execute("select id, started_at, status, total_length_meters, actual_distance_meters from navigation_routes order by started_at desc limit 10"):
      print(dict(row))
  PY'
  ```
- Useful production container check:
  ```bash
  ssh -o BatchMode=yes root@100.127.44.82 'docker ps --format "{{.Names}} {{.Image}} {{.Ports}}" | grep -E "boulder|pocketbase"'
  ```
- Do not write to the production DB casually. For route metric investigations, first compare `navigation_routes.total_length_meters`, stored `route_geojson` length, and summed `navigation_ticks` distance before deciding whether a record needs repair.

## Navigation And Sync

- Main navigation endpoints:
  - `POST /api/navigation/start`
  - `POST /api/navigation/<route_id>/tick`
  - `POST /api/navigation/<route_id>/end`
  - `GET /api/navigation/history`
  - `GET/PATCH/DELETE /api/navigation/<route_id>`
  - `POST /api/navigation/sync` for iOS local-to-cloud sync.
- Metrics logic prefers tick-derived actual distance/duration, but completed routes with too little tick distance fall back to planned route length for display.
- Navigation metric filtering is mirrored across Flask, web, and iOS. Keep the shared constants aligned: 75 m max GPS accuracy, 65 m stationary radius, 45 min idle auto-end, and 15 m/s max plausible step speed.
- iOS `SyncService` syncs unsynced SwiftData routes and route tuning profiles when `pocketbase_token` and `logged_in_user_id` exist.

## Tests And Diagnostics

- Backend navigation flow smoke test: `./venv/bin/python3 backend/test_navigation_flow.py`; it intentionally targets `http://localhost:8081/api` to verify nginx proxy mapping too.
- Route analysis: `./venv/bin/python3 tools/analyze_route.py <start_lat> <start_lon> <end_lat> <end_lon>`.
- Useful route regression scripts:
  - `./venv/bin/python3 tools/test_detour.py`
  - `./venv/bin/python3 tools/test_routing_stress.py`
  - `./venv/bin/python3 tools/test_matching.py`
  - `./venv/bin/python3 tools/test_iris_route.py`
  - `./venv/bin/python3 tools/test_loops.py`
- If routing behavior is odd, inspect the segment classification first: OSM tags, `facility_type`, `bikestress`, `offstreet_type`, and final multiplier.

## Editing Guardrails

- There may be local uncommitted Swift/Xcode changes from the user. Check `git status` before edits and do not revert unrelated files.
- Prefer small, targeted edits. Backend changes can affect web, iOS, and deployed Docker behavior.
- Avoid committing generated local state like Xcode `UserInterfaceState.xcuserstate`, `pb_data/`, logs, or local venv files.
- For frontend changes, verify at `http://localhost:8081` when practical.
- For deployment changes, reason through both local `docker-compose.yml` and remote expectations in `update.sh`.
