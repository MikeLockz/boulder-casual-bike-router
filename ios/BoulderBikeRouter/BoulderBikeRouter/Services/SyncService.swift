import Foundation
import SwiftData

@MainActor
class SyncService {
    private let modelContext: ModelContext
    private let apiService = APIService()
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Sync locally edited route tuning profiles when authenticated and cloud sync is enabled.
    func syncPendingRouteTuningProfiles() async {
        guard UserDefaults.standard.object(forKey: "cloud_sync_enabled") as? Bool ?? true else {
            print("[SyncService] Cloud sync disabled, skipping profile sync.")
            return
        }
        guard UserDefaults.standard.string(forKey: "pocketbase_token") != nil,
              let userId = UserDefaults.standard.string(forKey: "logged_in_user_id") else {
            print("[SyncService] User is not authenticated, skipping profile sync.")
            return
        }

        let descriptor = FetchDescriptor<LocalRouteTuningProfile>(
            predicate: #Predicate<LocalRouteTuningProfile> { $0.synced == false || $0.deleted == true }
        )

        do {
            let pendingProfiles = try modelContext.fetch(descriptor)
            guard !pendingProfiles.isEmpty else { return }

            for localProfile in pendingProfiles {
                if localProfile.deleted {
                    if let serverId = localProfile.serverId {
                        do {
                            try await apiService.deleteRouteTuningProfile(serverId: serverId)
                        } catch {
                            print("[SyncService] Failed to delete profile \(serverId): \(error.localizedDescription)")
                            continue
                        }
                    }
                    modelContext.delete(localProfile)
                    continue
                }

                let payload = RouteTuningProfile(
                    id: localProfile.serverId ?? localProfile.id,
                    localId: localProfile.id,
                    serverId: localProfile.serverId,
                    name: localProfile.name,
                    weights: localProfile.weights,
                    offsets: localProfile.offsets,
                    isDefault: localProfile.isDefault,
                    userId: userId,
                    synced: false
                )

                do {
                    let syncedProfile: RouteTuningProfile
                    if let serverId = localProfile.serverId {
                        syncedProfile = try await apiService.updateRouteTuningProfile(payload, serverId: serverId)
                    } else {
                        syncedProfile = try await apiService.createRouteTuningProfile(payload)
                    }
                    localProfile.serverId = syncedProfile.id
                    localProfile.userId = userId
                    localProfile.synced = true
                    localProfile.deleted = false
                } catch {
                    print("[SyncService] Failed to sync route tuning profile \(localProfile.id): \(error.localizedDescription)")
                }
            }

            try modelContext.save()
        } catch {
            print("[SyncService] Profile sync error: \(error.localizedDescription)")
        }
    }
    
