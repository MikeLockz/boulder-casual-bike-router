# Official Bike Routes Overlay Rendering Plan

## Goal

Make the official bike routes layer performant and map-aligned on iOS and web.

The current iOS issue is caused by rendering thousands of official route segments as SwiftUI `MapPolyline` children. A `Canvas` overlay improves performance, but it is not viable because it can drift from the underlying map projection during pan, zoom, pitch, or heading changes.

The chosen direction is to do both:

1. Group official bike route data on the server into a small number of display-layer `MultiLineString` features, with optional meter-based coordinate simplification.
2. Move the entire iOS map surface to `MKMapView` and render grouped iOS routes with `MKMultiPolylineRenderer`.

This keeps performance first, preserves native map alignment, and keeps full-detail data available through `detail=full` for web debug tooling and future explicit callers.

## Requirements

- Normal web and iOS clients must use a grouped display layer.
- Coordinate simplification must be configurable in meters and must default to no simplification.
- Full-detail ungrouped route geometry must remain available with `?detail=full`.
- Official bike routes must align with the base map during pan, zoom, pitch, and active navigation.
- Active navigation 3D camera mode must support the official bike route layer.
- Route planning, history display, start/end markers, waypoints, home selection, and navigation controls must continue to work.
- Per-segment tooltips are not required for normal clients. They are only needed for web/debug inspection.

## Server Plan

### 1. Define Display Categories

Group detailed `FACILITYTYPE` values into a small stable set of display categories:

| Display category | Source facility types |
| --- | --- |
| `paths` | `Multi-Use Path`, `Bike Park Path`, `Soft Surface Trail` |
| `protected` | `Protected Bike Lane`, `Separated Bike Lane`, `Contra Flow Bike Lane` |
| `lanes` | `On-Street Bike Lane`, `Bikeable Shoulder` |
| `designated` | `Designated Bike Route` |
| `other` | Any supported fallback type |

Each grouped feature should include properties such as:

```json
{
  "route_category": "paths",
  "display_name": "Paths",
  "facility_types": ["Multi-Use Path", "Bike Park Path", "Soft Surface Trail"]
}
```

### 2. Build Grouped Display GeoJSON

For the normal `/api/bike-routes` response:

- Filter official route source files as today.
- Simplify line coordinates on the server only when `BIKE_ROUTE_SIMPLIFICATION_TOLERANCE_METERS` is greater than `0`.
- Default to `BIKE_ROUTE_SIMPLIFICATION_TOLERANCE_METERS=0`, which means no coordinate simplification.
- Treat any configured value as meters.
- Group display line strings by display category.
- Return one `MultiLineString` feature per category.
- Store this grouped response in the graph cache as `bike_routes_geojson`.

Expected shape:

```json
{
  "type": "FeatureCollection",
  "features": [
    {
      "type": "Feature",
      "properties": {
        "route_category": "paths",
        "display_name": "Paths",
        "facility_types": ["Multi-Use Path", "Bike Park Path", "Soft Surface Trail"]
      },
      "geometry": {
        "type": "MultiLineString",
        "coordinates": [
          [[-105.27, 40.01], [-105.26, 40.02]]
        ]
      }
    }
  ]
}
```

### 3. Preserve Full Detail

For `/api/bike-routes?detail=full`:

- Return ungrouped full-detail features.
- Do not store the full-detail response as the normal cached display layer.
- Keep source facility names and street/path names for tooltips and inspection.

The web debug mode already has the right API intent: when `?debug` or `?sim` is active, request `detail=full`. iOS does not need to expose a debug overlay mode for this phase, but the endpoint remains available.

### 4. Cache Invalidation

Because the cached `bike_routes_geojson` structure changes from many individual features to grouped `MultiLineString` features:

- Bump `GRAPH_BUILD_VERSION`.
- Include `BIKE_ROUTE_SIMPLIFICATION_TOLERANCE_METERS` in the graph cache fingerprint so changing the tolerance regenerates cached display geometry.
- Rebuild/recreate local and production backend containers after deploying.
- Confirm `/api/graph-status` reaches `ready` for each region.

### 5. Server Acceptance Checks

- `/api/bike-routes?region=boulder` returns roughly 4-5 grouped features.
- `/api/bike-routes?region=boulder&detail=full` returns the full ungrouped feature set.
- Normal grouped response has far fewer feature objects than full detail.
- With default tolerance, grouped response preserves source coordinates inside category `MultiLineString`s.
- With nonzero tolerance, grouped response preserves route endpoints and enough visual fidelity at normal map zooms.
- Web normal mode uses grouped display data.
- Web debug mode uses full-detail data.

## iOS Plan

### 1. Replace Official Route Canvas

Remove the `Canvas` official route overlay from `MainMapView`.

Do not return to thousands of SwiftUI `MapPolyline` children for official bike routes. The server grouping helps the data shape, but SwiftUI `Map` still does not give enough explicit overlay-rendering control for this layer.

### 2. Replace The Entire Map With `MKMapView`

Create a SwiftUI wrapper around one `MKMapView` map surface, likely:

- `MapKitMapView`
- `MapKitMapCoordinator`
- `OfficialBikeRoutesOverlayRenderer` or equivalent helper

