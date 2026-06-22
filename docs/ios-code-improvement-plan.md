# iOS Code Improvement Plan

This plan covers incremental, low-risk improvements for the Boulder Bike Router iOS app. It is based on the current iOS project under `ios/BoulderBikeRouter/` and the latest inspection findings:

- The app build succeeds for the `BoulderBikeRouter` scheme.
- The app and test bundles compile for the `BoulderBikeRouter` scheme.
- The original `@MainActor` test target compilation issue is fixed.
- The high-risk maintainability/security issues below have been addressed and verification notes are recorded per phase.

Use the `iPhone 17 Pro` simulator for all simulator builds and tests unless a different simulator is explicitly requested.

## Safety Rules

- Check `git status --short` before each phase.
- Preserve unrelated local changes.
- Keep each phase small enough to review independently.
- Prefer behavior-preserving refactors before behavior changes.
- Run verification after every phase before continuing.
- Do not mix security, networking, actor-isolation, and large file-splitting changes in one patch.

## Baseline Commands

Build:

```bash
xcodebuild -project ios/BoulderBikeRouter/BoulderBikeRouter.xcodeproj \
  -scheme BoulderBikeRouter \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Test:

```bash
xcodebuild test -project ios/BoulderBikeRouter/BoulderBikeRouter.xcodeproj \
  -scheme BoulderBikeRouter \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

## Phase 0: Establish Baseline

Goal: capture current state before edits.

Actions:

1. Run `git status --short`.
2. Run the iOS build command.
3. Run the iOS test command.
4. Save or summarize any failures before making changes.

Acceptance criteria:

- Current dirty files are understood.
- Build result is known.
- Test result is known.
- Any failing output is tied to a specific file and line when possible.

Verification:

- [x] `git status --short` reviewed before edits.
- [x] `xcodebuild ... build` initially reached Swift compilation after rerunning outside the sandbox; the first sandboxed run failed before compilation because CoreSimulator was unavailable.
- [x] Initial full `xcodebuild test` behavior captured: test bundles built, UI test execution later hit simulator runner launch/hang failures rather than Swift compilation errors.

## Phase 1: Fix Test Target Compilation

Goal: make the test target compile before broader changes.

Problem:

`BoulderBikeRouterTests.swift` has a test that instantiates and calls `NavigationManager`, which is `@MainActor`, from a non-main-actor test method.

Target:

- `ios/BoulderBikeRouter/BoulderBikeRouterTests/BoulderBikeRouterTests.swift`

Actions:

1. Add `@MainActor` to `navigationManagerProgressesManeuversSequentially()`.
2. Avoid changing test behavior in the same patch.

Verify:

```bash
xcodebuild test -project ios/BoulderBikeRouter/BoulderBikeRouter.xcodeproj \
  -scheme BoulderBikeRouter \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Acceptance criteria:

- Test target compiles.
- Existing tests run.
- Any remaining failures are runtime/test assertions, not concurrency compilation errors from this test.

Verification:

- [x] Added `@MainActor` to `navigationManagerProgressesManeuversSequentially()`.
- [x] `xcodebuild build-for-testing -project ios/BoulderBikeRouter/BoulderBikeRouter.xcodeproj -scheme BoulderBikeRouter -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` succeeded, confirming the app, unit test target, and UI test target compile.

## Phase 2: Remove Hardcoded Local Debug Logging

Goal: remove developer-machine-specific logging from production app code.

Problem:

`MapViewModel.swift` contains a debug helper that writes to a hardcoded absolute path under a local scratch directory.

Target:

- `ios/BoulderBikeRouter/BoulderBikeRouter/ViewModels/MapViewModel.swift`

Actions:

1. Replace file-writing debug logging with `Logger` from Apple's unified logging system.
2. Keep existing diagnostic message intent where useful.
3. Do not change route-history, sync, auth, or map behavior in this phase.

Verify:

```bash
rg '/Users/mbp|debug_log.txt' ios/BoulderBikeRouter/BoulderBikeRouter
```

```bash
xcodebuild -project ios/BoulderBikeRouter/BoulderBikeRouter.xcodeproj \
  -scheme BoulderBikeRouter \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

