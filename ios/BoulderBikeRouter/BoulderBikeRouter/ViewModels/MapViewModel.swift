import Foundation
import CoreLocation
import SwiftUI

@Observable
class MapViewModel {
    // Dynamic configurations loaded from server
    var presets: [PresetConfig] = []
    var weightsMetadata: [WeightConfig] = []
    var weights: [String: Double] = [:]

    // Map markers and route state
    var startLocation: CLLocationCoordinate2D?
    var endLocation: CLLocationCoordinate2D?
    var waypoints: [CLLocationCoordinate2D] = []
    var routeResponse: RouteResponse?
    var isLoadingRoute: Bool = false
    var routingError: String?

    // Selection states
    var selectedPresetName: String?
    var selectedPlayground: Playground?
    var playgroundsList: [Playground] = []
    var showOfficialRoutesLayer: Bool = false

    // App state
    var isConfigLoaded: Bool = false
    var isWeightsLocked: Bool = false

    // Navigation preferences
    var avoidTolls: Bool = false
    var avoidHighways: Bool = false
    
    // History list
    var pastRoutes: [PastRoute] = []
    
    // Telemetry selection state
    var selectedHistoryRoute: PastRoute? = nil
    var selectedHistoryRouteTicks: [NavigationTick] = []
    var selectedHistoryRouteDetails: DetailedRouteResponse? = nil

    // Services
    private let apiService = APIService()

    init() {
        // Populate local fallback configurations so the app works offline
        loadLocalFallbacks()
        
        // Load telemetry history asynchronously
        Task {
            await loadHistory()
        }
        
        // Listen for updates when a route ends
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("TelemetryRouteEnded"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task {
                await self?.loadHistory()
            }
        }
    }

    /// Primary dynamic bootstrapper loaded on view appear
    func loadConfiguration() async {
        do {
            let config = try await apiService.fetchConfig()
            
            await MainActor.run {
                self.presets = config.presets
                self.weightsMetadata = config.weights
                
                // Populate dynamic weights dictionary
                var newWeights: [String: Double] = [:]
                for w in config.weights {
                    newWeights[w.key] = w.default
                }
                self.weights = newWeights
                self.isConfigLoaded = true
                print("Successfully loaded \(self.presets.count) presets and \(self.weightsMetadata.count) sliders from backend.")
            }
            
            // Also load playgrounds
            let playgrounds = try await apiService.fetchPlaygrounds()
            await MainActor.run {
                self.playgroundsList = playgrounds
            }
        } catch {
            print("Failed to load configurations from API backend. Using local fallbacks. Error: \(error.localizedDescription)")
            await MainActor.run {
                self.isConfigLoaded = true // proceed with fallbacks
            }
        }
    }

    func selectPreset(_ preset: PresetConfig) {
        selectedPresetName = preset.name
        startLocation = preset.startCoordinate
        endLocation = preset.endCoordinate
        waypoints = preset.waypointCoordinates
        
        // Lock/unlock sliders based on preset type (like official routes B180/B360)
        if preset.routeType != nil {
            isWeightsLocked = true
        } else {
            isWeightsLocked = false
        }
        
        // Trigger routing
        Task {
            await fetchRoute()
        }
    }

    func selectPlayground(_ playground: Playground) {
        selectedPlayground = playground
        endLocation = playground.coordinate
        selectedPresetName = nil // clear preset selection
        
        // Trigger routing
        Task {
            await fetchRoute()
        }
    }

    func setStartLocation(_ coordinate: CLLocationCoordinate2D) {
        startLocation = coordinate
        selectedPresetName = nil
        Task {
            await fetchRoute()
        }
    }

    func setEndLocation(_ coordinate: CLLocationCoordinate2D) {
        endLocation = coordinate
        selectedPresetName = nil
        selectedPlayground = nil
        Task {
            await fetchRoute()
        }
    }

    func resetWeights() {
        var newWeights: [String: Double] = [:]
        for w in weightsMetadata {
            newWeights[w.key] = w.default
        }
        self.weights = newWeights
        
        Task {
            await fetchRoute()
        }
    }

    func fetchRoute() async {
        guard let start = startLocation, let end = endLocation else { return }
        
        await MainActor.run {
            self.isLoadingRoute = true
            self.routingError = nil
        }
        
        // Build waypoints coordinate array
        let wpsArray = waypoints.map { [$0.latitude, $0.longitude] }
        
        let request = RouteRequest(
            startLat: start.latitude,
            startLon: start.longitude,
            endLat: end.latitude,
            endLon: end.longitude,
            waypoints: wpsArray,
            weights: weights
        )
        
        do {
            let response = try await apiService.fetchRoute(request: request)
            await MainActor.run {
                self.routeResponse = response
                self.isLoadingRoute = false
            }
        } catch {
            await MainActor.run {
                self.routingError = error.localizedDescription
                self.isLoadingRoute = false
            }
        }
    }

