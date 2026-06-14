# iOS Route History and Sync Investigation Plan

## Problem

On a cellular connection, there can be a long delay between tapping End Navigation and seeing the completed route detail screen. Route deletion and local/cloud history consistency also need verification.

This document records the current code paths, identifies likely delay and race points, and defines the investigation and remediation sequence. It describes the current uncommitted workspace state as of June 14, 2026.

## Preliminary Conclusions

- Route detail presentation still waits for `loadHistory()`, and `loadHistory()` waits for a full remote history request when cloud sync is enabled. This directly exposes cellular latency to the transition.
- `TelemetryRouteEnded` has two listeners that independently call `loadHistory()`. One is in `MapViewModel`; the other is in `MainTabView`. This can issue duplicate concurrent history requests and race updates to `pastRoutes`.
- Before the notification is posted, `NavigationManager.stop()` inserts every cached tick into SwiftData and saves the route. That synchronous local work can delay the transition even without networking.
- The remote `/end` call is already launched in an unstructured `Task`, after the notification. Moving only that call to the background will not remove the remaining `loadHistory()` dependency or local save cost.
- The backend `/end` handler creates batched ticks in PocketBase one at a time. The delete handler also fetches and deletes ticks one at a time. Both paths scale poorly with route tick count.
- A normal history delete does send `DELETE /api/navigation/<route_id>` when the user is signed in and cloud sync is enabled. The backend deletes ticks and then the route. If direct deletion fails, a local tombstone is retained and `syncPendingRoutes()` is invoked.
- The delete method awaits the direct remote delete before its final `loadHistory()`, so that specific sequence does not fetch before its own delete completes. Other automatic history loads can still overlap it.
- Sync is local-first but not a single coordinated state machine. Direct REST end/update/delete calls and batch `/api/navigation/sync` both mutate the same records, with `synced` and `deleted` booleans acting as the queue state.

## Evidence From June 14 Delete Reproduction

The captured deletion log for route `t9q66n2cdsbwsn8` confirms:

- iOS marked the local route `deleted = true` and `synced = false` and saved successfully.
- Direct `DELETE /api/navigation/t9q66n2cdsbwsn8` returned `401`.
- The immediate fallback batch sync attempted four unsynced routes and also returned `401`.
- The subsequent history request was treated as a successful anonymous request and returned zero remote routes even though iOS still reported `isUserLoggedIn = true`.
- The following local fetch reported no deletion tombstones and showed all 21 routes again. Therefore the deleted route was not reliably hidden after failed authentication/sync.

This demonstrates both stale client authentication state and a deletion retry/UI consistency failure. The immediate remediation is to keep deletion locally authoritative, avoid an immediate competing batch sync after direct delete failure, and return `401` for an invalid supplied history token instead of returning an empty list.

Implemented session remediation:

- iOS now exchanges a valid stored token through PocketBase `auth-refresh` at app initialization and foregrounding, stores the replacement token, and schedules another refresh 30 minutes before the JWT expiration time.
- Initial route/profile sync waits for this refresh attempt.
- A PocketBase `401` marks the local session expired without deleting local routes or pending mutations.
- The app displays a global Session Expired alert with a direct Sign In action, and Account Settings retains the expired-session status.
- Successful sign-in clears the expired state and retries pending route/profile sync.
- Transient network failures do not sign the user out.

Follow-up evidence from the next reproduction showed authenticated DELETE requests returning `403`, not `401`. Production inspection confirmed the affected routes had an empty `user` owner because they were created while an expired token was supplied, and the deployed backend interpreted that invalid token as an anonymous request. The deployed ownership helper also still rejected authenticated deletion of those guest routes. The source now rejects invalid supplied tokens at navigation start and permits the existing guest-route mutation behavior, preventing new orphaned guest records and allowing legacy records to be removed after deployment.

