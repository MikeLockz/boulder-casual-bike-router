import Foundation
import CoreLocation

extension CLLocationCoordinate2D: @retroactive Equatable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        return lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}

/// Represents a simple geographic coordinate.
struct GeoCoordinate: Codable, Equatable, Hashable {
    let latitude: Double
    let longitude: Double

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    init(clLocationCoordinate2D coordinate: CLLocationCoordinate2D) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }

    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// Request payload for the `/api/route` endpoint.
struct RouteRequest: Codable {
    let region: String
    let startLat: Double
    let startLon: Double
    let endLat: Double
    let endLon: Double
    let waypoints: [[Double]] // List of [lat, lon] pairs
    let weights: [String: Double]
    let offsets: [String: Double]?

    enum CodingKeys: String, CodingKey {
        case region
        case startLat = "start_lat"
        case startLon = "start_lon"
        case endLat = "end_lat"
        case endLon = "end_lon"
        case waypoints
        case weights
        case offsets
    }
}

struct AnalyticsSelectedPlace: Codable {
    let id: String?
    let name: String?
}

struct PlaceSearchAnalyticsRequest: Codable {
    let query: String
    let target: String?
    let limit: Int?
    let resultCount: Int?
    let selectedPlace: AnalyticsSelectedPlace?
    let source: String
    let clientSessionId: String
    let metadata: [String: String]?

    enum CodingKeys: String, CodingKey {
        case query
        case target
        case limit
        case resultCount = "result_count"
        case selectedPlace = "selected_place"
        case source
        case clientSessionId = "client_session_id"
        case metadata
    }
}

struct RouteAnalyticsEventRequest: Codable {
    let eventType: String
    let routeType: String?
    let routeId: String?
    let startLat: Double?
    let startLon: Double?
    let endLat: Double?
    let endLon: Double?
    let waypointCount: Int?
    let totalLengthMeters: Double?
    let totalWeight: Double?
    let segmentCount: Int?
    let startPointName: String?
    let endPointName: String?
    let weights: [String: Double]?
    let offsets: [String: Double]?
    let source: String
    let clientSessionId: String
    let metadata: [String: String]?

    enum CodingKeys: String, CodingKey {
        case eventType = "event_type"
        case routeType = "route_type"
        case routeId = "route_id"
        case startLat = "start_lat"
        case startLon = "start_lon"
        case endLat = "end_lat"
        case endLon = "end_lon"
        case waypointCount = "waypoint_count"
        case totalLengthMeters = "total_length_meters"
        case totalWeight = "total_weight"
        case segmentCount = "segment_count"
        case startPointName = "start_point_name"
        case endPointName = "end_point_name"
        case weights
        case offsets
        case source
        case clientSessionId = "client_session_id"
        case metadata
    }
}

/// Represents a single styled path segment on the map.
struct RouteSegment: Codable, Identifiable, Equatable {
    var id: String {
        // Compute simple unique ID based on first coordinate and name/type
        let firstCoord = coords.first ?? [0.0, 0.0]
        return "\(name)-\(type)-\(firstCoord[0])-\(firstCoord[1])"
    }

    let coords: [[Double]] // List of [lat, lon] pairs
    let type: String       // e.g., "separated_path", "residential", "crossing_safe"
    let name: String       // Street/path name
    let length: Double     // Distance in meters
    let multiplier: Double // Calculated weight modifier multiplier
    
    // Optional GIS details from OSM / Boulder Open Data
    let bikestress: String?
    let offstreetType: String?
    let bicyclesAllowed: String?
    let ebikeAllowed: String?

    enum CodingKeys: String, CodingKey {
        case coords, type, name, length, multiplier, bikestress
        case offstreetType = "offstreet_type"
        case bicyclesAllowed = "bicycles_allowed"
        case ebikeAllowed = "ebike_allowed"
    }
    
    var clCoordinates: [CLLocationCoordinate2D] {
        coords.map { CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1]) }
    }
}

/// Response payload from the `/api/route` endpoint.
struct RouteResponse: Codable, Equatable {
    var region: String? = nil
    let segments: [RouteSegment]
    let totalLengthMeters: Double
    let totalWeight: Double
    let error: String?

