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
    var routeOffsets: [String: Double] = [:]
    var routeTuningProfiles: [RouteTuningProfile] = []
    var activeRouteTuningProfileId: String? = UserDefaults.standard.string(forKey: "active_route_tuning_profile_id")
    var homeLocation: HomeLocation?
    var homeLocationError: String?
    var isSavingHomeLocation: Bool = false
    var isSelectingHomeLocation: Bool = false
    var pendingHomeCoordinate: CLLocationCoordinate2D?
    var startPlaceSuggestions: [PlaceSuggestion] = []
    var endPlaceSuggestions: [PlaceSuggestion] = []
    var startPlaceSearchCompleted: Bool = false
    var endPlaceSearchCompleted: Bool = false
    var startPlaceSearchQuery: String = ""
    var endPlaceSearchQuery: String = ""
    var placeAutocompleteError: String?

    // Map markers and route state
    var startLocation: CLLocationCoordinate2D?
    var endLocation: CLLocationCoordinate2D?
    var currentLocation: CLLocationCoordinate2D?
    var waypoints: [CLLocationCoordinate2D] = []
    var routeResponse: RouteResponse?
    var isLoadingRoute: Bool = false
    var routingError: String?

    // Selection states
    var selectedPresetName: String?
    var selectedPlayground: Playground?
    var selectedDestinationName: String?
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
            syncService = modelContext.map { SyncService(modelContext: $0) }
            if modelContext != nil {
                Task(priority: .background) {
                    await syncService?.syncPendingRoutes()
                    await syncService?.syncPendingRouteTuningProfiles()
                }
                Task {
                    await loadRouteTuningProfiles()
                    await loadHomeLocation()
                    await loadHistory()
                }
            }
        }
    }

    private(set) var syncService: SyncService? = nil
    
    var isCloudSyncEnabled: Bool {
        get {
            UserDefaults.standard.object(forKey: "cloud_sync_enabled") as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "cloud_sync_enabled")
            if newValue {
                Task {
                    await syncService?.syncPendingRoutes()
                    await syncService?.syncPendingRouteTuningProfiles()
                    await loadRouteTuningProfiles()
                    await loadHomeLocation()
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

    private func parseCoordinateText(_ text: String) -> CLLocationCoordinate2D? {
        let parts = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if parts.count == 2,
           let lat = Double(parts[0]),
           let lon = Double(parts[1]) {
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        return nil
    }

    init() {
        // Populate local fallback configurations so the app works offline
        loadLocalFallbacks()

        // Apply cached config from last successful fetch so real presets appear before the network call completes
        if let data = UserDefaults.standard.data(forKey: "cached_config_v1"),
           let cached = try? JSONDecoder().decode(CachedConfig.self, from: data) {
            presets = cached.presets
            weightsMetadata = cached.weightsMetadata
            playgroundsList = cached.playgrounds
            var w: [String: Double] = [:]
            for wm in cached.weightsMetadata { w[wm.key] = wm.default }
            weights = w
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
                await self?.syncService?.syncPendingRouteTuningProfiles()
                await self?.loadRouteTuningProfiles()
                await self?.loadHomeLocation()
                await self?.loadHistory()
            }
        }
    }

    /// Primary dynamic bootstrapper loaded on view appear
    func loadConfiguration() async {
        do {
            let config = try await apiService.fetchConfig()
            
            await MainActor.run {
                self.presets = config.presets.filter { $0.routeType == "b180" || $0.routeType == "b360" }
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
                // Cache for instant preset display on next launch
                if let data = try? JSONEncoder().encode(CachedConfig(
                    presets: self.presets,
                    weightsMetadata: self.weightsMetadata,
                    playgrounds: playgrounds
                )) {
                    UserDefaults.standard.set(data, forKey: "cached_config_v1")
                }
            }
        } catch {
            print("Failed to load configurations from API backend. Using local fallbacks. Error: \(error.localizedDescription)")
            await MainActor.run {
                self.loadLocalFallbacks()
                self.isConfigLoaded = true // proceed with fallbacks
            }
        }
    }

    func selectPreset(_ preset: PresetConfig) {
        selectedPresetName = preset.name
        selectedDestinationName = nil

        if preset.routeType == "playgrounds" {
            selectedPlayground = nil
            routeResponse = nil
            routingError = nil
            isWeightsLocked = false
            return
        }

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
        guard startLocation != nil else {
            routingError = "Set a start location before routing to a playground."
            return
        }
        selectedPlayground = playground
        selectedDestinationName = playground.name
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

    func setEndLocation(_ coordinate: CLLocationCoordinate2D, destinationName: String? = nil) {
        endLocation = coordinate
        selectedPresetName = nil
        selectedPlayground = nil
        let trimmedName = destinationName?.trimmingCharacters(in: .whitespacesAndNewlines)
        selectedDestinationName = (trimmedName?.isEmpty == false) ? trimmedName : nil
        Task {
            await fetchRoute()
        }
    }

    func searchPlaces(query: String, target: String) async {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count >= 2, parseCoordinateText(normalized) == nil else {
            await MainActor.run {
                self.clearPlaceSuggestions(target: target)
            }
            return
        }

        do {
            let suggestions = try await apiService.fetchPlaceSuggestions(query: normalized)
            await MainActor.run {
                if target == "start" {
                    self.startPlaceSuggestions = suggestions
                    self.startPlaceSearchCompleted = true
                    self.startPlaceSearchQuery = normalized
                } else {
                    self.endPlaceSuggestions = suggestions
                    self.endPlaceSearchCompleted = true
                    self.endPlaceSearchQuery = normalized
                }
                self.placeAutocompleteError = nil
            }
        } catch {
            await MainActor.run {
                self.clearPlaceSuggestions(target: target)
                self.placeAutocompleteError = error.localizedDescription
            }
        }
    }

    @MainActor
    func clearPlaceSuggestions(target: String) {
        if target == "start" {
            startPlaceSuggestions = []
            startPlaceSearchCompleted = false
            startPlaceSearchQuery = ""
        } else {
            endPlaceSuggestions = []
            endPlaceSearchCompleted = false
            endPlaceSearchQuery = ""
        }
    }

    @MainActor
    func selectPlaceSuggestion(_ suggestion: PlaceSuggestion, target: String) {
        if target == "start" {
            setStartLocation(suggestion.coordinate)
        } else {
            setEndLocation(suggestion.coordinate, destinationName: suggestion.name)
        }
        clearPlaceSuggestions(target: target)
    }

    func routeToHome(from currentCoordinate: CLLocationCoordinate2D?) {
        guard let homeLocation else {
            homeLocationError = isUserLoggedIn ? "Set your home location first." : "Sign in to use home routing."
            return
        }
        guard let routeStart = currentCoordinate ?? currentLocation else {
            homeLocationError = "Current location is unavailable. Allow location access to route home."
            return
        }
        startLocation = routeStart
        setEndLocation(homeLocation.coordinate, destinationName: "Home")
    }

    @MainActor
    func beginHomeLocationSelection(currentCoordinate: CLLocationCoordinate2D? = nil) {
        guard isUserLoggedIn else {
            homeLocationError = "Sign in to set a home location."
            return
        }
        pendingHomeCoordinate = currentCoordinate ?? currentLocation
        isSelectingHomeLocation = true
        homeLocationError = nil
    }

    @MainActor
    func updatePendingHomeLocation(_ coordinate: CLLocationCoordinate2D) {
        pendingHomeCoordinate = coordinate
    }

    @MainActor
    func cancelHomeLocationSelection() {
        isSelectingHomeLocation = false
        pendingHomeCoordinate = nil
    }

    func loadHomeLocation() async {
        guard isUserLoggedIn else {
            await MainActor.run {
                self.homeLocation = nil
                self.homeLocationError = nil
            }
            return
        }

        do {
            let home = try await apiService.fetchHomeLocation()
            await MainActor.run {
                self.homeLocation = home
                self.homeLocationError = nil
            }
        } catch {
            await MainActor.run {
                self.homeLocationError = error.localizedDescription
            }
        }
    }

    @MainActor
    func saveHomeLocation(_ coordinate: CLLocationCoordinate2D) async {
        guard isUserLoggedIn else {
            homeLocationError = "Sign in to save a home location."
            return
        }

        isSavingHomeLocation = true
        homeLocationError = nil
        do {
            let saved = try await apiService.saveHomeLocation(coordinate)
            homeLocation = saved
            pendingHomeCoordinate = nil
            isSelectingHomeLocation = false
        } catch {
            homeLocationError = error.localizedDescription
        }
        isSavingHomeLocation = false
    }

    @MainActor
    func deleteHomeLocation() async {
        guard isUserLoggedIn else {
            homeLocationError = "Sign in to clear a home location."
            return
        }

        isSavingHomeLocation = true
        homeLocationError = nil
        do {
            try await apiService.deleteHomeLocation()
            homeLocation = nil
        } catch {
            homeLocationError = error.localizedDescription
        }
        isSavingHomeLocation = false
    }

    func resetWeights() {
        self.weights = defaultRouteWeights()
        self.routeOffsets = [:]
        
        Task {
            await fetchRoute()
        }
    }

    func defaultRouteWeights() -> [String: Double] {
        var newWeights: [String: Double] = [:]
        for w in weightsMetadata {
            newWeights[w.key] = w.default
        }
        return newWeights
    }

    func loadRouteTuningProfiles() async {
        let currentUserId = UserDefaults.standard.string(forKey: "logged_in_user_id")
        let isSyncActive = isUserLoggedIn && isCloudSyncEnabled

        if isSyncActive {
            await syncService?.syncPendingRouteTuningProfiles()
        }

        if isSyncActive, let context = modelContext {
            do {
                let serverProfiles = try await apiService.fetchRouteTuningProfiles()
                let descriptor = FetchDescriptor<LocalRouteTuningProfile>()
                let existingProfiles = try context.fetch(descriptor)

                for serverProfile in serverProfiles {
                    if let existing = existingProfiles.first(where: { $0.serverId == serverProfile.id || $0.id == serverProfile.id }) {
                        existing.serverId = serverProfile.id
                        existing.name = serverProfile.name
                        existing.weights = serverProfile.weights
                        existing.offsets = serverProfile.offsets
                        existing.isDefault = serverProfile.isDefault
                        existing.userId = currentUserId
                        existing.synced = true
                        existing.deleted = false
                        existing.updatedAt = Date()
                    } else {
                        context.insert(LocalRouteTuningProfile(
                            id: serverProfile.id,
                            serverId: serverProfile.id,
                            name: serverProfile.name,
                            weights: serverProfile.weights,
                            offsets: serverProfile.offsets,
                            isDefault: serverProfile.isDefault,
                            userId: currentUserId,
                            synced: true
                        ))
                    }
                }
                try context.save()
            } catch {
                print("Failed to load route tuning profiles from server: \(error.localizedDescription)")
            }
        }

        guard let context = modelContext else { return }
        do {
            let descriptor = FetchDescriptor<LocalRouteTuningProfile>(
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
            let profiles = try context.fetch(descriptor)
                .filter { profile in
                    if profile.deleted { return false }
                    if let userId = currentUserId {
                        return profile.userId == userId || profile.userId == nil
                    }
                    return profile.userId == nil
                }
                .map(\.toRouteTuningProfile)

            await MainActor.run {
                self.routeTuningProfiles = profiles
                if let activeId = self.activeRouteTuningProfileId,
                   let active = profiles.first(where: { $0.localId == activeId || $0.id == activeId }) {
                    self.applyRouteTuningProfile(active)
                } else if let defaultProfile = profiles.first(where: { $0.isDefault }) {
                    self.applyRouteTuningProfile(defaultProfile)
                }
            }
        } catch {
            print("Failed to load local route tuning profiles: \(error.localizedDescription)")
        }
    }

    @MainActor
    func applyRouteTuningProfile(_ profile: RouteTuningProfile?) {
        guard let profile else {
            activeRouteTuningProfileId = nil
            UserDefaults.standard.removeObject(forKey: "active_route_tuning_profile_id")
            resetWeights()
            return
        }
        weights = profile.weights
        routeOffsets = profile.offsets
        activeRouteTuningProfileId = profile.localId ?? profile.id
        UserDefaults.standard.set(activeRouteTuningProfileId, forKey: "active_route_tuning_profile_id")
        Task {
            await fetchRoute()
        }
    }

    @MainActor
    func createRouteTuningProfile(name: String) async {
        await createRouteTuningProfile(name: name, weights: weights, offsets: routeOffsets)
    }

    @MainActor
    func createRouteTuningProfile(name: String, weights: [String: Double], offsets: [String: Double] = [:]) async {
        guard let context = modelContext else { return }
        let profile = LocalRouteTuningProfile(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Routing Profile" : name,
            weights: weights,
            offsets: offsets,
            isDefault: routeTuningProfiles.isEmpty,
            userId: currentUserId,
            synced: false
        )
        context.insert(profile)
        try? context.save()
        activeRouteTuningProfileId = profile.id
        UserDefaults.standard.set(profile.id, forKey: "active_route_tuning_profile_id")
        if isUserLoggedIn && isCloudSyncEnabled {
            await syncService?.syncPendingRouteTuningProfiles()
        }
        await loadRouteTuningProfiles()
    }

    @MainActor
    func saveActiveRouteTuningProfile() async {
        guard let activeId = activeRouteTuningProfileId else {
            await createRouteTuningProfile(name: "Custom Routing Profile")
            return
        }
        await saveRouteTuningProfile(id: activeId, name: nil, weights: weights, offsets: routeOffsets)
    }

    @MainActor
    func saveRouteTuningProfile(id: String, name: String?, weights: [String: Double], offsets: [String: Double] = [:]) async {
        guard let context = modelContext else { return }
        do {
            let descriptor = FetchDescriptor<LocalRouteTuningProfile>()
            if let profile = try context.fetch(descriptor).first(where: { $0.id == id || $0.serverId == id }) {
                if let name {
                    profile.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Routing Profile" : name
                }
                profile.weights = weights
                profile.offsets = offsets
                profile.synced = false
                profile.updatedAt = Date()
                try context.save()
                self.weights = weights
                self.routeOffsets = offsets
                activeRouteTuningProfileId = profile.id
                UserDefaults.standard.set(profile.id, forKey: "active_route_tuning_profile_id")
                if isUserLoggedIn && isCloudSyncEnabled {
                    await syncService?.syncPendingRouteTuningProfiles()
                }
                await loadRouteTuningProfiles()
                await fetchRoute()
            }
        } catch {
            print("Failed to save route tuning profile: \(error.localizedDescription)")
        }
    }

    @MainActor
    func deleteActiveRouteTuningProfile() async {
        guard let context = modelContext, let activeId = activeRouteTuningProfileId else { return }
        await deleteRouteTuningProfile(id: activeId)
    }

    @MainActor
    func deleteRouteTuningProfile(id: String) async {
        guard let context = modelContext else { return }
        do {
            let descriptor = FetchDescriptor<LocalRouteTuningProfile>()
            if let profile = try context.fetch(descriptor).first(where: { $0.id == id || $0.serverId == id }) {
                if let serverId = profile.serverId, isUserLoggedIn && isCloudSyncEnabled {
                    try? await apiService.deleteRouteTuningProfile(serverId: serverId)
                    context.delete(profile)
                } else if profile.serverId != nil {
                    profile.deleted = true
                    profile.synced = false
                } else {
                    context.delete(profile)
                }
                try context.save()
            }
            if activeRouteTuningProfileId == id {
                activeRouteTuningProfileId = nil
                UserDefaults.standard.removeObject(forKey: "active_route_tuning_profile_id")
                resetWeights()
            }
            await loadRouteTuningProfiles()
        } catch {
            print("Failed to delete route tuning profile: \(error.localizedDescription)")
        }
    }

    @MainActor
    func setActiveRouteTuningProfileDefault() async {
        guard let context = modelContext, let activeId = activeRouteTuningProfileId else { return }
        do {
            let descriptor = FetchDescriptor<LocalRouteTuningProfile>()
            let profiles = try context.fetch(descriptor)
            for profile in profiles {
                let shouldBeDefault = profile.id == activeId || profile.serverId == activeId
                if profile.isDefault != shouldBeDefault {
                    profile.isDefault = shouldBeDefault
                    profile.synced = false
                    profile.updatedAt = Date()
                }
            }
            try context.save()
            if isUserLoggedIn && isCloudSyncEnabled {
                await syncService?.syncPendingRouteTuningProfiles()
            }
            await loadRouteTuningProfiles()
        } catch {
            print("Failed to update default route tuning profile: \(error.localizedDescription)")
        }
    }

    func fetchRoute() async {
        guard let start = startLocation, let end = endLocation else { return }
        
        await MainActor.run {
            self.isLoadingRoute = true
            self.routingError = nil
        }

        if let routeType = presets.first(where: { $0.name == selectedPresetName })?.routeType,
           routeType == "b180" || routeType == "b360" {
            do {
                let response = try await apiService.fetchOfficialLoopRoute(routeType: routeType)
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
            return
        }
        
        // Build waypoints coordinate array
        let wpsArray = waypoints.map { [$0.latitude, $0.longitude] }
        
        let request = RouteRequest(
            startLat: start.latitude,
            startLon: start.longitude,
            endLat: end.latitude,
            endLon: end.longitude,
            waypoints: wpsArray,
            weights: weights,
            offsets: routeOffsets
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
            PresetConfig(name: "Boulder Loops B-180", desc: "12 mi scenic loop (Valmont Park)", start: [40.030, -105.234], end: [40.030, -105.234], waypoints: [[40.033,-105.253],[40.038,-105.263],[40.028,-105.281],[40.028,-105.283],[40.021,-105.291],[40.015,-105.292],[40.014,-105.275],[40.015,-105.253]], routeType: "b180"),
            PresetConfig(name: "Boulder Loops B-360", desc: "24 mi grand loop (Valmont Park)", start: [40.030, -105.234], end: [40.030, -105.234], waypoints: [[40.034,-105.225],[40.052,-105.207],[40.054,-105.228],[40.040,-105.249],[40.046,-105.265],[40.060,-105.275],[40.039,-105.289],[40.028,-105.289],[40.015,-105.292],[39.998,-105.283],[39.991,-105.263],[39.986,-105.238],[39.981,-105.233],[39.998,-105.228],[40.030,-105.210]], routeType: "b360")
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
                    if r.deleted { return false }
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
            for r in serverRoutes {
                combinedMap[r.id] = r
            }
            for r in localRoutes {
                combinedMap[r.id] = r
            }
            
            self.pastRoutes = combinedMap.values.sorted(by: { $0.date > $1.date })
            print("Loaded \(self.pastRoutes.count) past routes (Local: \(localRoutes.count), Server: \(serverRoutes.count)).")
        }
    }
    
    func selectHistoryRoute(_ route: PastRoute) async {
        await loadHistoryRouteDetails(route, activateSelection: true)
    }

    func preloadHistoryRouteDetails(_ route: PastRoute) async {
        await loadHistoryRouteDetails(route, activateSelection: false)
    }

    private func loadHistoryRouteDetails(_ route: PastRoute, activateSelection: Bool) async {
        // First, check if we have the route with detailed ticks locally in SwiftData
        if let context = modelContext {
            let routeId = route.id
            let descriptor = FetchDescriptor<LocalRoute>()
            if let localRoute = try? context.fetch(descriptor).first(where: { $0.id == routeId || $0.serverId == routeId }) {
                await MainActor.run {
                    if activateSelection {
                        self.selectedHistoryRoute = route
                    }
                    let sortedTicks = localRoute.ticks.sorted { $0.timestamp < $1.timestamp }.map { $0.toNavigationTick }
                    self.selectedHistoryRouteTicks = sortedTicks
                    
                    var routeGeojsonObj: GeoJSONFeatureCollection? = nil
                    if let geojsonStr = localRoute.routeGeojson,
                       let geojsonData = geojsonStr.data(using: .utf8) {
                        routeGeojsonObj = try? JSONDecoder().decode(GeoJSONFeatureCollection.self, from: geojsonData)
                    }
                    
                    self.selectedHistoryRouteDetails = DetailedRouteResponse(
                        id: localRoute.id,
                        displayName: localRoute.displayName,
                        notes: localRoute.notes,
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
                        ticks: sortedTicks
                    )
                    
                    if activateSelection {
                        self.startLocation = nil
                        self.endLocation = nil
                        self.routeResponse = nil
                    }
                }
                return
            }
        }
        
        // Fallback: load details from backend server
        do {
            let details = try await apiService.fetchRouteDetails(routeId: route.id)
            await MainActor.run {
                if activateSelection {
                    self.selectedHistoryRoute = route
                }
                self.selectedHistoryRouteTicks = details.ticks.sorted { $0.timestamp < $1.timestamp }
                self.selectedHistoryRouteDetails = details
                
                if activateSelection {
                    self.startLocation = nil
                    self.endLocation = nil
                    self.routeResponse = nil
                }
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

    @MainActor
    @discardableResult
    func updateHistoryRoute(_ route: PastRoute, displayName: String, notes: String) async -> PastRoute? {
        let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        var updatedRoute: PastRoute?

        if let context = modelContext {
            do {
                let routeId = route.id
                let descriptor = FetchDescriptor<LocalRoute>()
                if let localRoute = try context.fetch(descriptor).first(where: { $0.id == routeId || $0.serverId == routeId }) {
                    localRoute.displayName = trimmedDisplayName
                    localRoute.notes = trimmedNotes
                    localRoute.synced = false
                    try context.save()
                    updatedRoute = localRoute.toPastRoute
                }
            } catch {
                print("Failed to update local history route: \(error.localizedDescription)")
            }
        }

        if isUserLoggedIn && isCloudSyncEnabled {
            do {
                let remoteRoute = try await apiService.updateHistoryRoute(
                    routeId: route.id,
                    request: RouteHistoryUpdateRequest(
                        displayName: trimmedDisplayName,
                        notes: trimmedNotes,
                        startPointName: nil,
                        endPointName: nil
                    )
                )
                if let context = modelContext {
                    let routeId = route.id
                    let descriptor = FetchDescriptor<LocalRoute>()
                    if let localRoute = try? context.fetch(descriptor).first(where: { $0.id == routeId || $0.serverId == routeId }) {
                        localRoute.synced = true
                        localRoute.serverId = route.id
                        try? context.save()
                        updatedRoute = localRoute.toPastRoute
                    } else {
                        updatedRoute = remoteRoute
                    }
                }
            } catch {
                print("Failed to update remote history route: \(error.localizedDescription)")
                await syncService?.syncPendingRoutes()
            }
        }

        await loadHistory()
        return updatedRoute ?? pastRoutes.first(where: { $0.id == route.id })
    }

    @MainActor
    func deleteHistoryRoute(_ route: PastRoute) async {
        var shouldDeleteRemote = isUserLoggedIn && isCloudSyncEnabled

        if let context = modelContext {
            do {
                let routeId = route.id
                let descriptor = FetchDescriptor<LocalRoute>()
                if let localRoute = try context.fetch(descriptor).first(where: { $0.id == routeId || $0.serverId == routeId }) {
                    if shouldDeleteRemote && localRoute.serverId != nil {
                        localRoute.deleted = true
                        localRoute.synced = false
                    } else {
                        shouldDeleteRemote = false
                        context.delete(localRoute)
                    }
                    try context.save()
                }
            } catch {
                print("Failed to delete local history route: \(error.localizedDescription)")
            }
        }

        if shouldDeleteRemote {
            do {
                try await apiService.deleteHistoryRoute(routeId: route.id)
                if let context = modelContext {
                    let routeId = route.id
                    let descriptor = FetchDescriptor<LocalRoute>()
                    if let localRoute = try? context.fetch(descriptor).first(where: { $0.id == routeId || $0.serverId == routeId }) {
                        context.delete(localRoute)
                        try? context.save()
                    }
                }
            } catch {
                print("Failed to delete remote history route: \(error.localizedDescription)")
                await syncService?.syncPendingRoutes()
            }
        }

        clearHistorySelection()
        await loadHistory()
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
            await sync.syncPendingRouteTuningProfiles()
        }
        
        // Reload telemetry history for the logged-in user
        await loadRouteTuningProfiles()
        await loadHomeLocation()
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
        UserDefaults.standard.removeObject(forKey: "active_route_tuning_profile_id")
        
        self.pocketbaseToken = nil
        self.currentUserEmail = nil
        self.currentUserId = nil
        self.activeRouteTuningProfileId = nil
        self.homeLocation = nil
        self.homeLocationError = nil
        
        // Reload telemetry history for the guest
        Task {
            await loadRouteTuningProfiles()
            await loadHistory()
        }
    }
}

private struct CachedConfig: Codable {
    let presets: [PresetConfig]
    let weightsMetadata: [WeightConfig]
    let playgrounds: [Playground]
}