The wrapper should be responsible for:

- Map camera position, pitch, heading, and fitting.
- User location display.
- Start/end markers.
- Waypoint markers.
- Home selection marker.
- Planned route overlay.
- History route overlay.
- Official bike routes overlay.
- Tap handling for start/end/home selection.
- Drag handling for editable markers.

The entire current SwiftUI `Map` surface should move to this wrapper. Do not stack a second map or canvas overlay on top of the SwiftUI map.

The surrounding UI should remain SwiftUI:

- Search and route planner UI.
- Settings.
- History.
- Navigation banners.
- Bottom tab shell.
- Active navigation controls.

### 3. Render Official Routes With `MKMultiPolylineRenderer`

Convert each grouped `MultiLineString` feature into one `MKMultiPolyline`.

Add one overlay per display category:

- `paths`
- `protected`
- `lanes`
- `designated`
- `other` if present

Use `MKMultiPolylineRenderer` styles:

| Category | Style intent |
| --- | --- |
| `paths` | Green, thickest |
| `protected` | Cyan, medium-thick |
| `lanes` | Blue/slate, medium |
| `designated` | Purple, medium |
| `other` | Muted gray |

Ensure official route overlays draw behind:

- Planned route line.
- Active navigation route line.
- History route line.
- Markers and user location.

### 4. Model Changes

Update iOS route overlay models so they represent grouped paths directly.

Suggested shape:

```swift
struct BikeRouteOverlayGroup: Identifiable {
    let id: String
    let category: String
    let displayName: String
    let facilityTypes: [String]
    let coordinatePaths: [[CLLocationCoordinate2D]]
}
```

`APIService.fetchBikeRoutes(region:)` should parse both:

- Normal grouped `MultiLineString` features.
- Full-detail features if an explicit future iOS diagnostic path requests `detail=full`.

### 5. Active Navigation 3D Support

`MKMapView` supports camera heading and pitch through `MKMapCamera`. Native overlays are projected by MapKit, so official routes should stay aligned in the active navigation 3D view.

Implementation requirements:

- Official route overlays must remain enabled when navigation mode activates.
- Active navigation camera updates must use `MKMapCamera` or `MKCoordinateRegion` consistently.
- Official overlays must be re-rendered only when the data or visibility changes, not on every location tick.
- User puck, route progress, and maneuver UI must stay responsive while the official layer is visible.

### 6. Update Strategy

Avoid recreating all overlays on every SwiftUI render.

Coordinator should track:

- Current region.
- Official routes visibility.
- Official routes overlay version or IDs.
- Active route geometry version.
- History route geometry version.
- Marker state.

Only add/remove official overlays when:

- Region changes.
- Official layer toggles on/off.
- The fetched overlay groups change.

### 7. iOS Acceptance Checks

- Toggle official routes on/off without UI lockup.
- Pan and zoom at Boulder with official routes visible.
- Zoom to street level and confirm route lines align with streets/paths.
- Enter active navigation mode and confirm 3D camera keeps official routes aligned.
- Confirm official routes render behind the active route line.
- Switch regions and confirm old overlays are removed.
- Disable layer and confirm overlays are removed immediately.
- Run simulator build:

```bash
xcodebuild -project ios/BoulderBikeRouter/BoulderBikeRouter.xcodeproj -scheme BoulderBikeRouter -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

## Web Plan

### 1. Normal Mode

Normal web mode should request:

```text
/api/bike-routes?region=<region>
```

This receives grouped display `MultiLineString` features.

Leaflet can render grouped `MultiLineString` features directly with the existing `L.geoJSON` path, using `route_category` or fallback facility type for styling.

### 2. Debug Mode

Debug web mode should request:

```text
/api/bike-routes?region=<region>&detail=full
```

This preserves per-segment names and facility types for inspection and tooltips.

### 3. Web Acceptance Checks

- Normal mode renders grouped display layer.
- Debug mode renders full-detail layer.
- Tooltips remain available in debug mode.
- Switching regions clears cached route layer and detail level.

## Rollout Order

1. Implement server grouped display response with configurable simplification tolerance.
2. Keep debug full-detail response working.
3. Update web styling to support grouped `route_category` properties.
4. Update iOS models to parse grouped route overlays.
5. Replace the entire iOS SwiftUI map surface with `MKMapView` + `MKMultiPolylineRenderer`.
6. Verify normal map mode.
7. Verify active navigation 3D mode.
8. Rebuild Docker backend and wait for graph cache regeneration.
9. Validate production host after deployment.

## Resolved Decisions

- Simplification tolerance is configurable with `BIKE_ROUTE_SIMPLIFICATION_TOLERANCE_METERS`.
- Tolerance values are meters.
- Default tolerance is `0`, meaning no coordinate simplification.
- `detail=full` remains available for full-detail ungrouped geometry.
- Web debug mode uses `detail=full`.
- iOS does not need to expose a debug full-detail overlay mode for this phase.
- The entire iOS map surface should move to one `MKMapView`; do not stack maps or canvas overlays.

## Non-Goals For This Phase

- Custom vector tiles.
- Per-segment tooltips in normal client mode.
- Changing routing graph precision.
- Changing route planning behavior or weights.