    enum CodingKeys: String, CodingKey {
        case region, segments
        case totalLengthMeters = "total_length_meters"
        case totalWeight = "total_weight"
        case error
    }

    var continuousCoordinates: [CLLocationCoordinate2D] {
        routeCoordinatePaths.flatMap { $0 }
    }

    var routeCoordinatePaths: [[CLLocationCoordinate2D]] {
        mergeRoutePaths(segments.map { $0.clCoordinates })
    }
}

/// Configuration representing a routing weight parameter from the backend.
struct WeightConfig: Codable, Identifiable, Hashable {
    var id: String { key }
    
    let key: String
    let name: String
    let description: String
    let webIcon: String
    let iosIcon: String
    let min: Double
    let max: Double
    let step: Double
    let `default`: Double

    enum CodingKeys: String, CodingKey {
        case key, name, description, min, max, step, `default`
        case webIcon = "web_icon"
        case iosIcon = "ios_icon"
    }
}

/// Configuration representing a preset route from the backend.
struct PresetConfig: Codable, Identifiable, Hashable {
    var id: String { name }

    let name: String
    let desc: String
    let start: [Double]
    let end: [Double]
    let waypoints: [[Double]]
    let routeType: String?
    var region: String? = nil

    enum CodingKeys: String, CodingKey {
        case name, desc, start, end, waypoints, region
        case routeType = "route_type"
    }

    var startCoordinate: CLLocationCoordinate2D {
        guard start.count >= 2 else { return CLLocationCoordinate2D() }
        return CLLocationCoordinate2D(latitude: start[0], longitude: start[1])
    }

    var endCoordinate: CLLocationCoordinate2D {
        guard end.count >= 2 else { return CLLocationCoordinate2D() }
        return CLLocationCoordinate2D(latitude: end[0], longitude: end[1])
    }

    var waypointCoordinates: [CLLocationCoordinate2D] {
        waypoints.compactMap { wp in
            guard wp.count >= 2 else { return nil }
            return CLLocationCoordinate2D(latitude: wp[0], longitude: wp[1])
        }
    }
}

struct RoutingRegionCapabilities: Codable, Hashable {
    let playgrounds: Bool
    let officialRoutes: Bool

    enum CodingKeys: String, CodingKey {
        case playgrounds
        case officialRoutes = "official_routes"
    }

    init(playgrounds: Bool, officialRoutes: Bool) {
        self.playgrounds = playgrounds
        self.officialRoutes = officialRoutes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        playgrounds = try container.decodeIfPresent(Bool.self, forKey: .playgrounds) ?? false
        officialRoutes = try container.decodeIfPresent(Bool.self, forKey: .officialRoutes) ?? true
    }
}

struct RoutingRegion: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let bbox: [Double]
    let center: [Double]
    let defaultZoom: Int
    let capabilities: RoutingRegionCapabilities

    enum CodingKeys: String, CodingKey {
        case id, name, bbox, center, capabilities
        case defaultZoom = "default_zoom"
    }

    init(
        id: String,
        name: String,
        bbox: [Double],
        center: [Double],
        defaultZoom: Int,
        capabilities: RoutingRegionCapabilities
    ) {
        self.id = id
        self.name = name
        self.bbox = bbox
        self.center = center
        self.defaultZoom = defaultZoom
        self.capabilities = capabilities
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        name = try container.decode(String.self, forKey: .name)
        bbox = try container.decode([Double].self, forKey: .bbox)
        center = try container.decodeIfPresent([Double].self, forKey: .center)
            ?? Self.center(of: bbox)
        defaultZoom = try container.decodeIfPresent(Int.self, forKey: .defaultZoom) ?? 13
        capabilities = try container.decodeIfPresent(RoutingRegionCapabilities.self, forKey: .capabilities)
            ?? RoutingRegionCapabilities(playgrounds: false, officialRoutes: true)
    }

    private static func center(of bbox: [Double]) -> [Double] {
        guard bbox.count == 4 else { return [] }
        return [(bbox[0] + bbox[2]) / 2, (bbox[1] + bbox[3]) / 2]
    }

    func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        guard bbox.count == 4 else { return false }
        return coordinate.latitude >= bbox[0] && coordinate.latitude <= bbox[2]
            && coordinate.longitude >= bbox[1] && coordinate.longitude <= bbox[3]
    }
}

