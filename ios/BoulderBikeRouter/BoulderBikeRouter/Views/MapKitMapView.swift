import SwiftUI
import MapKit
import CoreLocation

private enum MapAnnotationKind: String {
    case start
    case destination
    case user
    case waypoint
    case home
    case historyTick
}

private final class RoutePointAnnotation: NSObject, MKAnnotation {
    let kind: MapAnnotationKind
    let index: Int?
    dynamic var coordinate: CLLocationCoordinate2D
    var title: String?

    init(kind: MapAnnotationKind, coordinate: CLLocationCoordinate2D, title: String? = nil, index: Int? = nil) {
        self.kind = kind
        self.coordinate = coordinate
        self.title = title
        self.index = index
    }
}

private final class StyledPolyline: MKPolyline {
    var styleKey: String = "route"
}

private final class StyledMultiPolyline: MKMultiPolyline {
    var styleKey: String = "other"
}

struct MapKitMapView: UIViewRepresentable {
    @Binding var cameraPosition: MapCameraPosition

    let startLocation: CLLocationCoordinate2D?
    let endLocation: CLLocationCoordinate2D?
    let selectedHistoryActualCoordinates: [CLLocationCoordinate2D]
    let pendingHomeCoordinate: CLLocationCoordinate2D?
    let userCoordinate: CLLocationCoordinate2D?
    let routeCoordinatePaths: [[CLLocationCoordinate2D]]
    let waypoints: [CLLocationCoordinate2D]
    let officialRouteGroups: [BikeRouteOverlayGroup]
    let showOfficialRoutes: Bool
    let isSelectingHomeLocation: Bool
    let mapSelectionMode: MapSelectionTarget?
    let onMapTap: (CLLocationCoordinate2D) -> Void
    let onStartDragChanged: (CLLocationCoordinate2D) -> Void
    let onStartDragEnded: (CLLocationCoordinate2D) -> Void
    let onEndDragChanged: (CLLocationCoordinate2D) -> Void
    let onEndDragEnded: (CLLocationCoordinate2D) -> Void
    let onHomeDragChanged: (CLLocationCoordinate2D) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.mapType = .standard
        mapView.pointOfInterestFilter = .excludingAll
        mapView.showsCompass = true
        mapView.showsScale = false
        mapView.isRotateEnabled = true
        mapView.isPitchEnabled = true
        mapView.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: "RoutePointAnnotation")

        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tapGesture.delegate = context.coordinator
        mapView.addGestureRecognizer(tapGesture)

        context.coordinator.applyCamera(cameraPosition, to: mapView, animated: false)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.applyCamera(cameraPosition, to: mapView, animated: true)
        context.coordinator.updateAnnotations(on: mapView)
        context.coordinator.updateOverlays(on: mapView)
        context.coordinator.updateOfficialOverlayVisibility(on: mapView)
    }

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: MapKitMapView
        private var isApplyingCamera = false
        private var lastCameraSignature: String?
        private var lastAnnotationSignature: String?
        private var lastOverlaySignature: String?

        init(_ parent: MapKitMapView) {
            self.parent = parent
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended,
                  let mapView = recognizer.view as? MKMapView,
                  parent.isSelectingHomeLocation || parent.mapSelectionMode != nil else { return }
            let point = recognizer.location(in: mapView)
            parent.onMapTap(mapView.convert(point, toCoordinateFrom: mapView))
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        func applyCamera(_ position: MapCameraPosition, to mapView: MKMapView, animated: Bool) {
            let signature = cameraSignature(for: position)
            guard signature != lastCameraSignature else { return }
            lastCameraSignature = signature
            isApplyingCamera = true
            defer { isApplyingCamera = false }

            if let camera = position.camera {
                let mkCamera = MKMapCamera(
                    lookingAtCenter: camera.centerCoordinate,
                    fromDistance: camera.distance,
                    pitch: camera.pitch,
                    heading: camera.heading
                )
                mapView.setCamera(mkCamera, animated: animated)
            } else if let region = position.region {
                mapView.setRegion(region, animated: animated)
            }
        }

        private func cameraSignature(for position: MapCameraPosition) -> String {
            if let camera = position.camera {
                return String(format: "c:%.6f:%.6f:%.1f:%.1f:%.1f",
                              camera.centerCoordinate.latitude,
                              camera.centerCoordinate.longitude,
                              camera.distance,
                              camera.heading,
                              camera.pitch)
            }
            if let region = position.region {
                return String(format: "r:%.6f:%.6f:%.6f:%.6f",
                              region.center.latitude,
                              region.center.longitude,
                              region.span.latitudeDelta,
                              region.span.longitudeDelta)
            }
            return "unknown"
        }

        func updateAnnotations(on mapView: MKMapView) {
            let annotations = makeAnnotations()
            let signature = annotations
                .map { "\($0.kind.rawValue):\($0.index ?? -1):\(rounded($0.coordinate.latitude)):\(rounded($0.coordinate.longitude))" }
                .joined(separator: "|")
            guard signature != lastAnnotationSignature else { return }
            lastAnnotationSignature = signature

            mapView.removeAnnotations(mapView.annotations)
            mapView.addAnnotations(annotations)
        }

        private func makeAnnotations() -> [RoutePointAnnotation] {
            var annotations: [RoutePointAnnotation] = []

            if !parent.isSelectingHomeLocation {
                if let start = parent.startLocation {
                    annotations.append(RoutePointAnnotation(kind: .start, coordinate: start, title: "Start"))
                } else if let first = parent.selectedHistoryActualCoordinates.first {
                    annotations.append(RoutePointAnnotation(kind: .start, coordinate: first, title: "Start"))
                }

                if let end = parent.endLocation {
                    annotations.append(RoutePointAnnotation(kind: .destination, coordinate: end, title: "Destination"))
                } else if parent.selectedHistoryActualCoordinates.count >= 2,
                          let last = parent.selectedHistoryActualCoordinates.last {
                    annotations.append(RoutePointAnnotation(kind: .destination, coordinate: last, title: "Destination"))
                }

                for (index, waypoint) in parent.waypoints.enumerated() {
                    annotations.append(RoutePointAnnotation(kind: .waypoint, coordinate: waypoint, index: index))
                }

                if parent.selectedHistoryActualCoordinates.count == 1,
                   let tick = parent.selectedHistoryActualCoordinates.first {
                    annotations.append(RoutePointAnnotation(kind: .historyTick, coordinate: tick))
                }
            }

            if let userCoordinate = parent.userCoordinate {
                annotations.append(RoutePointAnnotation(kind: .user, coordinate: userCoordinate, title: "User Location"))
            }

            if let pendingHome = parent.pendingHomeCoordinate {
                annotations.append(RoutePointAnnotation(kind: .home, coordinate: pendingHome, title: "Home"))
            }

            return annotations
        }

        func updateOverlays(on mapView: MKMapView) {
            let signature = overlaySignature()
            guard signature != lastOverlaySignature else { return }
            lastOverlaySignature = signature

            mapView.removeOverlays(mapView.overlays)

            for group in parent.officialRouteGroups {
                let polylines = group.coordinatePaths
                    .filter { $0.count >= 2 }
                    .map { MKPolyline(coordinates: $0, count: $0.count) }
                guard !polylines.isEmpty else { continue }
                let overlay = StyledMultiPolyline(polylines)
                overlay.styleKey = group.category
                mapView.addOverlay(overlay, level: .aboveRoads)
            }

            for path in parent.routeCoordinatePaths where path.count >= 2 {
                let overlay = StyledPolyline(coordinates: path, count: path.count)
                overlay.styleKey = "route"
                mapView.addOverlay(overlay, level: .aboveLabels)
            }

            if parent.routeCoordinatePaths.isEmpty && parent.selectedHistoryActualCoordinates.count >= 2 {
                let overlay = StyledPolyline(coordinates: parent.selectedHistoryActualCoordinates, count: parent.selectedHistoryActualCoordinates.count)
                overlay.styleKey = "history"
                mapView.addOverlay(overlay, level: .aboveLabels)
            }
        }

        private func overlaySignature() -> String {
            let official = parent.officialRouteGroups.map { "\($0.id):\($0.coordinatePaths.count)" }.joined(separator: ",")
            let routes = parent.routeCoordinatePaths.map { "\($0.count)" }.joined(separator: ",")
            let history = parent.selectedHistoryActualCoordinates.count
            return "\(official)|\(routes)|\(history)"
        }

        func updateOfficialOverlayVisibility(on mapView: MKMapView) {
            for overlay in mapView.overlays {
                guard overlay is StyledMultiPolyline,
                      let renderer = mapView.renderer(for: overlay) else { continue }
                let targetAlpha: CGFloat = parent.showOfficialRoutes ? 1.0 : 0.0
                guard abs(renderer.alpha - targetAlpha) > 0.01 else { continue }
                renderer.alpha = targetAlpha
                renderer.setNeedsDisplay()
            }
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            guard !isApplyingCamera else { return }
            let camera = mapView.camera
            lastCameraSignature = String(format: "c:%.6f:%.6f:%.1f:%.1f:%.1f",
                                         camera.centerCoordinate.latitude,
                                         camera.centerCoordinate.longitude,
                                         camera.centerCoordinateDistance,
                                         camera.heading,
                                         camera.pitch)
            parent.cameraPosition = .camera(
                MapCamera(
                    centerCoordinate: camera.centerCoordinate,
                    distance: camera.centerCoordinateDistance,
                    heading: camera.heading,
                    pitch: camera.pitch
                )
            )
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let multiPolyline = overlay as? StyledMultiPolyline {
                let renderer = MKMultiPolylineRenderer(multiPolyline: multiPolyline)
                applyStyle(multiPolyline.styleKey, to: renderer)
                renderer.alpha = parent.showOfficialRoutes ? 1.0 : 0.0
                return renderer
            }
            if let polyline = overlay as? StyledPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                applyStyle(polyline.styleKey, to: renderer)
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        private func applyStyle(_ styleKey: String, to renderer: MKOverlayPathRenderer) {
            renderer.lineCap = .round
            renderer.lineJoin = .round

            switch styleKey {
            case "paths":
                renderer.strokeColor = UIColor(red: 0.0, green: 0.90, blue: 0.46, alpha: 0.75)
                renderer.lineWidth = 4.5
            case "protected":
                renderer.strokeColor = UIColor(red: 0.0, green: 0.90, blue: 1.0, alpha: 0.75)
                renderer.lineWidth = 4.0
            case "lanes":
                renderer.strokeColor = UIColor(red: 0.16, green: 0.47, blue: 1.0, alpha: 0.75)
                renderer.lineWidth = 3.5
            case "designated":
                renderer.strokeColor = UIColor(red: 0.70, green: 0.53, blue: 1.0, alpha: 0.75)
                renderer.lineWidth = 3.5
            case "route", "history":
                renderer.strokeColor = UIColor(Color.primaryMint)
                renderer.lineWidth = styleKey == "route" ? 6.0 : 5.0
            default:
                renderer.strokeColor = UIColor(red: 0.56, green: 0.64, blue: 0.68, alpha: 0.72)
                renderer.lineWidth = 3.0
            }
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let annotation = annotation as? RoutePointAnnotation else { return nil }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: "RoutePointAnnotation", for: annotation) as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "RoutePointAnnotation")

            view.annotation = annotation
            view.canShowCallout = false
            view.isDraggable = annotation.kind == .start || annotation.kind == .destination || annotation.kind == .home
            view.glyphImage = glyphImage(for: annotation.kind)
            view.markerTintColor = markerColor(for: annotation.kind)
            view.glyphTintColor = .white
            view.displayPriority = annotation.kind == .user ? .required : .defaultHigh
            return view
        }

        func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, didChange newState: MKAnnotationView.DragState, fromOldState oldState: MKAnnotationView.DragState) {
            guard let annotation = view.annotation as? RoutePointAnnotation else { return }
            switch newState {
            case .dragging:
                handleDrag(annotation, ended: false)
            case .ending, .canceling:
                handleDrag(annotation, ended: true)
                view.setDragState(.none, animated: true)
            default:
                break
            }
        }

        private func handleDrag(_ annotation: RoutePointAnnotation, ended: Bool) {
            switch annotation.kind {
            case .start:
                ended ? parent.onStartDragEnded(annotation.coordinate) : parent.onStartDragChanged(annotation.coordinate)
            case .destination:
                ended ? parent.onEndDragEnded(annotation.coordinate) : parent.onEndDragChanged(annotation.coordinate)
            case .home:
                parent.onHomeDragChanged(annotation.coordinate)
            default:
                break
            }
        }

        private func glyphImage(for kind: MapAnnotationKind) -> UIImage? {
            switch kind {
            case .start:
                return UIImage(systemName: "location.fill")
            case .destination:
                return UIImage(systemName: "mappin")
            case .user:
                return UIImage(systemName: "location.north.fill")
            case .waypoint, .historyTick:
                return UIImage(systemName: "circle.fill")
            case .home:
                return UIImage(systemName: "house.fill")
            }
        }

        private func markerColor(for kind: MapAnnotationKind) -> UIColor {
            switch kind {
            case .start, .user, .historyTick:
                return UIColor(Color.primaryMint)
            case .destination:
                return UIColor(Color.errorRose)
            case .waypoint:
                return .white
            case .home:
                return UIColor(Color.mintGlow)
            }
        }

        private func rounded(_ value: CLLocationDegrees) -> String {
            String(format: "%.6f", value)
        }
    }
}
