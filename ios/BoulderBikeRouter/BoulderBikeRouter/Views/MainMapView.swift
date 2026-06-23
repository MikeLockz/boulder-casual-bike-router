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
    @Binding var isNavigationActive: Bool
    @State private var locationManager = LocationManager()
    @State private var navigationManager = NavigationManager()
    @Environment(\.modelContext) private var modelContext
    
    // UI state
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 40.015, longitude: -105.270), // Boulder
            span: MKCoordinateSpan(latitudeDelta: 0.025, longitudeDelta: 0.025)
        )
    )
    @State private var showSettingsModal: Bool = false
    @State private var isSearchExpanded: Bool = false
    @State private var mapSelectionMode: MapSelectionTarget? = nil
    @State private var hasCenteredInitialLocation: Bool = false
    @State private var startLocationText: String = ""
    @State private var endLocationText: String = ""
    @State private var startAutocompleteTask: Task<Void, Never>? = nil
    @State private var endAutocompleteTask: Task<Void, Never>? = nil
    @State private var suppressNextStartAutocomplete: Bool = false
    @State private var suppressNextEndAutocomplete: Bool = false
    @State private var showPlaygroundList: Bool = false
    @State private var keyboardHeight: CGFloat = 0
    @State private var endRowBottomY: CGFloat = 0
    @FocusState private var focusedField: SearchField?

    private var listMaxHeight: CGFloat {
        guard endRowBottomY > 0 else { return 260 }
        let available = UIScreen.main.bounds.height - keyboardHeight - endRowBottomY - 16
        return max(80, available)
    }

    private enum SearchField { case start, destination }

    private var shouldHideRouteOverviewForSearch: Bool {
        keyboardHeight > 0 && focusedField != nil
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // 1. Native Map canvas
            mapCanvas()
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
                            .onPreferenceChange(EndRowBottomKey.self) { value in
                                guard abs(endRowBottomY - value) > 0.5 else { return }
                                endRowBottomY = value
                            }
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
                    if !shouldHideRouteOverviewForSearch {
                        routeOverviewCard
                    }
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
                if let name = viewModel.selectedStartName, !name.isEmpty {
                    startLocationText = name
                } else if let home = viewModel.homeLocation,
                          coordinateDistance(start, to: home.coordinate) <= 20 {
                    startLocationText = "Home"
                } else {
                    startLocationText = String(format: "%.4f, %.4f", start.latitude, start.longitude)
                }
            }
            if let end = viewModel.endLocation {
                if let name = viewModel.selectedDestinationName, !name.isEmpty {
                    endLocationText = name
                } else if let home = viewModel.homeLocation,
                          coordinateDistance(end, to: home.coordinate) <= 50 {
                    endLocationText = "Home"
                } else {
                    endLocationText = String(format: "%.4f, %.4f", end.latitude, end.longitude)
                }
            }
            seedHomeSelectionFromCurrentLocation()
            // MainMapView is recreated on every tab switch, so onChange won't fire for
            // state that was already set before this view appeared (e.g. navigating from
            // History > View on Map). Fit the camera here to cover that case.
            DispatchQueue.main.async {
                if let route = viewModel.selectedHistoryRoute {
                    let startCoord = CLLocationCoordinate2D(latitude: route.startLat, longitude: route.startLon)
                    let endCoord = CLLocationCoordinate2D(latitude: route.endLat, longitude: route.endLon)
                    fitMap(to: historyFitCoordinates(start: startCoord, end: endCoord), insets: .historyBanner)
                } else if viewModel.routeResponse != nil {
                    fitMap(to: routeFitCoordinates(for: viewModel.routeResponse), insets: .routeCard)
                } else if viewModel.hasManualRegionSelection {
                    centerMapOnActiveRegion()
                }
            }
        }
        .task(id: viewModel.activeRegionId) {
            if viewModel.showOfficialRoutesLayer {
                await viewModel.loadBikeRouteOverlays()
            }
        }
        .onChange(of: locationManager.currentLocation) { _, newLocation in
            if let loc = newLocation {
                DispatchQueue.main.async {
                    viewModel.currentLocation = loc.coordinate
                    viewModel.selectAutomaticRegion(for: loc.coordinate)
                    // Auto-initialize starting point to current location if not set yet
                    if viewModel.startLocation == nil,
                       viewModel.routingRegions.first(where: { $0.id == viewModel.activeRegionId })?.contains(loc.coordinate) == true {
                        viewModel.setStartLocation(loc.coordinate, startName: nil)
                    }

                    if !hasCenteredInitialLocation && !viewModel.hasManualRegionSelection && viewModel.routeResponse == nil && viewModel.selectedHistoryRoute == nil && !viewModel.isSelectingHomeLocation && mapSelectionMode == nil {
                        hasCenteredInitialLocation = true
                        centerMap(on: loc.coordinate, spanDelta: 0.015)
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
        .onChange(of: viewModel.activeRegionId) { _, _ in
            centerMapOnActiveRegion()
        }
        .onChange(of: viewModel.startLocation) { _, newLoc in
            DispatchQueue.main.async {
                if let loc = newLoc {
                    if let name = viewModel.selectedStartName, !name.isEmpty {
                        suppressNextStartAutocomplete = true
                        startLocationText = name
                    } else if let home = viewModel.homeLocation,
                              coordinateDistance(loc, to: home.coordinate) <= 20 {
                        startLocationText = "Home"
                    } else {
                        startLocationText = String(format: "%.4f, %.4f", loc.latitude, loc.longitude)
                    }
                } else {
                    startLocationText = ""
                }
            }
        }
        .onChange(of: viewModel.homeLocation) { _, newHome in
            guard let home = newHome else { return }
            DispatchQueue.main.async {
                if let startLoc = viewModel.startLocation,
                   coordinateDistance(startLoc, to: home.coordinate) <= 20 {
                    viewModel.selectedStartName = "Home"
                }
                if let endLoc = viewModel.endLocation,
                   coordinateDistance(endLoc, to: home.coordinate) <= 50 {
                    viewModel.selectedDestinationName = "Home"
                }
            }
        }
        .onChange(of: viewModel.endLocation) { _, newLoc in
            DispatchQueue.main.async {
                if let loc = newLoc {
                    if let name = viewModel.selectedDestinationName, !name.isEmpty {
                        suppressNextEndAutocomplete = true
                        endLocationText = name
                    } else if let home = viewModel.homeLocation,
                               coordinateDistance(loc, to: home.coordinate) <= 50 {
                        endLocationText = "Home"
                    } else {
                        endLocationText = String(format: "%.4f, %.4f", loc.latitude, loc.longitude)
                    }
                } else {
                    endLocationText = ""
                }
            }
        }
        .onChange(of: viewModel.selectedDestinationName) { _, newName in
            if let newName, !newName.isEmpty {
                DispatchQueue.main.async {
                    suppressNextEndAutocomplete = true
                    endLocationText = newName
                }
            }
        }
        .onChange(of: viewModel.selectedStartName) { _, newName in
            if let newName, !newName.isEmpty {
                DispatchQueue.main.async {
                    suppressNextStartAutocomplete = true
                    startLocationText = newName
                }
            }
        }
        .onChange(of: viewModel.routeResponse) { _, newResponse in
            if newResponse != nil {
                DispatchQueue.main.async {
                    withAnimation {
                        isSearchExpanded = false
                    }
                    fitMap(to: routeFitCoordinates(for: newResponse), insets: .routeCard)
                }
            }
        }
        .onChange(of: viewModel.selectedHistoryRoute) { _, newRoute in
            if let route = newRoute {
                let startCoord = CLLocationCoordinate2D(latitude: route.startLat, longitude: route.startLon)
                let endCoord = CLLocationCoordinate2D(latitude: route.endLat, longitude: route.endLon)

                DispatchQueue.main.async {
                    fitMap(to: historyFitCoordinates(start: startCoord, end: endCoord), insets: .historyBanner)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notif in
            if let frame = notif.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                withAnimation(.easeOut(duration: 0.25)) { keyboardHeight = frame.height }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            focusedField = nil
            withAnimation(.easeOut(duration: 0.25)) { keyboardHeight = 0 }
        }
        .onChange(of: navigationManager.isActive) { _, isActive in
            isNavigationActive = isActive
            locationManager.setBackgroundNavigationEnabled(isActive)
            if !isActive {
                locationManager.stopUpdating()
                locationManager.isSimulating = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RouteRerouted"))) { notification in
            if let newRoute = notification.object as? RouteResponse {
                if locationManager.isSimulating {
                    let routeCoords = newRoute.continuousCoordinates
                    locationManager.setSimulationRoute(routeCoords)
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

    private func centerMapOnActiveRegion() {
        guard let region = viewModel.routingRegions.first(where: { $0.id == viewModel.activeRegionId }),
              region.center.count == 2 else { return }
        hasCenteredInitialLocation = true
        centerMap(
            on: CLLocationCoordinate2D(latitude: region.center[0], longitude: region.center[1]),
            spanDelta: 0.12
        )
    }

    private func fitMap(to coordinates: [CLLocationCoordinate2D], insets: MapFitInsets) {
        guard let region = RouteMapCamera.region(
            for: coordinates,
            screenSize: UIScreen.main.bounds.size,
            insets: insets
        ) else { return }
        withAnimation { cameraPosition = .region(region) }
    }

    private func routeFitCoordinates(for route: RouteResponse?) -> [CLLocationCoordinate2D] {
        guard let route else { return [] }
        return route.continuousCoordinates + routeMarkerCoordinates
    }

    private func historyFitCoordinates(start: CLLocationCoordinate2D, end: CLLocationCoordinate2D) -> [CLLocationCoordinate2D] {
        let actual = viewModel.selectedHistoryRouteDetails?.actualRouteCoordinatePath ?? []
        return actual
    }

    private var routeMarkerCoordinates: [CLLocationCoordinate2D] {
        [viewModel.startLocation, viewModel.endLocation].compactMap { $0 } + viewModel.waypoints
    }

    private func currentStartCoordinate() -> CLLocationCoordinate2D? {
        locationManager.currentLocation?.coordinate
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
        
        let routeCoords = route.continuousCoordinates
        locationManager.setSimulationRoute(routeCoords)
        
        #if targetEnvironment(simulator)
        locationManager.isSimulating = true
        #else
        locationManager.isSimulating = false
        #endif

        let navigationDestinationName = routeTitle == "Custom Route" ? nil : routeTitle
        navigationManager.start(
            segments: route.segments,
            modelContext: modelContext,
            region: viewModel.activeRegionId,
            startNearName: viewModel.selectedStartName,
            endNearName: viewModel.selectedDestinationName,
            destinationName: navigationDestinationName,
            weights: viewModel.weights,
            offsets: viewModel.routeOffsets.isEmpty ? nil : viewModel.routeOffsets
        )
        isNavigationActive = navigationManager.isActive
        locationManager.setBackgroundNavigationEnabled(navigationManager.isActive)
        locationManager.startUpdating()
    }

    private func stopNavigation() {
        // Record route in history list
        viewModel.recordCompletedRoute()
        
        navigationManager.stop()
        isNavigationActive = navigationManager.isActive
        locationManager.setBackgroundNavigationEnabled(false)
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
        let computedHeading = calculateCameraHeading(for: location)
        withAnimation(.easeInOut) {
            cameraPosition = .camera(
                MapCamera(
                    centerCoordinate: location.coordinate,
                    distance: 300,
                    heading: computedHeading,
                    pitch: 60.0
                )
            )
        }
    }

    private func calculateCameraHeading(for location: CLLocation) -> CLLocationDirection {
        let speed = location.speed >= 0 ? location.speed : 0.0
        let gpsCourse = location.course
        let compassHeading = locationManager.currentHeading
        
        // If GPS course is invalid/negative, default to compass heading
        guard gpsCourse >= 0 else {
            return compassHeading
        }
        
        // Define thresholds (in meters per second):
        // 1.5 m/s is ~3.3 MPH
        // 3.5 m/s is ~7.8 MPH
        let minSpeedForGps: Double = 1.5
        let maxSpeedForGps: Double = 3.5
        
        if speed < minSpeedForGps {
            return compassHeading
        } else if speed > maxSpeedForGps {
            return gpsCourse
        } else {
            // Linear blend using unit vectors to avoid 0/360 wrap issues
            let gpsWeight = (speed - minSpeedForGps) / (maxSpeedForGps - minSpeedForGps)
            let compassWeight = 1.0 - gpsWeight
            
            let gpsRad = gpsCourse * .pi / 180.0
            let compassRad = compassHeading * .pi / 180.0
            
            let x = cos(gpsRad) * gpsWeight + cos(compassRad) * compassWeight
            let y = sin(gpsRad) * gpsWeight + sin(compassRad) * compassWeight
            
            var blended = atan2(y, x) * 180.0 / .pi
            if blended < 0 {
                blended += 360.0
            }
            return blended
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

    // MARK: - Route Planner Helpers
    
    private var collapsedSearchBar: some View {
        HStack {
            Button(action: {
                withAnimation(.spring()) {
                    isSearchExpanded = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    focusedField = .destination
                }
            }) {
                if viewModel.routeResponse != nil && viewModel.endLocation != nil {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.primaryMint)
                        .frame(width: 48, height: 48)
                        .background(Color.surfaceElevated.opacity(0.95))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.onSurfaceVariant.opacity(0.15), lineWidth: 1))
                } else {
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
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open route search")

            Spacer()
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
                    focusedField = nil
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

                    TextField("Start Location", text: $startLocationText, onCommit: {
                        if let coord = parseCoordinate(from: startLocationText) {
                            focusedField = nil
                            viewModel.setStartLocation(coord)
                        }
                    })
                    .focused($focusedField, equals: .start)
                    .onChange(of: startLocationText) { _, newValue in
                        if suppressNextStartAutocomplete {
                            suppressNextStartAutocomplete = false
                            startAutocompleteTask?.cancel()
                            Task { @MainActor in
                                viewModel.clearPlaceSuggestions(target: "start")
                            }
                            return
                        }
                        schedulePlaceAutocomplete(target: "start", query: newValue)
                    }
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 14))
                    .foregroundColor(.onSurface)

                    if !startLocationText.isEmpty {
                        Button(action: {
                            startLocationText = ""
                            viewModel.startLocation = nil
                            viewModel.selectedStartName = nil
                            startAutocompleteTask?.cancel()
                            Task { @MainActor in viewModel.clearPlaceSuggestions(target: "start") }
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.onSurfaceVariant)
                                .font(.system(size: 14))
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    Button(action: {
                        if let userLoc = locationManager.currentLocation {
                            focusedField = nil
                            viewModel.setStartLocation(userLoc.coordinate)
                        }
                    }) {
                        Image(systemName: "location.fill")
                            .foregroundColor(.primaryMint)
                    }

                    Button(action: {
                        if let home = viewModel.homeLocation {
                            focusedField = nil
                            viewModel.setStartLocation(home.coordinate, startName: "Home")
                        }
                    }) {
                        Image(systemName: "house.fill")
                            .foregroundColor(viewModel.homeLocation == nil ? .onSurfaceVariant : .primaryMint)
                    }
                    .disabled(viewModel.homeLocation == nil)

                    Button(action: {
                        focusedField = nil
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

                    TextField("Destination", text: $endLocationText, onCommit: {
                        if let coord = parseCoordinate(from: endLocationText) {
                            focusedField = nil
                            viewModel.setEndLocation(coord)
                        }
                    })
                    .focused($focusedField, equals: .destination)
                    .onChange(of: endLocationText) { _, newValue in
                        if suppressNextEndAutocomplete {
                            suppressNextEndAutocomplete = false
                            endAutocompleteTask?.cancel()
                            Task { @MainActor in
                                viewModel.clearPlaceSuggestions(target: "end")
                            }
                            return
                        }
                        if showPlaygroundList { showPlaygroundList = false }
                        schedulePlaceAutocomplete(target: "end", query: newValue)
                    }
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 14))
                    .foregroundColor(.onSurface)

                    if !endLocationText.isEmpty {
                        Button(action: {
                            endLocationText = ""
                            viewModel.endLocation = nil
                            viewModel.selectedDestinationName = nil
                            endAutocompleteTask?.cancel()
                            Task { @MainActor in viewModel.clearPlaceSuggestions(target: "end") }
                            showPlaygroundList = false
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.onSurfaceVariant)
                                .font(.system(size: 14))
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    Button(action: {
                        focusedField = nil
                        withAnimation {
                            showPlaygroundList.toggle()
                        }
                    }) {
                        Image(systemName: "figure.play")
                            .foregroundColor(showPlaygroundList ? .mintGlow : .primaryMint)
                    }

                    Button(action: {
                        focusedField = nil
                        viewModel.routeToHome(from: currentStartCoordinate())
                    }) {
                        Image(systemName: "house.fill")
                            .foregroundColor(viewModel.homeLocation == nil ? .onSurfaceVariant : .primaryMint)
                    }
                    .disabled(viewModel.homeLocation == nil)

                    Button(action: {
                        focusedField = nil
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
                .overlay(
                    GeometryReader { geo in
                        Color.clear.preference(key: EndRowBottomKey.self, value: geo.frame(in: .global).maxY)
                    }
                )

                if showPlaygroundList {
                    playgroundSelectionList
                } else {
                    placeSuggestionList(
                        viewModel.endPlaceSuggestions,
                        target: "end",
                        searchCompleted: viewModel.endPlaceSearchCompleted,
                        query: viewModel.endPlaceSearchQuery
                    )
                }
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
            ScrollView {
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
                                focusedField = nil
                                viewModel.selectPlaceSuggestion(suggestion, target: target)
                            }) {
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(suggestion.name)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(.onSurface)
                                            .lineLimit(1)

                                        Text(suggestion.type.replacingOccurrences(of: "_", with: " ").prefix(1).uppercased() + suggestion.type.replacingOccurrences(of: "_", with: " ").dropFirst())
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
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if suggestion.id != suggestions.last?.id {
                                Divider()
                                    .background(Color.onSurfaceVariant.opacity(0.15))
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: listMaxHeight)
            .background(Color.forestDeep.opacity(0.92))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primaryMint.opacity(0.16), lineWidth: 1))
        }
    }

    @ViewBuilder
    private var playgroundSelectionList: some View {
        ScrollView {
            VStack(spacing: 0) {
                if viewModel.playgroundsList.isEmpty {
                    Text("No playgrounds available")
                        .font(.system(size: 13))
                        .foregroundColor(.onSurfaceVariant)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                } else {
                    ForEach(viewModel.playgroundsList) { pg in
                        Button(action: {
                            viewModel.selectPlayground(pg)
                            viewModel.clearPlaceSuggestions(target: "end")
                            withAnimation(.spring()) {
                                showPlaygroundList = false
                                isSearchExpanded = false
                            }
                        }) {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(pg.name)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.onSurface)
                                        .lineLimit(1)

                                    Text("Playground")
                                        .font(.system(size: 11))
                                        .foregroundColor(.onSurfaceVariant)
                                        .lineLimit(1)
                                }

                                Spacer()

                                Image(systemName: "figure.play")
                                    .font(.system(size: 14))
                                    .foregroundColor(.primaryMint)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if pg.id != viewModel.playgroundsList.last?.id {
                            Divider()
                                .background(Color.onSurfaceVariant.opacity(0.15))
                        }
                    }
                }
            }
        }
        .frame(maxHeight: listMaxHeight)
        .background(Color.forestDeep.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primaryMint.opacity(0.16), lineWidth: 1))
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
        let detailDistanceMeters = viewModel.selectedHistoryRouteDetails?.id == route.id
            ? viewModel.selectedHistoryRouteDetails?.actualDistanceMeters
            : nil
        let detailDurationSeconds = viewModel.selectedHistoryRouteDetails?.id == route.id
            ? viewModel.selectedHistoryRouteDetails?.actualDurationSeconds
            : nil
        let distanceMiles = (detailDistanceMeters ?? route.displayedDistanceMeters) / 1609.34
        let durationMinutes = Int((detailDurationSeconds ?? route.displayedDurationSeconds) / 60)

        return HStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundColor(.mintGlow)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(route.name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.onSurface)
                Text(String(format: "Actual: %.2f mi (Time: %d min)", distanceMiles, durationMinutes))
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
        viewModel.selectedPresetName ?? viewModel.selectedDestinationName ?? viewModel.selectedPlayground?.name ?? "Custom Route"
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
    private func mapCanvas() -> some View {
        MapKitMapView(
            cameraPosition: $cameraPosition,
            startLocation: viewModel.startLocation,
            endLocation: viewModel.endLocation,
            selectedHistoryActualCoordinates: viewModel.selectedHistoryRouteDetails?.actualRouteCoordinatePath ?? [],
            pendingHomeCoordinate: viewModel.pendingHomeCoordinate,
            userCoordinate: locationManager.currentLocation?.coordinate,
            routeCoordinatePaths: viewModel.routeResponse?.routeCoordinatePaths ?? [],
            waypoints: viewModel.waypoints,
            officialRouteGroups: viewModel.bikeRouteOverlays,
            showOfficialRoutes: viewModel.showOfficialRoutesLayer,
            isSelectingHomeLocation: viewModel.isSelectingHomeLocation,
            mapSelectionMode: mapSelectionMode,
            onMapTap: { coordinate in
                if viewModel.isSelectingHomeLocation {
                    handleHomeMapTap(at: coordinate)
                } else if mapSelectionMode != nil {
                    handleMapTap(at: coordinate)
                }
            },
            onStartDragChanged: { coordinate in
                viewModel.dragStartLocation(to: coordinate)
            },
            onStartDragEnded: { coordinate in
                viewModel.setStartLocation(coordinate, startName: nil)
            },
            onEndDragChanged: { coordinate in
                viewModel.dragEndLocation(to: coordinate)
            },
            onEndDragEnded: { coordinate in
                viewModel.setEndLocation(coordinate, destinationName: nil)
            },
            onHomeDragChanged: { coordinate in
                viewModel.updatePendingHomeLocation(coordinate)
            }
        )
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

    private func coordinateDistance(_ a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }
}

// MARK: - Preference Keys

private struct EndRowBottomKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

// MARK: - Subviews: User Location Marker

struct UserLocationMarker: View {
    /// Holds a direct reference to the @Observable LocationManager so that SwiftUI sets up
    /// observation tracking here, inside the annotation's own hosted SwiftUI view.  This
    /// guarantees heading changes re-render the arrow even when MapKit reuses a cached
    /// MKAnnotationView and skips propagating parent-level content updates.
    var locationManager: LocationManager

    var body: some View {
        let heading = locationManager.currentHeading
        ZStack {
            Image(systemName: "triangle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 14, height: 14)
                .foregroundColor(.primaryMint)
                .opacity(0.7)
                .offset(y: -12)
                .rotationEffect(.degrees(heading))
                .animation(.easeInOut(duration: 0.2), value: heading)

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