/// Dynamic bootstrapper configuration payload.
struct BackendConfig: Codable {
    let presets: [PresetConfig]
    let weights: [WeightConfig]
    let regions: [String: RoutingRegion]
    let defaultRegion: String

    enum CodingKeys: String, CodingKey {
        case presets, weights, regions
        case defaultRegion = "default_region"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        presets = try container.decode([PresetConfig].self, forKey: .presets)
        weights = try container.decode([WeightConfig].self, forKey: .weights)

        let decodedRegions = try container.decode([String: RoutingRegion].self, forKey: .regions)
        regions = Dictionary(uniqueKeysWithValues: decodedRegions.map { regionKey, region in
            let regionId = region.id.isEmpty ? regionKey : region.id
            let capabilities = region.id.isEmpty && regionId == "boulder"
                ? RoutingRegionCapabilities(playgrounds: true, officialRoutes: true)
                : region.capabilities
            let normalizedRegion = RoutingRegion(
                id: regionId,
                name: region.name,
                bbox: region.bbox,
                center: region.center,
                defaultZoom: region.defaultZoom,
                capabilities: capabilities
            )
            return (regionKey, normalizedRegion)
        })
        defaultRegion = try container.decodeIfPresent(String.self, forKey: .defaultRegion)
            ?? (regions["boulder"] != nil ? "boulder" : regions.keys.sorted().first ?? "")
    }
}

/// Search result returned by `/api/autocomplete`.
struct PlaceSuggestion: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let type: String
    let lat: Double
    let lng: Double
    let source: String?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}

/// User-managed routing weights and offsets profile.
struct RouteTuningProfile: Codable, Identifiable, Hashable {
    let id: String
    let localId: String?
    let serverId: String?
    let name: String
    let weights: [String: Double]
    let offsets: [String: Double]
    let isDefault: Bool
    let userId: String?
    let synced: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case localId = "local_id"
        case serverId = "server_id"
        case name
        case weights
        case offsets
        case isDefault = "is_default"
        case userId = "user"
        case synced
    }
}

/// Authenticated home location setting stored as lat/lng coordinates.
struct HomeLocation: Codable, Identifiable, Hashable {
    let id: String?
    let lat: Double
    let lng: Double
    let created: String?
    let updated: String?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}

struct HomeLocationResponse: Codable {
    let home: HomeLocation?
}

struct HomeLocationRequest: Codable {
    let lat: Double
    let lng: Double
}

