import Foundation
import CoreLocation
import SwiftUI
import SwiftData

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

    // User session properties
    var currentUserEmail: String? = UserDefaults.standard.string(forKey: "logged_in_user_email")
    var currentUserId: String? = UserDefaults.standard.string(forKey: "logged_in_user_id")
    var pocketbaseToken: String? = UserDefaults.standard.string(forKey: "pocketbase_token")
    
    var isUserLoggedIn: Bool {
        pocketbaseToken != nil
    }
    
    // SwiftData Context & Services
    var modelContext: ModelContext? = nil {
        didSet {
            if modelContext != nil {
                Task {
                    await syncService?.syncPendingRoutes()
                    await loadHistory()
                }
            }
        }
    }
    
    var syncService: SyncService? {
        guard let context = modelContext else { return nil }
        return SyncService(modelContext: context)
    }
    
    var isCloudSyncEnabled: Bool {
        get {
            UserDefaults.standard.object(forKey: "cloud_sync_enabled") as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "cloud_sync_enabled")
            if newValue {
                Task {
                    await syncService?.syncPendingRoutes()
                    await loadHistory()
                }
            }
        }
    }
    
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
        
        // Listen for app foregrounding to trigger auto-sync
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task {
                await self?.syncService?.syncPendingRoutes()
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

    /// Load telemetry route history from both remote server (if sync is enabled) and SwiftData.
    func loadHistory() async {
        let currentUserId = UserDefaults.standard.string(forKey: "logged_in_user_id")
        let isSyncActive = isUserLoggedIn && isCloudSyncEnabled
        
        var serverRoutes: [PastRoute] = []
        
        // 1. Fetch remote routes if cloud sync is active
        if isSyncActive {
            do {
                serverRoutes = try await apiService.fetchHistory(routeIds: nil)
            } catch {
                print("Failed to load telemetry history from server: \(error.localizedDescription)")
            }
        }
        
        // 2. Fetch local routes from SwiftData
        var localRoutes: [PastRoute] = []
        if let context = modelContext {
            do {
                let descriptor = FetchDescriptor<LocalRoute>(
                    sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
                )
                let allLocalRoutes = try context.fetch(descriptor)
                
                // Filter routes depending on auth context
                let filteredLocalRoutes = allLocalRoutes.filter { r in
                    if let userId = currentUserId {
                        // Signed-in: Show user's routes and unsynced guest routes
                        return r.userId == userId || r.userId == nil
                    } else {
                        // Guest: Show only guest routes
                        return r.userId == nil
                    }
                }
                
                localRoutes = filteredLocalRoutes.map { $0.toPastRoute }
            } catch {
                print("Failed to load local routes from SwiftData: \(error.localizedDescription)")
            }
        }
        
        // 3. Combine and sort
        await MainActor.run {
            var combinedMap: [String: PastRoute] = [:]
            for r in localRoutes {
                combinedMap[r.id] = r
            }
            for r in serverRoutes {
                combinedMap[r.id] = r
            }
            
            self.pastRoutes = combinedMap.values.sorted(by: { $0.startedAt > $1.startedAt })
            print("Loaded \(self.pastRoutes.count) past routes (Local: \(localRoutes.count), Server: \(serverRoutes.count)).")
        }
    }
    
    func selectHistoryRoute(_ route: PastRoute) async {
        // First, check if we have the route with detailed ticks locally in SwiftData
        if let context = modelContext {
            let localId = route.id
            let descriptor = FetchDescriptor<LocalRoute>(
                predicate: #Predicate<LocalRoute> { $0.id == localId }
            )
            if let localRoute = try? context.fetch(descriptor).first {
                await MainActor.run {
                    self.selectedHistoryRoute = route
                    self.selectedHistoryRouteTicks = localRoute.ticks.map { $0.toNavigationTick }
                    
                    var routeGeojsonObj: GeoJSONFeatureCollection? = nil
                    if let geojsonStr = localRoute.routeGeojson,
                       let geojsonData = geojsonStr.data(using: .utf8) {
                        routeGeojsonObj = try? JSONDecoder().decode(GeoJSONFeatureCollection.self, from: geojsonData)
                    }
                    
                    self.selectedHistoryRouteDetails = DetailedRouteResponse(
                        id: localRoute.id,
                        startPointName: localRoute.startPointName,
                        endPointName: localRoute.endPointName,
                        startLat: localRoute.startLat,
                        startLon: localRoute.startLon,
                        endLat: localRoute.endLat,
                        endLon: localRoute.endLon,
                        totalLengthMeters: localRoute.totalLengthMeters,
                        totalEstimatedTimeSeconds: localRoute.totalEstimatedTimeSeconds,
                        status: localRoute.status,
                        startedAt: localRoute.startedAt,
                        endedAt: localRoute.endedAt,
                        endedLat: localRoute.endedLat,
                        endedLon: localRoute.endedLon,
                        actualDistanceMeters: localRoute.actualDistanceMeters,
                        actualDurationSeconds: localRoute.actualDurationSeconds,
                        averageSpeed: localRoute.averageSpeed,
                        deviceType: localRoute.deviceType,
                        weights: localRoute.weights,
                        routeGeojson: routeGeojsonObj,
                        ticks: localRoute.ticks.map { $0.toNavigationTick }
                    )
                    
                    self.startLocation = nil
                    self.endLocation = nil
                    self.routeResponse = nil
                }
                return
            }
        }
        
        // Fallback: load details from backend server
        do {
            let details = try await apiService.fetchRouteDetails(routeId: route.id)
            await MainActor.run {
                self.selectedHistoryRoute = route
                self.selectedHistoryRouteTicks = details.ticks
                self.selectedHistoryRouteDetails = details
                
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
        // Logic handled by NavigationManager & SwiftData; kept for backward compatibility
    }

    // MARK: - User Authentication Actions
    
    @MainActor
    func signIn(email: String, password: String) async throws {
        let auth = try await apiService.signIn(email: email, password: password)
        
        UserDefaults.standard.set(auth.token, forKey: "pocketbase_token")
        UserDefaults.standard.set(auth.record.email, forKey: "logged_in_user_email")
        UserDefaults.standard.set(auth.record.id, forKey: "logged_in_user_id")
        
        // Enable Cloud Sync by default on sign-in
        UserDefaults.standard.set(true, forKey: "cloud_sync_enabled")
        
        self.pocketbaseToken = auth.token
        self.currentUserEmail = auth.record.email
        self.currentUserId = auth.record.id
        
        // Trigger batch upload of any pending offline guest routes
        if let sync = syncService {
            await sync.syncPendingRoutes()
        }
        
        // Reload telemetry history for the logged-in user
        await loadHistory()
    }
    
    @MainActor
    func signUp(email: String, password: String) async throws {
        // 1. Create the account
        try await apiService.signUp(email: email, password: password)
        
        // 2. Automatically log in after successful registration
        try await signIn(email: email, password: password)
    }
    
    @MainActor
    func signOut() {
        // Clear synced authenticated user routes from local DB on sign-out
        if let sync = syncService {
            sync.clearUserSyncedData()
        }
        
        UserDefaults.standard.removeObject(forKey: "pocketbase_token")
        UserDefaults.standard.removeObject(forKey: "logged_in_user_email")
        UserDefaults.standard.removeObject(forKey: "logged_in_user_id")
        UserDefaults.standard.removeObject(forKey: "cloud_sync_enabled") // Reset toggle
        
        self.pocketbaseToken = nil
        self.currentUserEmail = nil
        self.currentUserId = nil
        
        // Reload telemetry history for the guest
        Task {
            await loadHistory()
        }
    }
}
