import Foundation
import CoreLocation

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
struct RouteResponse: Codable {
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
