import MapKit
import CoreLocation

/// Screen-point insets describing how much of each map edge is obscured by UI panels.
/// All values are in points. Adjust the static presets here to tune all map views at once.
struct MapFitInsets {
    let top: CGFloat
    let bottom: CGFloat
    let leading: CGFloat
    let trailing: CGFloat
    /// Minimum geographic span in degrees; prevents over-zooming on very short routes.
    let minSpan: CLLocationDegrees

    // collapsed search bar: .padding(.top, 50) + ~40pt bar = 90pt
    // route overview card: ~82pt card + 24pt outer padding + 34pt safe area = 140pt
    static let routeCard = MapFitInsets(top: 90, bottom: 140, leading: 16, trailing: 16, minSpan: 0.004)

    // history banner: .padding(.top, 50) + ~54pt banner = 104pt
    // no bottom card when history is selected: just safe area (34pt) + buffer = 50pt
    static let historyBanner = MapFitInsets(top: 104, bottom: 50, leading: 16, trailing: 16, minSpan: 0.004)

    // small static preview card embedded in a list row; no overlapping panels
    static let previewCard = MapFitInsets(top: 20, bottom: 8, leading: 8, trailing: 8, minSpan: 0.006)
}

/// Single source of truth for fitting a route into a map view.
///
/// Solves two problems with naive span-multiplication:
/// 1. Scales the geographic span so the route fills the *usable* area (screen minus insets),
///    not the full screen including panels.
/// 2. Shifts the camera center so the route's geographic midpoint appears at the visual
///    center of the usable area, not the full-screen center.
enum RouteMapCamera {

    /// Returns an `MKCoordinateRegion` that fits `coordinates` inside `screenSize`,
    /// respecting `insets` on each edge, with `contentPadding` inner breathing room.
    static func region(
        for coordinates: [CLLocationCoordinate2D],
        screenSize: CGSize,
        insets: MapFitInsets,
        contentPadding: Double = 1.1
    ) -> MKCoordinateRegion? {
        guard !coordinates.isEmpty else { return nil }

        let lats = coordinates.map(\.latitude)
        let lons = coordinates.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return nil }

        let geoCenterLat = (minLat + maxLat) / 2
        let geoCenterLon = (minLon + maxLon) / 2

        // Usable screen area after subtracting UI panels.
        let usableH = max(1.0, Double(screenSize.height - insets.top - insets.bottom))
        let usableW = max(1.0, Double(screenSize.width - insets.leading - insets.trailing))

        // Scale span so the bounding box fills the usable area (screenH/usableH amplifies
        // the span to account for the fraction of screen hidden behind panels).
        let latDelta = max(insets.minSpan,
                           (maxLat - minLat) * contentPadding * Double(screenSize.height) / usableH)
        let lonDelta = max(insets.minSpan,
                           (maxLon - minLon) * contentPadding * Double(screenSize.width) / usableW)

        // Shift the camera center so geoCenter appears at the usable-area midpoint.
        //
        // MapKit places the center coordinate at pixel (screenW/2, screenH/2).
        // The usable-area midpoint is at (topInset + usableH/2) from the top, which is
        // (topInset - bottomInset)/2 pixels above screen center.
        // Since increasing latitude maps to moving up (decreasing pixel-y), moving the
        // camera south by δ pixels causes geoCenter to appear δ pixels above camera center.
        // Therefore: cameraLat = geoCenterLat + (topInset - bottomInset)/2 * latDelta/screenH
        let latCenterOffset = (Double(insets.top) - Double(insets.bottom)) / 2.0
                                * latDelta / Double(screenSize.height)
        let lonCenterOffset = (Double(insets.trailing) - Double(insets.leading)) / 2.0
                                * lonDelta / Double(screenSize.width)

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: geoCenterLat + latCenterOffset,
                longitude: geoCenterLon + lonCenterOffset
            ),
            span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
        )
    }
}
