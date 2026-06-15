import Foundation
import SwiftData

@Model
class LocalRoute {
    @Attribute(.unique) var id: String
    var serverId: String?
    var displayName: String?
    var notes: String?
    var startPointName: String
    var endPointName: String
    var startNearName: String?
    var endNearName: String?
    var startLat: Double
    var startLon: Double
    var endLat: Double
    var endLon: Double
    var region: String
    var totalLengthMeters: Double
    var totalEstimatedTimeSeconds: Double
    var status: String
    var startedAt: String
    var endedAt: String?
    var endedLat: Double?
    var endedLon: Double?
    var actualDistanceMeters: Double?
    var actualDurationSeconds: Double?
    var averageSpeed: Double?
    var deviceType: String?
    var weights: [String: Double]?
    
    // Sync states
    var userId: String? // nil for guests, PocketBase user ID for signed-in users
    var synced: Bool = false
    var deleted: Bool = false
    var routeGeojson: String? // Serialized GeoJSON string
    
    // Relationships
    @Relationship(deleteRule: .cascade, inverse: \LocalNavigationTick.route)
    var ticks: [LocalNavigationTick] = []
    
    init(
        id: String,
        serverId: String? = nil,
        displayName: String? = nil,
        notes: String? = nil,
        startPointName: String,
        endPointName: String,
        startNearName: String? = nil,
        endNearName: String? = nil,
        startLat: Double,
        startLon: Double,
        endLat: Double,
        endLon: Double,
        region: String = "boulder",
        totalLengthMeters: Double,
        totalEstimatedTimeSeconds: Double,
        status: String,
        startedAt: String,
        endedAt: String? = nil,
        endedLat: Double? = nil,
        endedLon: Double? = nil,
        actualDistanceMeters: Double? = nil,
        actualDurationSeconds: Double? = nil,
        averageSpeed: Double? = nil,
        deviceType: String? = nil,
        weights: [String: Double]? = nil,
        userId: String? = nil,
        synced: Bool = false,
        deleted: Bool = false,
        routeGeojson: String? = nil
    ) {
        self.id = id
        self.serverId = serverId
        self.displayName = displayName
        self.notes = notes
        self.startPointName = startPointName
        self.endPointName = endPointName
        self.startNearName = startNearName
        self.endNearName = endNearName
        self.startLat = startLat
        self.startLon = startLon
        self.endLat = endLat
        self.endLon = endLon
        self.region = region
        self.totalLengthMeters = totalLengthMeters
        self.totalEstimatedTimeSeconds = totalEstimatedTimeSeconds
        self.status = status
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.endedLat = endedLat
        self.endedLon = endedLon
        self.actualDistanceMeters = actualDistanceMeters
        self.actualDurationSeconds = actualDurationSeconds
        self.averageSpeed = averageSpeed
        self.deviceType = deviceType
        self.weights = weights
        self.userId = userId
        self.synced = synced
        self.deleted = deleted
        self.routeGeojson = routeGeojson
    }
    
    // Computed property to convert to PastRoute struct
    var toPastRoute: PastRoute {
        PastRoute(
            id: serverId ?? id,
            displayName: displayName,
            notes: notes,
            startPointName: startPointName,
            endPointName: endPointName,
            startNearName: startNearName,
            endNearName: endNearName,
            startLat: startLat,
            startLon: startLon,
            endLat: endLat,
            endLon: endLon,
            totalLengthMeters: totalLengthMeters,
            totalEstimatedTimeSeconds: totalEstimatedTimeSeconds,
            status: status,
            startedAt: startedAt,
            endedAt: endedAt,
            endedLat: endedLat,
            endedLon: endedLon,
            actualDistanceMeters: actualDistanceMeters,
            actualDurationSeconds: actualDurationSeconds,
            averageSpeed: averageSpeed,
            deviceType: deviceType,
            weights: weights
        )
    }
}

@Model
class LocalNavigationTick {
    var id: String // timestamp as unique string
    var lat: Double
    var lon: Double
    var speed: Double?
    var direction: Double?
    var accuracy: Double?
    var altitude: Double?
    var timestamp: String
    var batteryLevel: Double?
    
    // Relationship
    var route: LocalRoute?
    
    init(
        id: String,
        lat: Double,
        lon: Double,
        speed: Double? = nil,
        direction: Double? = nil,
        accuracy: Double? = nil,
        altitude: Double? = nil,
        timestamp: String,
        batteryLevel: Double? = nil,
        route: LocalRoute? = nil
    ) {
        self.id = id
        self.lat = lat
        self.lon = lon
        self.speed = speed
        self.direction = direction
        self.accuracy = accuracy
        self.altitude = altitude
        self.timestamp = timestamp
        self.batteryLevel = batteryLevel
        self.route = route
    }
    
    var toNavigationTick: NavigationTick {
        NavigationTick(
            lat: lat,
            lon: lon,
            speed: speed,
            direction: direction,
            accuracy: accuracy,
            altitude: altitude,
            timestamp: timestamp,
            batteryLevel: batteryLevel
        )
    }
}

@Model
class LocalRouteTuningProfile {
    @Attribute(.unique) var id: String
    var serverId: String?
    var name: String
    var weights: [String: Double]
    var offsets: [String: Double]
    var isDefault: Bool
    var userId: String?
    var synced: Bool
    var deleted: Bool
    var updatedAt: Date
    
    init(
        id: String = UUID().uuidString,
        serverId: String? = nil,
        name: String,
        weights: [String: Double],
        offsets: [String: Double] = [:],
        isDefault: Bool = false,
        userId: String? = nil,
        synced: Bool = false,
        deleted: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.serverId = serverId
        self.name = name
        self.weights = weights
        self.offsets = offsets
        self.isDefault = isDefault
        self.userId = userId
        self.synced = synced
        self.deleted = deleted
        self.updatedAt = updatedAt
    }
    
    var toRouteTuningProfile: RouteTuningProfile {
        RouteTuningProfile(
            id: serverId ?? id,
            localId: id,
            serverId: serverId,
            name: name,
            weights: weights,
            offsets: offsets,
            isDefault: isDefault,
            userId: userId,
            synced: synced
        )
    }
}