The same reproduction showed SwiftData deletion flags returning to `false` before the next delete. A persistent route-ID deletion outbox is now also stored in UserDefaults. History merging always suppresses those IDs, and deletion is retried after token refresh or sign-in until the backend acknowledges it.

## Current Code Paths

### End Navigation to Route Detail

1. The UI calls `NavigationManager.stop()`.
2. `stop()` calculates metrics from `localTicksCache`.
3. It creates a `LocalRoute`, creates one `LocalNavigationTick` per cached tick, inserts them into SwiftData, and saves.
4. It posts `TelemetryRouteEnded` with the route id.
5. If cloud sync is active, it separately starts a `Task` that posts the route and all cached ticks to `/api/navigation/<id>/end`. Success marks the local route `synced = true`; failure leaves it pending.
6. `MapViewModel` receives `TelemetryRouteEnded` and calls `loadHistory()`.
7. `MainTabView` also receives the same notification, calls `loadHistory()`, searches `pastRoutes` for the id, sets `historyRouteToPresent`, and only then switches to History.
8. `HistoryTabView` presents `RouteHistoryDetailView` when `routeToPresent` changes.
9. The detail view starts `preloadHistoryRouteDetails()`. It uses SwiftData when a matching local route exists; otherwise it fetches `/api/navigation/<id>`.

Relevant files:

- `ios/BoulderBikeRouter/BoulderBikeRouter/Services/NavigationManager.swift`
- `ios/BoulderBikeRouter/BoulderBikeRouter/Views/MainTabView.swift`
- `ios/BoulderBikeRouter/BoulderBikeRouter/Views/HistoryTabView.swift`
- `ios/BoulderBikeRouter/BoulderBikeRouter/ViewModels/MapViewModel.swift`
- `ios/BoulderBikeRouter/BoulderBikeRouter/Services/APIService.swift`
- `backend/app.py` (`nav_end`, `nav_history`, and `nav_detail`)

### History Loading and Merge

1. When signed in with cloud sync enabled, `loadHistory()` first awaits `GET /api/navigation/history`.
2. It then fetches all local SwiftData routes.
3. Local deletion tombstones are collected and used to suppress matching remote routes.
4. Remote and local routes are merged by displayed route id, with local routes applied last.
5. `pastRoutes` is replaced with the sorted merged result.

Automatic load/sync triggers currently include model-context setup, cloud-sync enablement, app foregrounding, sign-in, sign-out, route-ended notification handling, edits, and deletes.

### Delete From History

1. `deleteHistoryRoute()` finds the local record by local id or server id.
2. For a remotely backed route, it sets `deleted = true` and `synced = false`. For a local-only route, it deletes immediately.
3. If the route exists only in the remote list, it creates a local deletion tombstone.
4. For signed-in cloud sync, it awaits `DELETE /api/navigation/<route_id>`.
5. On success, it removes the local tombstone/record. On failure, it calls `syncPendingRoutes()`.
6. It clears the selected detail and awaits a full `loadHistory()`.
7. The detail sheet waits for the entire method before dismissing. Swipe deletion also awaits the same operation in its task.

Backend delete behavior:

1. Authenticate and verify route ownership.
2. Fetch up to 5,000 ticks.
3. Delete each tick with an individual PocketBase request.
4. Delete the route record.

### Batch Sync

1. `SyncService.syncPendingRoutes()` selects every `LocalRoute` where `synced == false`.
2. It encodes all selected routes and all their ticks into one `/api/navigation/sync` request.
3. `deleted == true` becomes a delete operation; all other records become upserts.
4. The backend processes routes serially. New routes create ticks one at a time and then recalculate metrics.
5. The response marks successful upserts synced and permanently removes successful deletion tombstones locally.

Important consistency characteristics:

