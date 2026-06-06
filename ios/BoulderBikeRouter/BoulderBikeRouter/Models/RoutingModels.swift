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
    let startLat: Double
    let startLon: Double
    let endLat: Double
    let endLon: Double
    let waypoints: [[Double]] // List of [lat, lon] pairs
    let weights: [String: Double]

    enum CodingKeys: String, CodingKey {
        case startLat = "start_lat"
        case startLon = "start_lon"
        case endLat = "end_lat"
        case endLon = "end_lon"
        case waypoints
        case weights
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
    let segments: [RouteSegment]
    let totalLengthMeters: Double
    let totalWeight: Double
    let error: String?

    enum CodingKeys: String, CodingKey {
        case segments
        case totalLengthMeters = "total_length_meters"
        case totalWeight = "total_weight"
        case error
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

    enum CodingKeys: String, CodingKey {
        case name, desc, start, end, waypoints
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

/// Dynamic bootstrapper configuration payload.
struct BackendConfig: Codable {
    let presets: [PresetConfig]
    let weights: [WeightConfig]
}

/// Represents a completed route in the navigation history log.
struct PastRoute: Codable, Identifiable, Hashable {
    let id: String
    let startPointName: String
    let endPointName: String
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
    let deviceType: String?
    let weights: [String: Double]?

    enum CodingKeys: String, CodingKey {
        case id
        case startPointName = "start_point_name"
        case endPointName = "end_point_name"
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
        case deviceType = "device_type"
        case weights
    }

    // Compatibility Computed Properties for existing Views
    var name: String {
        return endPointName.isEmpty ? "Custom Route" : "\(endPointName) Route"
    }
    
    var date: Date {
        let formatter = ISO8601DateFormatter()
        let fallbackFormatter = DateFormatter()
        fallbackFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        
        if let d = formatter.date(from: startedAt) {
            return d
        } else if let d = fallbackFormatter.date(from: startedAt) {
            return d
        } else {
            let cleaned = startedAt.prefix(19) + "Z"
            if let d = formatter.date(from: String(cleaned)) {
                return d
            }
            return Date()
        }
    }
    
    var distanceMiles: Double {
        let meters = actualDistanceMeters ?? totalLengthMeters
        return meters / 1609.34
    }
    
    var durationSeconds: Int {
        if let actualSecs = actualDurationSeconds {
            return Int(actualSecs)
        }
        return Int(totalEstimatedTimeSeconds)
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

struct NavigationStartRequest: Codable {
    let startLat: Double
    let startLon: Double
    let endLat: Double
    let endLon: Double
    let startPointName: String
    let endPointName: String
    let routeGeojson: GeoJSONFeatureCollection
    let totalLengthMeters: Double
    let totalEstimatedTimeSeconds: Double
    let deviceType: String
    let weights: [String: Double]

    enum CodingKeys: String, CodingKey {
        case startLat = "start_lat"
        case startLon = "start_lon"
        case endLat = "end_lat"
        case endLon = "end_lon"
        case startPointName = "start_point_name"
        case endPointName = "end_point_name"
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

    enum CodingKeys: String, CodingKey {
        case status
        case endedLat = "ended_lat"
        case endedLon = "ended_lon"
        case endedAt = "ended_at"
    }
}

struct NavigationTick: Codable, Identifiable, Hashable {
    var id: String { timestamp }
    
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
    let startPointName: String
    let endPointName: String
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
    let deviceType: String?
    let weights: [String: Double]?
    let routeGeojson: GeoJSONFeatureCollection?
    let ticks: [NavigationTick]

    enum CodingKeys: String, CodingKey {
        case id
        case startPointName = "start_point_name"
        case endPointName = "end_point_name"
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
                CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0])
            }
        }
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