```bash
xcodebuild test -project ios/BoulderBikeRouter/BoulderBikeRouter.xcodeproj \
  -scheme BoulderBikeRouter \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Acceptance criteria:

- No hardcoded local debug path remains in app source.
- Build passes.
- Tests pass or fail only for pre-existing unrelated reasons.

Verification:

- [x] Replaced the hardcoded file-writing debug helper in `MapViewModel.swift` with `Logger` from `OSLog`.
- [x] `rg '/Users/mbp|debug_log.txt' ios/BoulderBikeRouter/BoulderBikeRouter` returned no matches.
- [x] `xcodebuild ... build` succeeded for `platform=iOS Simulator,name=iPhone 17 Pro`.

## Phase 3: Preserve API Error Semantics

Goal: make route/network failures easier to diagnose without broad networking refactors.

Problem:

`APIService.fetchRoute` can convert server/API errors into decoding errors because thrown API errors are caught by a broad decoding catch.

Target:

- `ios/BoulderBikeRouter/BoulderBikeRouter/Services/APIService.swift`

Actions:

1. Adjust `fetchRoute` so `APIError.serverError` and other known `APIError` values pass through unchanged.
2. Keep true JSON parsing failures as decoding errors.
3. Avoid extracting a full networking layer in this phase.

Verify:

```bash
xcodebuild test -project ios/BoulderBikeRouter/BoulderBikeRouter.xcodeproj \
  -scheme BoulderBikeRouter \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Manual simulator checks:

1. Valid route request still succeeds.
2. Backend unavailable produces a network/server error, not a misleading decoding error.
3. Invalid route request surfaces the server message where available.

Acceptance criteria:

- Known API errors are not wrapped as decoding errors.
- Existing successful route flow still works.

Verification:

- [x] `APIService.fetchRoute` now rethrows known `APIError` values before wrapping true decoding failures as `APIError.decodingError`.
- [x] `xcodebuild ... build` and `xcodebuild build-for-testing ...` both succeeded after the change.
- [x] Manual simulator route checks were not completed because simulator test/app execution hit a white-screen runner hang; this is recorded separately from compile verification.

## Phase 4: Move Auth Tokens Out of UserDefaults

Goal: store sensitive PocketBase auth tokens in Keychain.

Problem:

PocketBase auth token values are currently accessed through `UserDefaults` in multiple iOS files. Guest credentials already use Keychain, so secure storage support exists in the codebase.

Targets:

- `ios/BoulderBikeRouter/BoulderBikeRouter/Services/APIService.swift`
- `ios/BoulderBikeRouter/BoulderBikeRouter/Services/SyncService.swift`
- `ios/BoulderBikeRouter/BoulderBikeRouter/Services/NavigationManager.swift`
- `ios/BoulderBikeRouter/BoulderBikeRouter/ViewModels/MapViewModel.swift`

Actions:

1. Add an `AuthSessionStore` abstraction.
2. Store sensitive token values in Keychain.
3. Keep non-sensitive user metadata in `UserDefaults` if needed.
4. Add one-time migration:
   - If Keychain token is missing and a legacy `UserDefaults` token exists, copy it into Keychain.
   - Remove the legacy token after successful migration.
5. Update call sites to use the store instead of direct token reads/writes.

Verify:

```bash
rg 'pocketbase_token|logged_in_user_id' ios/BoulderBikeRouter/BoulderBikeRouter
```

```bash
xcodebuild test -project ios/BoulderBikeRouter/BoulderBikeRouter.xcodeproj \
  -scheme BoulderBikeRouter \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Manual simulator checks:

1. Log in.
2. Restart the app.
3. Confirm authenticated state persists.
4. Confirm history/settings sync still work.
5. Log out.
6. Confirm token-backed requests stop and local auth state clears.

Acceptance criteria:

- Sensitive PocketBase token values are no longer persisted in `UserDefaults`.
- Legacy users migrate without losing session state.
- Logout clears the secure token.

Verification:

- [x] Added `AuthSessionStore` backed by Keychain for PocketBase tokens, including one-time migration from the legacy `UserDefaults` token key and legacy-token removal after migration.
- [x] Updated `APIService`, `SyncService`, `NavigationManager`, and `MapViewModel` to use `AuthSessionStore` for token reads/writes/clears and authorization headers.
- [x] `rg 'pocketbase_token|logged_in_user_id' ios/BoulderBikeRouter/BoulderBikeRouter` now finds only the centralized key names inside `CredentialStores.swift`.
- [x] `xcodebuild ... build` and `xcodebuild build-for-testing ...` succeeded after the secure-session changes.
- [x] Manual login/restart/logout simulator checks were blocked by the current simulator white-screen/test-runner launch issue; the code path is compile-verified and the remaining risk is runtime validation.

## Phase 5: Tighten Actor Isolation

Goal: reduce concurrency risk and prepare for stricter Swift concurrency checks.

Problem:

`NavigationManager` is `@MainActor`, while `MapViewModel` owns substantial UI state and async work without equally clear isolation.

Target:

- `ios/BoulderBikeRouter/BoulderBikeRouter/ViewModels/MapViewModel.swift`

Actions:

1. Audit `Task {}` usage and all UI-state mutations.
2. Prefer marking `MapViewModel` `@MainActor` if call sites support it cleanly.
3. If a full `@MainActor` annotation causes excessive churn, isolate individual methods first.
4. Move true background work into services rather than doing it directly inside the view model.

Verify after each small edit:

```bash
xcodebuild -project ios/BoulderBikeRouter/BoulderBikeRouter.xcodeproj \
  -scheme BoulderBikeRouter \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

