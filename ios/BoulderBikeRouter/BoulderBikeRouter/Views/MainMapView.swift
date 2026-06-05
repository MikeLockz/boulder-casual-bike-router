import SwiftUI
import MapKit

struct MainMapView: View {
    @State private var viewModel = MapViewModel()
    @State private var locationManager = LocationManager()
    @State private var navigationManager = NavigationManager()
    
    // UI state
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 40.015, longitude: -105.270), // Boulder
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
    )
    @State private var isPanelCollapsed: Bool = false
    @State private var showSettingsModal: Bool = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // 1. Native Map canvas
            MapReader { proxy in
                Map(position: $cameraPosition, interactionModes: .all) {
                    // Start Marker
                    if let start = viewModel.startLocation {
                        Annotation("Start", coordinate: start, anchor: .bottom) {
                            markerView(color: .emeraldGreen)
                        }
                    }
                    
                    // Destination Marker
                    if let end = viewModel.endLocation {
                        Annotation("Destination", coordinate: end, anchor: .bottom) {
                            markerView(color: .crimsonRed)
                        }
                    }

                    // Render computed route path polylines
                    if let route = viewModel.routeResponse {
                        ForEach(route.segments) { segment in
                            MapPolyline(coordinates: segment.clCoordinates)
                                .stroke(infraColor(for: segment.type), lineWidth: 6)
                        }
                    }

                    // Render waypoints as minor circles
                    ForEach(0..<viewModel.waypoints.count, id: \.self) { idx in
                        Annotation("", coordinate: viewModel.waypoints[idx]) {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 10, height: 10)
                                .shadow(radius: 2)
                        }
                    }

                    // User Location Dot
                    if let userLoc = locationManager.currentLocation {
                        Annotation("User Location", coordinate: userLoc.coordinate) {
                            UserLocationMarker(heading: locationManager.currentHeading)
                        }
                    }
                }
                .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
                .onTapGesture { screenPoint in
                    // Tap to set markers
                    if let coordinate = proxy.convert(screenPoint, from: .local) {
                        handleMapTap(at: coordinate)
                    }
                }
            }
            .ignoresSafeArea()

            // 2. Locate Me Button (floating on map)
            if !navigationManager.isActive {
                VStack {
                    HStack {
                        Spacer()
                        Button(action: locateUser) {
                            ZStack {
                                Circle()
                                    .fill(Color(white: 0.15).opacity(0.85))
                                    .frame(width: 44, height: 44)
                                    .shadow(radius: 4)
                                
                                Image(systemName: "location.fill")
                                    .foregroundColor(.white)
                                    .font(.title3)
                            }
                        }
                        .padding(.trailing, 16)
                        .padding(.top, 60) // Safe Area margin
                    }
                    Spacer()
                }
            }

            // 3. Control Panel overlay (slide-over sheet)
            if !navigationManager.isActive {
                VStack {
                    Spacer()
                    ControlPanelView(
                        isCollapsed: $isPanelCollapsed,
                        selectedPresetId: $viewModel.selectedPresetName,
                        selectedPlayground: $viewModel.selectedPlayground,
                        presets: viewModel.presets,
                        weightsMetadata: viewModel.weightsMetadata,
                        playgrounds: viewModel.playgroundsList,
                        weights: $viewModel.weights,
                        isWeightsLocked: viewModel.isWeightsLocked,
                        onResetWeights: { viewModel.resetWeights() },
                        showOfficialRoutes: $viewModel.showOfficialRoutesLayer,
                        routeDistance: viewModel.routeResponse.map { $0.totalLengthMeters / 1609.34 },
                        routeCost: viewModel.routeResponse?.totalWeight,
                        maneuvers: navigationManager.maneuvers,
                        onStartNavigation: startNavigation,
                        onSelectPreset: { viewModel.selectPreset($0) }
                    )
                    .frame(maxHeight: isPanelCollapsed ? 80 : 500)
                }
            } else {
                // 4. Navigation HUD Overlay
                NavigationOverlayView(
                    maneuver: navigationManager.currentBannerManeuver,
                    distanceToNext: navigationManager.distanceToNextManeuverString,
                    remainingDistance: navigationManager.remainingDistanceString,
                    eta: navigationManager.etaString,
                    isMuted: navigationManager.isMuted,
                    isSimulating: locationManager.isSimulating,
                    onMuteToggle: { navigationManager.toggleMute() },
                    onExit: stopNavigation
                )
            }

            // Onboarding permission guide modal
            if showSettingsModal {
                WelcomeModalView(
                    onUseLocation: {
                        showSettingsModal = false
                        locationManager.isSimulating = false
                        locationManager.requestAuthorization()
                        locationManager.startUpdating()
                    },
                    onExploreDemo: {
                        showSettingsModal = false
                        startDemoReplay()
                    }
                )
            }
        }
        .onAppear {
            Task {
                await viewModel.loadConfiguration()
                if locationManager.authorizationStatus == .notDetermined {
                    showSettingsModal = true
                } else {
                    locationManager.startUpdating()
                }
            }
        }
        .onChange(of: locationManager.currentLocation) { _, newLocation in
            if let loc = newLocation {
                if navigationManager.isActive {
                    navigationManager.updateLocation(loc)
                    updateCameraHeading(loc)
                }
            }
        }
    }

    // MARK: - Actions

    private func handleMapTap(at coordinate: CLLocationCoordinate2D) {
        if viewModel.startLocation == nil {
            viewModel.setStartLocation(coordinate)
        } else if viewModel.endLocation == nil {
            viewModel.setEndLocation(coordinate)
        } else {
            // Already have both, reset to new start
            viewModel.startLocation = coordinate
            viewModel.endLocation = nil
            viewModel.routeResponse = nil
        }
    }

    private func locateUser() {
        locationManager.requestAuthorization()
        locationManager.startUpdating()
        
        if let userLoc = locationManager.currentLocation {
            withAnimation {
                cameraPosition = .region(
                    MKCoordinateRegion(
                        center: userLoc.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                    )
                )
            }
        }
    }

    private func startNavigation() {
        guard let route = viewModel.routeResponse else { return }
        
        let routeCoords = route.segments.flatMap { $0.clCoordinates }
        locationManager.setSimulationRoute(routeCoords)
        
        // Start simulated replay if in simulator, otherwise live GPS
        #if targetEnvironment(simulator)
        locationManager.isSimulating = true
        #else
        locationManager.isSimulating = false
        #endif
        
        navigationManager.start(segments: route.segments)
        locationManager.startUpdating()
    }

    private func stopNavigation() {
        navigationManager.stop()
        locationManager.stopUpdating()
        locationManager.isSimulating = false
        
        // Restore normal camera overview
        if let start = viewModel.startLocation {
            withAnimation {
                cameraPosition = .region(
                    MKCoordinateRegion(
                        center: start,
                        span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
                    )
                )
            }
        }
    }

    private func startDemoReplay() {
        // Load default North Boulder preset
        if let preset = viewModel.presets.first {
            viewModel.selectPreset(preset)
            
            // Wait shortly for route calculation then navigate
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.locationManager.isSimulating = true
                self.startNavigation()
            }
        }
    }

    private func updateCameraHeading(_ location: CLLocation) {
        withAnimation(.easeInOut) {
            cameraPosition = .camera(
                MapCamera(
                    centerCoordinate: location.coordinate,
                    distance: 300, // Close up 3D view
                    heading: location.course >= 0 ? location.course : 0,
                    pitch: 60.0 // 3D tilt view
                )
            )
        }
    }

    // MARK: - Helpers

    private func markerView(color: Color) -> some View {
        Image(systemName: "mappin.circle.fill")
            .font(.title)
            .foregroundColor(color)
            .background(Color.white.clipShape(Circle()))
            .shadow(radius: 4)
    }

    private func infraColor(for type: String) -> Color {
        switch type {
        case "separated_path": return .emeraldGreen
        case "residential": return .emeraldGreen.opacity(0.8)
        case "sharrow_minor": return .amberGold
        case "sidewalk": return .cyanTeal
        case "busy_with_lane": return .deepOrange
        case "busy_with_sharrow": return .crimsonRed
        default: return .purpleAccent
        }
    }
}

// MARK: - Subviews: User Location Marker

struct UserLocationMarker: View {
    let heading: Double

    var body: some View {
        ZStack {
            // Directional heading cone
            Image(systemName: "triangle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .foregroundColor(.cyanTeal)
                .opacity(0.7)
                .offset(y: -14)
                .rotationEffect(.degrees(heading))
            
            // Center location dot
            Circle()
                .fill(Color.white)
                .frame(width: 18, height: 18)
                .shadow(radius: 3)
            
            Circle()
                .fill(Color.cyanTeal)
                .frame(width: 12, height: 12)
        }
    }
}