- There is no explicit `pending`, `syncing`, `failed`, or retry-count state.
- There is no request idempotency/version field for route mutations.
- There is no actor/lock preventing overlapping sync, history load, direct end, update, or delete operations.
- `SyncService.syncPendingRoutes()` checks authentication but does not itself check `cloud_sync_enabled`; callers are expected to enforce intent, and some automatic callers invoke it unconditionally.
- The batch endpoint can return HTTP 200 while omitting individual routes that failed, so success is partial and must be interpreted per item.

## Likely Causes to Measure

Ordered by expected relevance:

1. **Blocking remote history fetch before presentation.** `MainTabView` cannot set the route to present until `loadHistory()` returns.
2. **Duplicate route-ended history fetches.** Two listeners issue the same remote request and replace the same view-model state.
3. **Synchronous SwiftData tick persistence.** Inserting and saving a large tick set happens before the route-ended notification.
4. **Backend tick fan-out.** End, delete, and fallback sync perform many serial PocketBase HTTP calls.
5. **Concurrent end and history requests.** History can be fetched while `/end` is still uploading ticks and patching final metrics. Local merge usually protects the new route display, but remote state may be stale.
6. **Oversized fallback sync.** A failed direct mutation can trigger upload of every unsynced route and all ticks, increasing delay and network usage.
7. **No explicit loading/error state.** A sheet or list can appear unresponsive while an awaited operation runs, and failures are mostly console-only.
8. **Identifier ambiguity.** `PastRoute.id` prefers `serverId`, while notifications use the local route id. They currently match for server-started navigation but need tests for offline-started and later-synced routes.

## Investigation Plan

### Phase 1: Add Timing and Correlation Instrumentation

- Generate a correlation id for each end, history load, detail load, delete, and batch sync operation.
- Record monotonic durations for metric calculation, local route construction, local tick insertion, SwiftData save, notification-to-tab switch, history HTTP request, local history fetch, merge, sheet presentation, detail preload, remote end, and remote delete.
- Log route id, local id, server id, tick count, encoded request bytes, connection type, HTTP status, and result count.
- Add backend timings for PocketBase route lookup, tick creation/deletion count and duration, metric calculation, route patch/delete, and total request duration.
- Use unified logging/OSLog on iOS instead of writing to a Mac-only absolute file path.
- Confirm whether duplicate `loadHistory()` calls overlap by logging start/end and active operation count.

Exit criterion: one cellular reproduction produces an end-to-detail waterfall with no unexplained time interval.

### Phase 2: Reproduce Under Controlled Network Conditions

- Test on iPhone 17 Pro simulator with Network Link Conditioner profiles approximating LTE, constrained LTE, high latency, packet loss, and offline transitions.
- Repeat on a physical iPhone using `https://boulder.lockdev.com` because simulator localhost does not reproduce the production path.
- Use short, medium, and long routes with known tick counts.
- Test signed-out, signed-in sync enabled, and signed-in sync disabled.
- Capture server logs for the same correlation id and compare client duration with backend duration.
- Run each scenario at least three times and record median and worst case.

Exit criterion: delay is attributed among local persistence, client networking, backend processing, and UI sequencing.

### Phase 3: Verify Consistency and Race Scenarios

- End a route while `/end` is delayed; verify detail opens from local data and later reflects remote completion.
- End offline, relaunch, reconnect, and verify one remote route is created with one tick set.
- Trigger foreground sync while remote end is in flight; verify no duplicate ticks, route overwrite, or premature `synced = true`.
- Delete a local-only route, a synced route, and a remote-only route.
- Delete while history refresh is in flight; verify the tombstone prevents reappearance.
- Delete while offline, relaunch, reconnect, and verify the backend record is eventually removed.
- Force direct DELETE failure and verify fallback sync retains the tombstone until acknowledged.
- Toggle cloud sync off and foreground the app; verify no background route sync occurs.
- Verify partial `/sync` failures leave only failed records pending.

Exit criterion: each mutation has deterministic local UI behavior and eventual remote convergence across interruption/retry cases.

### Phase 4: Implement the Local-First UI Boundary

