import Foundation

enum WatchNavigationStatus: String, Codable, Equatable {
    case inactive
    case navigating
    case offRoute
    case arrived
    case ended
}

struct WatchNavigationSnapshot: Codable, Equatable {
    let routeId: String?
    let status: WatchNavigationStatus
    let instruction: String
    let maneuverIconName: String
    let distanceToManeuverMeters: Double?
    let remainingDistanceText: String?
    let etaText: String?
    let updatedAt: Date

    static let inactive = WatchNavigationSnapshot(
        routeId: nil,
        status: .inactive,
        instruction: "Start navigation on iPhone",
        maneuverIconName: "iphone",
        distanceToManeuverMeters: nil,
        remainingDistanceText: nil,
        etaText: nil,
        updatedAt: Date()
    )
}

enum WatchNavigationDistanceFormatter {
    static func shortDistance(_ meters: Double?) -> String {
        guard let meters else { return "" }

        let feet = meters * 3.28084
        if feet < 950 {
            let roundedFeet = Int(round(feet / 10.0) * 10.0)
            return "\(max(0, roundedFeet)) ft"
        }

        let miles = meters / 1609.34
        if miles < 10 {
            return String(format: "%.1f mi", miles)
        }

        return "\(Int(round(miles))) mi"
    }
}
