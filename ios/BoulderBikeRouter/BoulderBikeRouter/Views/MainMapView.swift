import SwiftUI
import MapKit
import SwiftData

enum MapSelectionTarget {
    case start
    case end
}

struct MainMapView: View {
    var viewModel: MapViewModel
    @Binding var isDrawerOpen: Bool
    @State private var locationManager = LocationManager()
    @State private var navigationManager = NavigationManager()
    @Environment(\.modelContext) private var modelContext
    
    // UI state
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 40.015, longitude: -105.270), // Boulder
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
    )
    @State private var showSettingsModal: Bool = false
    @State private var isSearchExpanded: Bool = false
    @State private var mapSelectionMode: MapSelectionTarget? = nil
    @State private var startLocationText: String = ""
    @State private var endLocationText: String = ""
    @State private var startAutocompleteTask: Task<Void, Never>? = nil
    @State private var endAutocompleteTask: Task<Void, Never>? = nil

    var body: some View {
        ZStack(alignment: .bottom) {
            // 1. Native Map canvas
            MapReader { proxy in
                mapCanvas(proxy: proxy)
            }
            .ignoresSafeArea()

            // 2. Map HUD / UI Controls when navigation is NOT active
            if !navigationManager.isActive {
                // Top Search / Route Planner Bar
                VStack {
                    if let historyRoute = viewModel.selectedHistoryRoute {
                        historySelectionBanner(historyRoute)
                    } else if viewModel.isSelectingHomeLocation {
                        homeSelectionBanner
                    } else if mapSelectionMode != nil {
                        mapSelectionBanner
                    } else if isSearchExpanded {
                        routePlanningPanel
                    } else {
                        collapsedSearchBar
                    }
                    Spacer()
                }
                
                // Locate Me Button
                VStack {
                    HStack {
                        Spacer()
                        Button(action: locateUser) {
                            ZStack {
                                Circle()
                                    .fill(Color.surfaceElevated.opacity(0.95))
                                    .frame(width: 44, height: 44)
                                    .shadow(radius: 4)
                                    .overlay(Circle().stroke(Color.onSurfaceVariant.opacity(0.15), lineWidth: 1))
                                
                                Image(systemName: "location.fill")
                                    .foregroundColor(.primaryMint)
                                    .font(.title3)
                            }
                        }
                        .padding(.trailing, 16)
                        .padding(.bottom, viewModel.routeResponse != nil ? 140 : 40)
                    }
                }
                
                // Bottom Route Overview Card
                if viewModel.isSelectingHomeLocation {
                    homeSaveCard
                } else {
                    routeOverviewCard
                }
            } else {
                // 3. Navigation HUD Overlay
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
            if locationManager.authorizationStatus == .notDetermined {
                showSettingsModal = true
            } else {
                locationManager.startUpdating()
            }
            if let start = viewModel.startLocation {
                startLocationText = String(format: "%.4f, %.4f", start.latitude, start.longitude)
            }
            if let end = viewModel.endLocation {
                endLocationText = String(format: "%.4f, %.4f", end.latitude, end.longitude)
            }
            seedHomeSelectionFromCurrentLocation()
        }
        .onChange(of: locationManager.currentLocation) { _, newLocation in
            if let loc = newLocation {
                DispatchQueue.main.async {
                    viewModel.currentLocation = loc.coordinate
                    // Auto-initialize starting point to current location if not set yet
                    if viewModel.startLocation == nil {
                        viewModel.startLocation = loc.coordinate
                    }
                    
                    if navigationManager.isActive {
                        navigationManager.updateLocation(loc)
                        updateCameraHeading(loc)
                    }

                    if viewModel.isSelectingHomeLocation && viewModel.pendingHomeCoordinate == nil {
                        viewModel.updatePendingHomeLocation(loc.coordinate)
                        centerMap(on: loc.coordinate, spanDelta: 0.01)
                    }
                }
            }
        }
        .onChange(of: viewModel.isSelectingHomeLocation) { _, isSelecting in
            if isSelecting {
                seedHomeSelectionFromCurrentLocation()
            }
        }
        .onChange(of: viewModel.startLocation) { _, newLoc in
            DispatchQueue.main.async {
                if let loc = newLoc {
                    startLocationText = String(format: "%.4f, %.4f", loc.latitude, loc.longitude)
                } else {
                    startLocationText = ""
                }
            }
        }
        .onChange(of: viewModel.endLocation) { _, newLoc in
            DispatchQueue.main.async {
                if let loc = newLoc {
                    endLocationText = String(format: "%.4f, %.4f", loc.latitude, loc.longitude)
                } else {
                    endLocationText = ""
                }
            }
        }
        .onChange(of: viewModel.routeResponse) { _, newResponse in
            if newResponse != nil {
                DispatchQueue.main.async {
                    withAnimation {
                        isSearchExpanded = false
                    }
                }
            }
        }
        .onChange(of: viewModel.selectedHistoryRoute) { _, newRoute in
            if let route = newRoute {
                let startCoord = CLLocationCoordinate2D(latitude: route.startLat, longitude: route.startLon)
                let endCoord = CLLocationCoordinate2D(latitude: route.endLat, longitude: route.endLon)
                
                let centerLat = (startCoord.latitude + endCoord.latitude) / 2
                let centerLon = (startCoord.longitude + endCoord.longitude) / 2
                
                let latDelta = abs(startCoord.latitude - endCoord.latitude) * 1.5
                let lonDelta = abs(startCoord.longitude - endCoord.longitude) * 1.5
                
                DispatchQueue.main.async {
                    withAnimation {
                        cameraPosition = .region(
                            MKCoordinateRegion(
                                center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
                                span: MKCoordinateSpan(latitudeDelta: max(0.01, latDelta), longitudeDelta: max(0.01, lonDelta))
                            )
                        )
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func handleMapTap(at coordinate: CLLocationCoordinate2D) {
        guard let mode = mapSelectionMode else { return }
        withAnimation(.spring()) {
            switch mode {
            case .start:
                viewModel.setStartLocation(coordinate)
            case .end:
                viewModel.setEndLocation(coordinate)
            }
            mapSelectionMode = nil
        }
    }

    private func handleHomeMapTap(at coordinate: CLLocationCoordinate2D) {
        withAnimation(.spring()) {
            viewModel.updatePendingHomeLocation(coordinate)
        }
    }

    private func seedHomeSelectionFromCurrentLocation() {
        guard viewModel.isSelectingHomeLocation else { return }
        locationManager.requestAuthorization()
        locationManager.startUpdating()

        let coordinate = locationManager.currentLocation?.coordinate ?? viewModel.currentLocation
        if let coordinate {
            if viewModel.pendingHomeCoordinate == nil {
                viewModel.updatePendingHomeLocation(coordinate)
            }
            centerMap(on: coordinate, spanDelta: 0.01)
        }
    }

    private func centerMap(on coordinate: CLLocationCoordinate2D, spanDelta: CLLocationDegrees) {
        withAnimation {
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: spanDelta, longitudeDelta: spanDelta)
                )
            )
        }
    }

    private func currentStartCoordinate() -> CLLocationCoordinate2D? {
        locationManager.currentLocation?.coordinate
    }

    private func selectPlaygroundFromCurrent(_ playground: Playground) {
        if let current = currentStartCoordinate() {
            viewModel.setStartLocation(current)
        }
        viewModel.selectPlayground(playground)
    }

    private func locateUser() {
        locationManager.requestAuthorization()
        locationManager.startUpdating()
        
        if let userLoc = locationManager.currentLocation {
            centerMap(on: userLoc.coordinate, spanDelta: 0.02)
        }
    }

    private func startNavigation() {
        guard let route = viewModel.routeResponse else { return }
        
        let routeCoords = route.segments.flatMap { $0.clCoordinates }
        locationManager.setSimulationRoute(routeCoords)
        
        #if targetEnvironment(simulator)
        locationManager.isSimulating = true
        #else
        locationManager.isSimulating = false
        #endif
        
        navigationManager.start(segments: route.segments, modelContext: modelContext)
        locationManager.startUpdating()
    }

    private func stopNavigation() {
        // Record route in history list
        viewModel.recordCompletedRoute()
        
        navigationManager.stop()
        locationManager.stopUpdating()
        locationManager.isSimulating = false
        
        // Restore camera
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
        if let preset = viewModel.presets.first {
            viewModel.selectPreset(preset)
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
                    distance: 300,
                    heading: location.course >= 0 ? location.course : 0,
                    pitch: 60.0
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
        case "separated_path": return .primaryMint
        case "residential": return .primaryMint.opacity(0.8)
        case "sharrow_minor": return .secondary
        case "sidewalk": return .secondary.opacity(0.8)
        case "busy_with_lane": return .errorRose
        case "busy_with_sharrow": return .errorRose.opacity(0.8)
        default: return .onSurfaceVariant
        }
    }
    
    // MARK: - Route Planner Helpers
    
    private var collapsedSearchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.primaryMint)
            
            Text(viewModel.endLocation == nil ? "Where to?" : "Route Planned")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(viewModel.endLocation == nil ? .onSurfaceVariant : .onSurface)
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.surfaceElevated.opacity(0.95))
        .cornerRadius(24)
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.onSurfaceVariant.opacity(0.15), lineWidth: 1))
        .onTapGesture {
            withAnimation(.spring()) {
                isSearchExpanded = true
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 50)
    }
    
    private var routePlanningPanel: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Route Planner")
                    .font(.headline)
                    .foregroundColor(.mintGlow)
                
                Spacer()
                
                Button(action: {
                    withAnimation(.spring()) {
                        isSearchExpanded = false
                    }
                }) {
                    Image(systemName: "xmark")
                        .foregroundColor(.onSurfaceVariant)
                        .padding(6)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
            }
            
            VStack(spacing: 12) {
                // Start Location Input Row
                HStack(spacing: 10) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 8))
                        .foregroundColor(.primaryMint)
                    
                    TextField("Start Location (lat, lon)", text: $startLocationText, onCommit: {
                        if let coord = parseCoordinate(from: startLocationText) {
                            viewModel.setStartLocation(coord)
                        }
                    })
                    .onChange(of: startLocationText) { _, newValue in
                        schedulePlaceAutocomplete(target: "start", query: newValue)
                    }
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 14))
                    .foregroundColor(.onSurface)
                    
                    Spacer()
                    
                    Button(action: {
                        if let userLoc = locationManager.currentLocation {
                            viewModel.setStartLocation(userLoc.coordinate)
                        }
                    }) {
                        Image(systemName: "location.fill")
                            .foregroundColor(.primaryMint)
                    }

                    Button(action: {
                        if let home = viewModel.homeLocation {
                            viewModel.setStartLocation(home.coordinate)
                        }
                    }) {
                        Image(systemName: "house.fill")
                            .foregroundColor(viewModel.homeLocation == nil ? .onSurfaceVariant : .primaryMint)
                    }
                    .disabled(viewModel.homeLocation == nil)

                    Button(action: {
                        withAnimation {
                            mapSelectionMode = .start
                        }
                    }) {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundColor(mapSelectionMode == .start ? .mintGlow : .onSurfaceVariant)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.forestDeep.opacity(0.5))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.onSurfaceVariant.opacity(0.15), lineWidth: 1))

                placeSuggestionList(
                    viewModel.startPlaceSuggestions,
                    target: "start",
                    searchCompleted: viewModel.startPlaceSearchCompleted,
                    query: viewModel.startPlaceSearchQuery
                )
                
                // End Location Input Row
                HStack(spacing: 10) {
                    Image(systemName: "square.fill")
                        .font(.system(size: 8))
                        .foregroundColor(.errorRose)
                    
                    TextField("Destination (lat, lon)", text: $endLocationText, onCommit: {
                        if let coord = parseCoordinate(from: endLocationText) {
                            viewModel.setEndLocation(coord)
                        }
                    })
                    .onChange(of: endLocationText) { _, newValue in
                        schedulePlaceAutocomplete(target: "end", query: newValue)
                    }
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 14))
                    .foregroundColor(.onSurface)
                    
                    Spacer()
                    
                    Menu {
                        ForEach(viewModel.playgroundsList) { pg in
                            Button(pg.name) {
                                selectPlaygroundFromCurrent(pg)
                            }
                        }
                    } label: {
                        Image(systemName: "figure.play")
                            .foregroundColor(.primaryMint)
                    }

                    Button(action: {
                        viewModel.routeToHome(from: currentStartCoordinate())
                    }) {
                        Image(systemName: "house.fill")
                            .foregroundColor(viewModel.homeLocation == nil ? .onSurfaceVariant : .primaryMint)
                    }
                    .disabled(viewModel.homeLocation == nil)
                    
                    Button(action: {
                        withAnimation {
                            mapSelectionMode = .end
                        }
                    }) {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundColor(mapSelectionMode == .end ? .mintGlow : .onSurfaceVariant)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.forestDeep.opacity(0.5))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.onSurfaceVariant.opacity(0.15), lineWidth: 1))

                placeSuggestionList(
                    viewModel.endPlaceSuggestions,
                    target: "end",
                    searchCompleted: viewModel.endPlaceSearchCompleted,
                    query: viewModel.endPlaceSearchQuery
                )
            }
        }
        .padding(16)
        .background(Color.surfaceElevated.opacity(0.95))
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.onSurfaceVariant.opacity(0.15), lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.top, 50)
    }

    @ViewBuilder
    private func placeSuggestionList(_ suggestions: [PlaceSuggestion], target: String, searchCompleted: Bool, query: String) -> some View {
        if !suggestions.isEmpty || searchCompleted {
            VStack(spacing: 0) {
                if suggestions.isEmpty {
                    Text(query.isEmpty ? "0 results found" : "0 results found for \"\(query)\"")
                        .font(.system(size: 13))
                        .foregroundColor(.onSurfaceVariant)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                } else {
                    ForEach(suggestions) { suggestion in
                        Button(action: {
                            viewModel.selectPlaceSuggestion(suggestion, target: target)
                        }) {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(suggestion.name)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.onSurface)
                                        .lineLimit(1)

                                    Text(suggestion.type)
                                        .font(.system(size: 11))
                                        .foregroundColor(.onSurfaceVariant)
                                        .lineLimit(1)
                                }

                                Spacer()

                                Image(systemName: "mappin.circle")
                                    .font(.system(size: 14))
                                    .foregroundColor(.primaryMint)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                        }
                        .buttonStyle(.plain)

                        if suggestion.id != suggestions.last?.id {
                            Divider()
                                .background(Color.onSurfaceVariant.opacity(0.15))
                        }
                    }
                }
            }
            .background(Color.forestDeep.opacity(0.92))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primaryMint.opacity(0.16), lineWidth: 1))
        }
    }

    private func schedulePlaceAutocomplete(target: String, query: String) {
        if parseCoordinate(from: query) != nil {
            Task { @MainActor in
                viewModel.clearPlaceSuggestions(target: target)
            }
            return
        }

        if target == "start" {
            startAutocompleteTask?.cancel()
            startAutocompleteTask = Task {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled else { return }
                await viewModel.searchPlaces(query: query, target: target)
            }
        } else {
            endAutocompleteTask?.cancel()
            endAutocompleteTask = Task {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled else { return }
                await viewModel.searchPlaces(query: query, target: target)
            }
        }
    }
    
    private func historySelectionBanner(_ route: PastRoute) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundColor(.mintGlow)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(route.name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.onSurface)
                Text(String(format: "Actual: %.2f mi (Time: %d min)", route.distanceMiles, route.durationSeconds / 60))
                    .font(.system(size: 11))
                    .foregroundColor(.onSurfaceVariant)
            }
            
            Spacer()
            
            Button("Back") {
                withAnimation {
                    viewModel.clearHistorySelection()
                }
                NotificationCenter.default.post(name: NSNotification.Name("HistoryRouteMapBack"), object: route)
            }
            .font(.system(size: 14, weight: .bold))
            .foregroundColor(.errorRose)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.surfaceElevated.opacity(0.95))
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.onSurfaceVariant.opacity(0.15), lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.top, 50)
    }

    private var mapSelectionBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "mappin.and.ellipse")
                .foregroundColor(.mintGlow)
            
            Text(mapSelectionMode == .start ? "Tap Map to Set Start Location" : "Tap Map to Set Destination")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.onSurface)
            
            Spacer()
            
            Button("Cancel") {
                withAnimation {
                    mapSelectionMode = nil
                }
            }
            .font(.system(size: 14, weight: .bold))
            .foregroundColor(.errorRose)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.surfaceElevated.opacity(0.95))
        .cornerRadius(24)
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.onSurfaceVariant.opacity(0.15), lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.top, 50)
    }

    private var homeSelectionBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "house.fill")
                .foregroundColor(.mintGlow)

            Text("Tap Map to Set Home Location")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.onSurface)

            Spacer()

            Button("Cancel") {
                withAnimation {
                    viewModel.cancelHomeLocationSelection()
                }
            }
            .font(.system(size: 14, weight: .bold))
            .foregroundColor(.errorRose)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.surfaceElevated.opacity(0.95))
        .cornerRadius(24)
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.onSurfaceVariant.opacity(0.15), lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.top, 50)
    }

    @ViewBuilder
    private var homeSaveCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Set Home")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.onSurface)
                    Text(homePendingText)
                        .font(.system(size: 12))
                        .foregroundColor(.onSurfaceVariant)
                }

                Spacer()
            }

            HStack(spacing: 10) {
                Button("Cancel") {
                    viewModel.cancelHomeLocationSelection()
                }
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.onSurface)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.08))
                .cornerRadius(12)

                Button(action: {
                    guard let coordinate = viewModel.pendingHomeCoordinate else { return }
                    Task {
                        await viewModel.saveHomeLocation(coordinate)
                        if viewModel.homeLocationError == nil {
                            NotificationCenter.default.post(name: NSNotification.Name("HomeLocationSaved"), object: nil)
                        }
                    }
                }) {
                    Text(viewModel.isSavingHomeLocation ? "Saving..." : "Save")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.surfaceDim)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(viewModel.pendingHomeCoordinate == nil ? Color.onSurfaceVariant : Color.primaryMint)
                        .cornerRadius(12)
                }
                .disabled(viewModel.pendingHomeCoordinate == nil || viewModel.isSavingHomeLocation)
            }
        }
        .padding(16)
        .background(Color.surfaceElevated.opacity(0.95))
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.onSurfaceVariant.opacity(0.15), lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
    }

    private var homePendingText: String {
        guard let coordinate = viewModel.pendingHomeCoordinate else {
            return "Drop a pin on the map."
        }
        return String(format: "%.6f, %.6f", coordinate.latitude, coordinate.longitude)
    }
    
    private var routeTitle: String {
        viewModel.selectedPresetName ?? viewModel.selectedPlayground?.name ?? "Custom Route"
    }

    @ViewBuilder
    private var routeOverviewCard: some View {
        if let route = viewModel.routeResponse {
            let miles = route.totalLengthMeters / 1609.34
            let minutes = Int(miles * 5)
            VStack(spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(routeTitle)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.onSurface)
                        
                        HStack(spacing: 12) {
                            Text("\(minutes) min")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.primaryMint)
                            
                            Text(String(format: "%.1f miles", miles))
                                .font(.system(size: 14))
                                .foregroundColor(.onSurfaceVariant)
                        }
                    }
                    Spacer()
                    
                    Button(action: startNavigation) {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill")
                            Text("Start")
                        }
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.surfaceDim)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 20)
                        .background(Color.primaryMint)
                        .cornerRadius(24)
                        .shadow(color: Color.primaryMint.opacity(0.3), radius: 6, x: 0, y: 3)
                    }
                }
            }
            .padding(20)
            .background(Color.surfaceElevated.opacity(0.95))
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.onSurfaceVariant.opacity(0.15), lineWidth: 1))
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
    
    @ViewBuilder
    private func mapCanvas(proxy: MapProxy) -> some View {
        Map(position: $cameraPosition, interactionModes: .all) {
            if !viewModel.isSelectingHomeLocation {
                // Start Marker
                if let start = viewModel.startLocation {
                    Annotation("Start", coordinate: start, anchor: .bottom) {
                        markerView(color: .primaryMint)
                    }
                } else if let historyRoute = viewModel.selectedHistoryRoute {
                    Annotation("Start", coordinate: CLLocationCoordinate2D(latitude: historyRoute.startLat, longitude: historyRoute.startLon), anchor: .bottom) {
                        markerView(color: .primaryMint)
                    }
                }

                // Destination Marker
                if let end = viewModel.endLocation {
                    Annotation("Destination", coordinate: end, anchor: .bottom) {
                        markerView(color: .errorRose)
                    }
                } else if let historyRoute = viewModel.selectedHistoryRoute {
                    Annotation("Destination", coordinate: CLLocationCoordinate2D(latitude: historyRoute.endLat, longitude: historyRoute.endLon), anchor: .bottom) {
                        markerView(color: .errorRose)
                    }
                }

                // Render computed route path polylines
                if let route = viewModel.routeResponse {
                    ForEach(route.segments) { segment in
                        MapPolyline(coordinates: segment.clCoordinates)
                            .stroke(infraColor(for: segment.type), lineWidth: 6)
                    }
                } else if let details = viewModel.selectedHistoryRouteDetails {
                    ForEach(0..<details.plannedRouteCoordinates.count, id: \.self) { pathIdx in
                        MapPolyline(coordinates: details.plannedRouteCoordinates[pathIdx])
                            .stroke(Color.secondary, lineWidth: 4)
                    }

                    let tickCoordinates = viewModel.selectedHistoryRouteTicks.map { $0.clCoordinate }
                    if tickCoordinates.count >= 2 {
                        MapPolyline(coordinates: tickCoordinates)
                            .stroke(Color.orange, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    } else if let tickCoordinate = tickCoordinates.first {
                        Annotation("", coordinate: tickCoordinate) {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 8, height: 8)
                                .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                                .shadow(radius: 2)
                        }
                    }
                }

                // Render waypoints as minor circles
                ForEach(0..<viewModel.waypoints.count, id: \.self) { idx in
                    Annotation("", coordinate: viewModel.waypoints[idx]) {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 8, height: 8)
                            .shadow(radius: 2)
                    }
                }
            }

            // User Location Dot
            if let userLoc = locationManager.currentLocation {
                Annotation("User Location", coordinate: userLoc.coordinate) {
                    UserLocationMarker(heading: locationManager.currentHeading)
                }
            }

            if let pendingHome = viewModel.pendingHomeCoordinate {
                Annotation("Home", coordinate: pendingHome, anchor: .bottom) {
                    markerView(color: .mintGlow)
                        .gesture(
                            DragGesture(coordinateSpace: .named("mapCanvas"))
                                .onChanged { value in
                                    if let coordinate = proxy.convert(value.location, from: .local) {
                                        viewModel.updatePendingHomeLocation(coordinate)
                                    }
                                }
                        )
                }
            }
        }
        .coordinateSpace(name: "mapCanvas")
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
        .onTapGesture { screenPoint in
            if viewModel.isSelectingHomeLocation {
                if let coordinate = proxy.convert(screenPoint, from: .local) {
                    handleHomeMapTap(at: coordinate)
                }
            } else if mapSelectionMode != nil {
                if let coordinate = proxy.convert(screenPoint, from: .local) {
                    handleMapTap(at: coordinate)
                }
            }
        }
    }
    
    private func parseCoordinate(from text: String) -> CLLocationCoordinate2D? {
        let parts = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if parts.count == 2,
           let lat = Double(parts[0]),
           let lon = Double(parts[1]) {
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        return nil
    }
}

// MARK: - Subviews: User Location Marker

struct UserLocationMarker: View {
    let heading: Double

    var body: some View {
        ZStack {
            Image(systemName: "triangle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 14, height: 14)
                .foregroundColor(.primaryMint)
                .opacity(0.7)
                .offset(y: -12)
                .rotationEffect(.degrees(heading))
            
            Circle()
                .fill(Color.white)
                .frame(width: 16, height: 16)
                .shadow(radius: 3)
            
            Circle()
                .fill(Color.primaryMint)
                .frame(width: 10, height: 10)
        }
    }
}