    /// Sync any local routes that haven't been synchronized with the remote backend database yet.
    func syncPendingRoutes() async {
        guard let token = UserDefaults.standard.string(forKey: "pocketbase_token"),
              let userId = UserDefaults.standard.string(forKey: "logged_in_user_id") else {
            print("[SyncService] User is not authenticated, skipping sync.")
            return
        }
        
        let descriptor = FetchDescriptor<LocalRoute>(
            predicate: #Predicate<LocalRoute> { $0.synced == false }
        )
        
        do {
            let pendingRoutes = try modelContext.fetch(descriptor)
            guard !pendingRoutes.isEmpty else {
                print("[SyncService] No pending unsynced routes found.")
                return
            }
            
            print("[SyncService] Found \(pendingRoutes.count) unsynced routes. Preparing sync payload...")
            
            var syncItems: [SyncRouteItem] = []
            
            for localRoute in pendingRoutes {
                let localTicks = localRoute.ticks
                
                var routeGeojsonObj: GeoJSONFeatureCollection? = nil
                if let geojsonStr = localRoute.routeGeojson,
                   let geojsonData = geojsonStr.data(using: .utf8) {
                    routeGeojsonObj = try? JSONDecoder().decode(GeoJSONFeatureCollection.self, from: geojsonData)
                }
                
                let tickItems = localTicks.map { t in
                    SyncTickItem(
                        lat: t.lat,
                        lon: t.lon,
                        speed: t.speed,
                        direction: t.direction,
                        accuracy: t.accuracy,
                        altitude: t.altitude,
                        timestamp: t.timestamp,
                        battery_level: t.batteryLevel
                    )
                }
                
                let routeItem = SyncRouteItem(
                    local_id: localRoute.id,
                    start_lat: localRoute.startLat,
                    start_lon: localRoute.startLon,
                    end_lat: localRoute.endLat,
                    end_lon: localRoute.endLon,
                    start_point_name: localRoute.startPointName,
                    end_point_name: localRoute.endPointName,
                    route_geojson: routeGeojsonObj,
                    total_length_meters: localRoute.totalLengthMeters,
                    total_estimated_time_seconds: localRoute.totalEstimatedTimeSeconds,
                    status: localRoute.status,
                    started_at: localRoute.startedAt,
                    ended_at: localRoute.endedAt,
                    ended_lat: localRoute.endedLat,
                    ended_lon: localRoute.endedLon,
                    actual_distance_meters: localRoute.actualDistanceMeters,
                    actual_duration_seconds: localRoute.actualDurationSeconds,
                    average_speed: localRoute.averageSpeed,
                    device_type: localRoute.deviceType ?? "ios",
                    weights: localRoute.weights ?? [:],
                    ticks: tickItems
                )
                
                syncItems.append(routeItem)
            }
            
            let payload = SyncRoutesPayload(routes: syncItems)
            
            // Perform POST to /api/navigation/sync
            let baseURLString = apiService.getBaseURL()
            guard let baseURL = URL(string: baseURLString),
                  let syncURL = URL(string: "/api/navigation/sync", relativeTo: baseURL) else {
                print("[SyncService] Invalid sync URL")
                return
            }
            
            var urlRequest = URLRequest(url: syncURL)
            urlRequest.httpMethod = "POST"
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            let encoder = JSONEncoder()
            urlRequest.httpBody = try encoder.encode(payload)
            
            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("[SyncService] Invalid URL response type.")
                return
            }
            
            if (200...299).contains(httpResponse.statusCode) {
                let syncResponse = try JSONDecoder().decode(SyncRoutesResponse.self, from: data)
                
                // Mark synced routes locally
                for syncedRoute in syncResponse.syncedRoutes {
                    if let matchingRoute = pendingRoutes.first(where: { $0.id == syncedRoute.localId }) {
                        matchingRoute.synced = true
                        matchingRoute.userId = userId
                        print("[SyncService] Successfully synced route: \(syncedRoute.localId)")
                    }
                }
                
                try modelContext.save()
                print("[SyncService] Local DB successfully updated and saved.")
            } else {
                let errString = String(data: data, encoding: .utf8) ?? ""
                print("[SyncService] Sync failed with status: \(httpResponse.statusCode). Error: \(errString)")
            }
            
        } catch {
            print("[SyncService] Sync error: \(error.localizedDescription)")
        }
    }
    
    /// Delete all user-synced history from the local SwiftData DB when signing out.
    func clearUserSyncedData() {
        print("[SyncService] Clearing user synced data from local DB...")
        do {
            let descriptor = FetchDescriptor<LocalRoute>(
                predicate: #Predicate<LocalRoute> { $0.userId != nil }
            )
            let userRoutes = try modelContext.fetch(descriptor)
            
            for route in userRoutes {
                modelContext.delete(route)
            }

            let profileDescriptor = FetchDescriptor<LocalRouteTuningProfile>(
                predicate: #Predicate<LocalRouteTuningProfile> { $0.userId != nil }
            )
            let userProfiles = try modelContext.fetch(profileDescriptor)
            for profile in userProfiles {
                modelContext.delete(profile)
            }
            
            try modelContext.save()
            print("[SyncService] Successfully deleted \(userRoutes.count) authenticated user routes and \(userProfiles.count) route tuning profiles.")
        } catch {
            print("[SyncService] Failed to clear user data: \(error.localizedDescription)")
        }
    }
}

// MARK: - Codable Payload Structs for Sync API

struct SyncRoutesPayload: Codable {
    let routes: [SyncRouteItem]
}

struct SyncRouteItem: Codable {
    let local_id: String
    let start_lat: Double
    let start_lon: Double
    let end_lat: Double
    let end_lon: Double
    let start_point_name: String
    let end_point_name: String
    let route_geojson: GeoJSONFeatureCollection?
    let total_length_meters: Double
    let total_estimated_time_seconds: Double
    let status: String
    let started_at: String
    let ended_at: String?
    let ended_lat: Double?
    let ended_lon: Double?
    let actual_distance_meters: Double?
    let actual_duration_seconds: Double?
    let average_speed: Double?
    let device_type: String
    let weights: [String: Double]
    let ticks: [SyncTickItem]
}

struct SyncTickItem: Codable {
    let lat: Double
    let lon: Double
    let speed: Double?
    let direction: Double?
    let accuracy: Double?
    let altitude: Double?
    let timestamp: String
    let battery_level: Double?
}

struct SyncRoutesResponse: Codable {
    let status: String
    let syncedRoutes: [SyncedRouteItem]
    
    enum CodingKeys: String, CodingKey {
        case status
        case syncedRoutes = "synced_routes"
    }
}

struct SyncedRouteItem: Codable {
    let localId: String
    let serverId: String
    
    enum CodingKeys: String, CodingKey {
        case localId = "local_id"
        case serverId = "server_id"
    }
}