/// Represents a completed route in the navigation history log.
struct PastRoute: Codable, Identifiable, Hashable {
    let id: String
    var region: String? = nil
    let displayName: String?
    let notes: String?
    let startPointName: String
    let endPointName: String
    let startNearName: String?
    let endNearName: String?
    let startLat: Double
    let startLon: Double
    let endLat: Double
    let endLon: Double
    let totalLengthMeters: Double
    let totalEstimatedTimeSeconds: Double
    let status: String
    let startedAt: String
    let endedAt: String?
    let endedLat: Double?
    let endedLon: Double?
    let actualDistanceMeters: Double?
    let actualDurationSeconds: Double?
    let averageSpeed: Double?
    var displayDistanceMeters: Double? = nil
    var displayDurationSeconds: Double? = nil
    var displayAverageSpeed: Double? = nil
    let deviceType: String?
    let weights: [String: Double]?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case notes
        case startPointName = "start_point_name"
        case endPointName = "end_point_name"
        case startNearName = "start_near_name"
        case endNearName = "end_near_name"
        case startLat = "start_lat"
        case startLon = "start_lon"
        case endLat = "end_lat"
        case endLon = "end_lon"
        case totalLengthMeters = "total_length_meters"
        case totalEstimatedTimeSeconds = "total_estimated_time_seconds"
        case status
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case endedLat = "ended_lat"
        case endedLon = "ended_lon"
        case actualDistanceMeters = "actual_distance_meters"
        case actualDurationSeconds = "actual_duration_seconds"
        case averageSpeed = "average_speed"
        case displayDistanceMeters = "display_distance_meters"
        case displayDurationSeconds = "display_duration_seconds"
        case displayAverageSpeed = "display_average_speed"
        case deviceType = "device_type"
        case weights
    }

    // Compatibility Computed Properties for existing Views
    var name: String {
        if let displayName, !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return displayName
        }
        let destination = endPointName.trimmingCharacters(in: .whitespacesAndNewlines)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMMM d"
        return "Ride to \(destination.isEmpty ? "Destination" : destination) on \(formatter.string(from: date))"
    }
    
    var date: Date {
        Self.parseRouteDate(startedAt) ?? Date.distantPast
    }

    var endDate: Date? {
        guard let endedAt else { return nil }
        return Self.parseRouteDate(endedAt)
    }

    var displayedDistanceMeters: Double {
        if let displayDistanceMeters, displayDistanceMeters > 0 {
            return displayDistanceMeters
        }
        let actual = actualDistanceMeters ?? 0
        if actual > 0 {
            return actual
        }
        return totalLengthMeters
    }

    var displayedDurationSeconds: Double {
        if let displayDurationSeconds, displayDurationSeconds > 0 {
            return displayDurationSeconds
        }
        if let actualDurationSeconds, actualDurationSeconds > 0 {
            return actualDurationSeconds
        }
        if let endDate {
            let elapsed = endDate.timeIntervalSince(date)
            if elapsed > 0 {
                return elapsed
            }
        }
        return totalEstimatedTimeSeconds
    }

    var displayedAverageSpeedMetersPerSecond: Double? {
        if let displayAverageSpeed, displayAverageSpeed > 0 {
            return displayAverageSpeed
        }
        let duration = displayedDurationSeconds
        guard duration > 0 else { return nil }
        return displayedDistanceMeters / duration
    }

    private static func parseRouteDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = formatter.date(from: value) {
            return d
        }

        let internetFormatter = ISO8601DateFormatter()
        if let d = internetFormatter.date(from: value) {
            return d
        }

        let fallbackFormatter = DateFormatter()
        fallbackFormatter.locale = Locale(identifier: "en_US_POSIX")
        fallbackFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        if let d = fallbackFormatter.date(from: value) {
            return d
        }

        fallbackFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSZ"
        if let d = fallbackFormatter.date(from: value) {
            return d
        }

        let cleaned = value.replacingOccurrences(of: " ", with: "T")
        if cleaned.count >= 19 {
            return internetFormatter.date(from: String(cleaned.prefix(19)) + "Z")
        }
        return nil
    }
    
    var distanceMiles: Double {
        displayedDistanceMeters / 1609.34
    }
    
    var durationSeconds: Int {
        Int(displayedDurationSeconds.rounded())
    }
}

// MARK: - Telemetry Models

struct GeoJSONGeometry: Codable {
    let type: String
    let coordinates: [[[Double]]]
}

struct GeoJSONFeature: Codable {
    let type: String
    let geometry: GeoJSONGeometry
    let properties: [String: String]
}

struct GeoJSONFeatureCollection: Codable {
    let type: String
    let features: [GeoJSONFeature]
}

struct BikeRouteOverlay: Identifiable {
    let id: String
    let facilityType: String
    let name: String
    let coordinates: [CLLocationCoordinate2D]
}

struct NavigationStartRequest: Codable {
    let region: String
    let displayName: String?
    let notes: String?
    let startLat: Double
    let startLon: Double
    let endLat: Double
    let endLon: Double
    let startPointName: String
    let endPointName: String
    let startNearName: String?
    let endNearName: String?
    let routeGeojson: GeoJSONFeatureCollection
    let totalLengthMeters: Double
    let totalEstimatedTimeSeconds: Double
    let deviceType: String
    let weights: [String: Double]