    private func loadLocalFallbacks() {
        // Fallbacks matching the initial preset items if backend is unreachable on first run
        self.presets = [
            PresetConfig(name: "North Boulder ➔ Iris Ave", desc: "Cedar Ave to 28th St & Iris", start: [40.028446, -105.281088], end: [40.038662, -105.263851], waypoints: [], routeType: nil),
            PresetConfig(name: "CU Campus ➔ North Park", desc: "Broadway Path & residential streets", start: [40.007, -105.263], end: [40.028, -105.283], waypoints: [], routeType: nil),
            PresetConfig(name: "Valmont Park ➔ Pearl Street Mall", desc: "Using off-street multi-use paths", start: [40.030, -105.234], end: [40.018, -105.279], waypoints: [], routeType: nil)
        ]
        
        self.weightsMetadata = [
            WeightConfig(key: "separated_path", name: "Separated Paths", description: "Multi-use paths, greenways", webIcon: "fa-leaf", iosIcon: "leaf.fill", min: 0.1, max: 2.0, step: 0.1, default: 0.2),
            WeightConfig(key: "sharrow_minor", name: "Quiet Streets (Sharrows)", description: "Quiet streets with sharrows", webIcon: "fa-shield-halved", iosIcon: "shield.fill", min: 0.5, max: 5.0, step: 0.1, default: 1.0),
            WeightConfig(key: "residential", name: "Residential Streets", description: "Quiet side streets", webIcon: "fa-house", iosIcon: "house.fill", min: 0.5, max: 5.0, step: 0.1, default: 1.5),
            WeightConfig(key: "sidewalk", name: "Sidewalk Routing", description: "Pedestrian ways, slow speed", webIcon: "fa-person-walking", iosIcon: "figure.walk", min: 1.0, max: 10.0, step: 0.5, default: 3.0),
            WeightConfig(key: "busy_with_lane", name: "Busy Roads w/ Bike Lane", description: "Secondary roads with lanes", webIcon: "fa-road", iosIcon: "road.lanes", min: 2.0, max: 15.0, step: 0.5, default: 4.0),
            WeightConfig(key: "busy_with_sharrow", name: "Busy Roads w/ Sharrows", description: "Arterials with sharrows", webIcon: "fa-triangle-exclamation", iosIcon: "exclamationmark.triangle.fill", min: 3.0, max: 25.0, step: 1.0, default: 8.0),
            WeightConfig(key: "busy_undesignated", name: "Busy Roads (Undesignated)", description: "Arterials without bike infrastructure", webIcon: "fa-skull", iosIcon: "skull", min: 5.0, max: 50.0, step: 1.0, default: 15.0)
        ]
        
        var newWeights: [String: Double] = [:]
        for w in weightsMetadata {
            newWeights[w.key] = w.default
        }
        self.weights = newWeights
    }

    /// Load telemetry route history from the backend.
    func loadHistory() async {
        do {
            let guestHistory = UserDefaults.standard.stringArray(forKey: "guest_routes_history")
            let routes = try await apiService.fetchHistory(routeIds: guestHistory)
            await MainActor.run {
                self.pastRoutes = routes
                print("Loaded \(routes.count) past routes from telemetry history.")
            }
        } catch {
            print("Failed to load telemetry history: \(error.localizedDescription)")
        }
    }
    
    func selectHistoryRoute(_ route: PastRoute) async {
        do {
            let details = try await apiService.fetchRouteDetails(routeId: route.id)
            await MainActor.run {
                self.selectedHistoryRoute = route
                self.selectedHistoryRouteTicks = details.ticks
                self.selectedHistoryRouteDetails = details
                
                // Clear active planner route when viewing history detail
                self.startLocation = nil
                self.endLocation = nil
                self.routeResponse = nil
            }
        } catch {
            print("Failed to load history route details: \(error.localizedDescription)")
        }
    }
    
    func clearHistorySelection() {
        self.selectedHistoryRoute = nil
        self.selectedHistoryRouteTicks = []
        self.selectedHistoryRouteDetails = nil
    }

    func recordCompletedRoute() {
        guard let route = routeResponse else { return }
        let startName = selectedPresetName != nil ? "Start Point" : "Dropped Pin"
        let endName = selectedPlayground?.name ?? "Destination"
        let durationSeconds = Int(route.totalLengthMeters / 5.3)
        
        let startLat = startLocation?.latitude ?? 0.0
        let startLon = startLocation?.longitude ?? 0.0
        let endLat = endLocation?.latitude ?? 0.0
        let endLon = endLocation?.longitude ?? 0.0
        
        let newRoute = PastRoute(
            id: UUID().uuidString,
            startPointName: startName,
            endPointName: endName,
            startLat: startLat,
            startLon: startLon,
            endLat: endLat,
            endLon: endLon,
            totalLengthMeters: route.totalLengthMeters,
            totalEstimatedTimeSeconds: Double(durationSeconds),
            status: "completed",
            startedAt: ISO8601DateFormatter().string(from: Date()),
            endedAt: ISO8601DateFormatter().string(from: Date()),
            endedLat: endLat,
            endedLon: endLon,
            actualDistanceMeters: route.totalLengthMeters,
            actualDurationSeconds: Double(durationSeconds),
            averageSpeed: 5.3,
            deviceType: "ios",
            weights: weights
        )
        
        pastRoutes.insert(newRoute, at: 0)
    }
}