Subject to Phase 1 confirmation:

- Have `stop()` return or publish the newly saved `PastRoute`, not only an id.
- Switch to History and present that local route immediately after the local route record is durable.
- Remove the blocking full-history fetch from `MainTabView`'s route-ended transition.
- Keep one owner for route-ended history refresh; coalesce or cancel duplicate loads.
- Refresh remote history after presentation without blocking the detail screen.
- Add a small sync-status indicator such as `Saved on this iPhone`, `Syncing`, or `Sync failed`; do not use a full-screen loading screen for cloud sync.
- If local tick persistence is material, save the summary route first, present details, and persist ticks in a controlled background task using an appropriate SwiftData context. Preserve crash recovery and relationship integrity.

Expected user contract: tapping End should show the locally saved route detail quickly even when offline. Cloud completion is eventual and visible but not a navigation prerequisite.

### Phase 5: Make Delete Optimistic and Durable

- Mark the local record/tombstone first and remove it from visible history immediately.
- Dismiss the detail sheet immediately after the local save.
- Perform remote deletion asynchronously with retry state.
- Do not call a blocking full history fetch as part of the delete interaction.
- Surface retry/error status without resurrecting the route in the visible list.
- Decide whether direct DELETE remains or all mutations use one outbox. Prefer one mechanism to reduce competing writers.

Expected user contract: Remove from History is immediate locally; remote deletion is eventually confirmed and retried if needed.

### Phase 6: Consolidate Sync Into an Outbox

- Replace the two booleans as the sole state machine with explicit operation state: operation type, local id, server id, state, attempt count, last error, and timestamps.
- Serialize operations per route and make sync execution actor-isolated.
- Add idempotency keys or revision checks so retries cannot duplicate ticks or overwrite newer changes.
- Coalesce route edits and let delete supersede pending upserts.
- Respect `cloud_sync_enabled` inside the sync service itself.
- Trigger sync on app start/foreground, connectivity recovery, explicit enablement, and after local mutation, with backoff.
- Keep history reads independent of mutation acknowledgement.

### Phase 7: Reduce Backend Work

- Measure first, then remove per-tick HTTP loops where possible.
- Prefer PocketBase cascade deletion for ticks if the schema safely supports it, or add a backend/database batch deletion path.
- Avoid resending ticks already stored for a route. Track tick identity or an uploaded sequence/high-water mark.
- Chunk large tick uploads and make chunks idempotent.
- Make `/end` patch the route summary quickly; perform expensive tick ingestion/metric reconciliation separately if product accuracy permits.
- Return per-route structured errors from `/sync` and use a non-success overall status when the whole batch cannot be processed.
- Add indexes and query timing checks for navigation route ownership and tick-by-route queries.

## Automated Tests to Add

- iOS unit tests for local/remote merge, tombstone filtering, id mapping, and partial sync response handling.
- iOS async tests proving end-detail presentation does not await `fetchHistory()` or `endNavigation()`.
- iOS tests proving delete hides the route before remote acknowledgement and retains a tombstone on failure.
- Concurrency tests for overlapping foreground sync, end, delete, and history refresh.
- Backend tests for authenticated and anonymous end/delete behavior, partial sync failures, repeated idempotent requests, and large tick sets.
- Integration tests with injected latency and failures around `/end`, `/history`, `/navigation/<id>`, and `/sync`.
- Performance budgets: end tap to detail presentation, delete tap to UI removal, payload size, backend total duration, and per-tick processing time.

## Recommended Decision

Move cloud synchronization out of the critical UI path, but do not simply wrap the existing flow in another background `Task`. The route summary must be saved locally first, the detail screen must open from that local object, and one coordinated sync/outbox path must own eventual remote end/update/delete work.

A loading state is useful only for local persistence or local detail preparation if either takes perceptible time. Network synchronization should use a non-blocking status indicator and retry behavior rather than holding the route detail transition.