    enum CodingKeys: String, CodingKey {
        case region
        case displayName = "display_name"
        case notes
        case startLat = "start_lat"
        case startLon = "start_lon"
        case endLat = "end_lat"
        case endLon = "end_lon"
        case startPointName = "start_point_name"
        case endPointName = "end_point_name"
        case startNearName = "start_near_name"
        case endNearName = "end_near_name"
        case routeGeojson = "route_geojson"
        case totalLengthMeters = "total_length_meters"
        case totalEstimatedTimeSeconds = "total_estimated_time_seconds"
        case deviceType = "device_type"
        case weights
    }
}

struct NavigationStartResponse: Codable {
    let status: String
    let routeId: String
    let startedAt: String

    enum CodingKeys: String, CodingKey {
        case status
        case routeId = "route_id"
        case startedAt = "started_at"
    }
}

struct NavigationTickRequest: Codable {
    let lat: Double
    let lon: Double
    let speed: Double
    let direction: Double
    let accuracy: Double
    let altitude: Double
    let timestamp: String
    let batteryLevel: Double?

    enum CodingKeys: String, CodingKey {
        case lat, lon, speed, direction, accuracy, altitude, timestamp
        case batteryLevel = "battery_level"
    }
}

struct NavigationEndRequest: Codable {
    let status: String
    let endedLat: Double?
    let endedLon: Double?
    let endedAt: String
    let ticks: [NavigationTickRequest]

    enum CodingKeys: String, CodingKey {
        case status
        case endedLat = "ended_lat"
        case endedLon = "ended_lon"
        case endedAt = "ended_at"
        case ticks
    }
}

struct NavigationTick: Codable, Identifiable, Hashable {
    var id: String { "\(timestamp)-\(lat)-\(lon)" }
    
    let lat: Double
    let lon: Double
    let speed: Double?
    let direction: Double?
    let accuracy: Double?
    let altitude: Double?
    let timestamp: String
    let batteryLevel: Double?

    enum CodingKeys: String, CodingKey {
        case lat, lon, speed, direction, accuracy, altitude, timestamp
        case batteryLevel = "battery_level"
    }
    
    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

struct DetailedRouteResponse: Codable {
    let id: String
    let displayName: String?
    let notes: String?
    let startPointName: String
    let endPointName: String
    let startNearName: String?
    let endNearName: String?
    let startLat: Double
    let startLon: Double
    let endLat: Double
    let endLon: Double
    let totalLengthMeters: Double
    let totalEstimatedTimeSeconds: Double
    let status: String
    let startedAt: String
    let endedAt: String?
    let endedLat: Double?
    let endedLon: Double?
    let actualDistanceMeters: Double?
    let actualDurationSeconds: Double?
    let averageSpeed: Double?
    var displayDistanceMeters: Double? = nil
    var displayDurationSeconds: Double? = nil
    var displayAverageSpeed: Double? = nil
    let deviceType: String?
    let weights: [String: Double]?
    let routeGeojson: GeoJSONFeatureCollection?
    let ticks: [NavigationTick]

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case notes
        case startPointName = "start_point_name"
        case endPointName = "end_point_name"
        case startNearName = "start_near_name"
        case endNearName = "end_near_name"
        case startLat = "start_lat"
        case startLon = "start_lon"
        case endLat = "end_lat"
        case endLon = "end_lon"
        case totalLengthMeters = "total_length_meters"
        case totalEstimatedTimeSeconds = "total_estimated_time_seconds"
        case status
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case endedLat = "ended_lat"
        case endedLon = "ended_lon"
        case actualDistanceMeters = "actual_distance_meters"
        case actualDurationSeconds = "actual_duration_seconds"
        case averageSpeed = "average_speed"
        case displayDistanceMeters = "display_distance_meters"
        case displayDurationSeconds = "display_duration_seconds"
        case displayAverageSpeed = "display_average_speed"
        case deviceType = "device_type"
        case weights
        case routeGeojson = "route_geojson"
        case ticks
    }
    