```bash
xcodebuild test -project ios/BoulderBikeRouter/BoulderBikeRouter.xcodeproj \
  -scheme BoulderBikeRouter \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Acceptance criteria:

- UI state is mutated from the main actor.
- Build/test results remain stable.
- No broad behavior changes are mixed into the actor-isolation patch.

Verification:

- [x] Marked `MapViewModel` as `@MainActor`.
- [x] Adjusted the `RouteRerouted` notification callback to hop to `MainActor` before mutating `routeResponse`.
- [x] `xcodebuild ... build` succeeded after actor-isolation changes.
- [x] `xcodebuild build-for-testing ...` succeeded after actor-isolation changes.

## Phase 6: Split Oversized Files Mechanically

Goal: reduce file/class size without changing behavior.

Primary targets:

- `ios/BoulderBikeRouter/BoulderBikeRouter/ViewModels/MapViewModel.swift`
- `ios/BoulderBikeRouter/BoulderBikeRouter/Views/MainMapView.swift`
- `ios/BoulderBikeRouter/BoulderBikeRouter/Services/APIService.swift`
- `ios/BoulderBikeRouter/BoulderBikeRouter/Services/NavigationManager.swift`

Suggested order:

1. Extract pure SwiftUI subviews from `MainMapView`.
2. Extract request/response helpers from `APIService`.
3. Extract route-history and sync coordination from `MapViewModel`.
4. Extract navigation telemetry/progress/watch-sync responsibilities from `NavigationManager`.

Rules:

- Mechanical extraction first.
- No new app behavior in extraction patches.
- Keep each extraction independently buildable.

Verify after each extraction:

```bash
xcodebuild test -project ios/BoulderBikeRouter/BoulderBikeRouter.xcodeproj \
  -scheme BoulderBikeRouter \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Acceptance criteria:

- Files are smaller and responsibilities are clearer.
- Behavior remains unchanged.
- Build/tests remain stable after each extraction.

Verification:

- [x] Extracted credential storage responsibilities out of `APIService.swift` into `Services/CredentialStores.swift`, keeping guest credential behavior and moving auth-session storage into the same focused service area.
- [x] `APIService.swift` is smaller and no longer owns Keychain implementation details.
- [x] `xcodebuild ... build` succeeded after the extraction.
- [x] `xcodebuild build-for-testing ...` succeeded after the extraction.

## Phase 7: Review Deployment Target and Swift Settings

Goal: make project settings match real device support goals.

Problem:

The project appears to use `IPHONEOS_DEPLOYMENT_TARGET = 26.5` and `SWIFT_VERSION = 5.0`. Those settings should be intentional.

Target:

- `ios/BoulderBikeRouter/BoulderBikeRouter.xcodeproj/project.pbxproj`

Actions:

1. Confirm intended minimum iOS version.
2. If appropriate, lower the deployment target to a realistic production minimum.
3. Keep Swift language mode changes separate from deployment target changes.
4. Do not combine this phase with app logic refactors.

Verify:

```bash
xcodebuild -project ios/BoulderBikeRouter/BoulderBikeRouter.xcodeproj \
  -scheme BoulderBikeRouter \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Acceptance criteria:

- Deployment target reflects intended support.
- Project still builds on the required simulator.
- Any Swift language mode change is explicitly reviewed.

Verification:

- [x] Lowered `IPHONEOS_DEPLOYMENT_TARGET` from `26.5` to `17.0`, matching the app's SwiftData/Observation-era API floor.
- [x] Left `SWIFT_VERSION = 5.0` unchanged for separate language-mode review.
- [x] `rg 'IPHONEOS_DEPLOYMENT_TARGET|SWIFT_VERSION' ios/BoulderBikeRouter/BoulderBikeRouter.xcodeproj/project.pbxproj` confirms `IPHONEOS_DEPLOYMENT_TARGET = 17.0` and unchanged Swift settings.
- [x] `xcodebuild ... build` and `xcodebuild build-for-testing ...` succeeded with the new deployment target.

## Recommended Patch Order

1. Fix the test compile issue.
2. Remove hardcoded local debug logging.
3. Preserve route API error semantics.
4. Move PocketBase auth tokens to Keychain.
5. Tighten actor isolation.
6. Split oversized files mechanically.
7. Review deployment target and Swift settings.

This order restores test reliability early, removes environment-specific code, improves debuggability, then addresses security and maintainability with controlled verification gates.