    var plannedRouteCoordinates: [[CLLocationCoordinate2D]] {
        guard let geojson = routeGeojson else { return [] }
        return geojson.features.compactMap { feature -> [CLLocationCoordinate2D]? in
            guard !feature.geometry.coordinates.isEmpty else { return nil }
            let coords = feature.geometry.coordinates[0]
            return coords.map { pair in
                if abs(pair[0]) <= 90, abs(pair[1]) > 90 {
                    return CLLocationCoordinate2D(latitude: pair[0], longitude: pair[1])
                }
                return CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0])
            }
        }
    }

    var plannedRouteCoordinatePaths: [[CLLocationCoordinate2D]] {
        mergeRoutePaths(plannedRouteCoordinates)
    }

    /// The recorded GPS trace, ordered chronologically and stripped of invalid points.
    /// History maps should prefer this over `routeGeojson`, which is the original plan.
    var actualRouteCoordinatePath: [CLLocationCoordinate2D] {
        let coordinates = ticks
            .filter {
                $0.lat.isFinite && $0.lon.isFinite &&
                (-90.0...90.0).contains($0.lat) &&
                (-180.0...180.0).contains($0.lon)
            }
            .sorted { $0.timestamp < $1.timestamp }
            .map(\.clCoordinate)

        if coordinates.count < 2 {
            return coordinates
        }
        return mergeRoutePaths([coordinates]).first ?? []
    }
}

private func mergeRoutePaths(_ paths: [[CLLocationCoordinate2D]]) -> [[CLLocationCoordinate2D]] {
    // Join adjacent segments at their shared endpoints first
    let merged = paths.reduce(into: [[CLLocationCoordinate2D]]()) { mergedPaths, path in
        guard path.count >= 2 else { return }
        guard !mergedPaths.isEmpty else { mergedPaths.append(path); return }
        if mergedPaths[mergedPaths.count - 1].last?.isSameRoutePoint(as: path[0]) == true {
            mergedPaths[mergedPaths.count - 1].append(contentsOf: path.dropFirst())
        } else {
            mergedPaths.append(path)
        }
    }
    // Remove points within ~1 m of each other to prevent MapKit stroke triangulation failures
    return merged.compactMap { path in
        let deduped = path.reduce(into: [CLLocationCoordinate2D]()) { result, coord in
            guard let last = result.last else { result.append(coord); return }
            if abs(last.latitude - coord.latitude) > 0.00001 || abs(last.longitude - coord.longitude) > 0.00001 {
                result.append(coord)
            }
        }
        return deduped.count >= 2 ? deduped : nil
    }
}

private extension CLLocationCoordinate2D {
    func isSameRoutePoint(as other: CLLocationCoordinate2D) -> Bool {
        abs(latitude - other.latitude) < 0.0000001 && abs(longitude - other.longitude) < 0.0000001
    }
}

struct RouteHistoryUpdateRequest: Codable {
    let displayName: String?
    let notes: String?
    let startPointName: String?
    let endPointName: String?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case notes
        case startPointName = "start_point_name"
        case endPointName = "end_point_name"
    }
}

// MARK: - User Authentication Models

/// Response containing the PocketBase user auth token and user details.
struct AuthResponse: Codable {
    let token: String
    let record: UserRecord
}

/// Details of the authenticated user.
struct UserRecord: Codable {
    let id: String
    let email: String
}

/// Detailed PocketBase response on validation failures or generic server errors.
struct PocketBaseError: Codable {
    let code: Int
    let message: String
    let data: [String: PocketBaseErrorDetail]?
}

struct PocketBaseErrorDetail: Codable {
    let code: String
    let message: String
}

// MARK: - Geocoding Models

struct ResolvedPlace: Codable, Equatable, Hashable {
    let id: String?
    let name: String
    let type: String?
    let lat: Double
    let lng: Double
    let distanceMeters: Double?

    enum CodingKeys: String, CodingKey {
        case id, name, type, lat, lng
        case distanceMeters = "distance_meters"
    }
}

struct NearestPlaceResponse: Codable, Equatable, Hashable {
    let place: ResolvedPlace?
    let displayName: String

    enum CodingKeys: String, CodingKey {
        case place
        case displayName = "display_name"
    }
}
