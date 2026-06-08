import Foundation
import CoreLocation

/// Shared navigation metric filtering for iOS, web, and Flask implementations.
/// Keep these constants in sync with backend/app.py and frontend/navigationMetricsFilter.js.
enum NavigationMetricFilter {
    nonisolated static let maxAccuracyMeters = 75.0
    nonisolated static let stationaryRadiusMeters = 65.0
    nonisolated static let idleAutoEndSeconds = 2700.0
    nonisolated static let maxStepSpeedMps = 15.0

    struct Summary {
        let ticks: [NavigationTickRequest]
        let distanceMeters: Double
        let durationSeconds: Double
        let idleCutoffAt: Date?
    }

    nonisolated private static func parseDate(_ value: String) -> Date? {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: value) {
            return date
        }
        let fallback = ISO8601DateFormatter()
        return fallback.date(from: value)
    }

    nonisolated private static func usableTick(_ tick: NavigationTickRequest) -> (tick: NavigationTickRequest, date: Date)? {
        guard (-90.0...90.0).contains(tick.lat),
              (-180.0...180.0).contains(tick.lon),
              tick.accuracy <= maxAccuracyMeters,
              let date = parseDate(tick.timestamp) else {
            return nil
        }
        return (tick, date)
    }

    nonisolated static func summarize(_ ticks: [NavigationTickRequest]) -> Summary {
        let usable = ticks.compactMap(usableTick).sorted { $0.date < $1.date }
        guard let first = usable.first else {
            return Summary(ticks: [], distanceMeters: 0, durationSeconds: 0, idleCutoffAt: nil)
        }

        var kept: [(tick: NavigationTickRequest, date: Date)] = [first]
        var anchor = first
        var distanceMeters = 0.0
        var idleCutoffAt: Date?

        for item in usable.dropFirst() {
            let elapsed = max(0.0, item.date.timeIntervalSince(anchor.date))
            let anchorLocation = CLLocation(latitude: anchor.tick.lat, longitude: anchor.tick.lon)
            let itemLocation = CLLocation(latitude: item.tick.lat, longitude: item.tick.lon)
            let stepDistance = anchorLocation.distance(from: itemLocation)

            if elapsed > 0, stepDistance / elapsed > maxStepSpeedMps {
                continue
            }

            if stepDistance <= stationaryRadiusMeters {
                if elapsed >= idleAutoEndSeconds {
                    idleCutoffAt = anchor.date.addingTimeInterval(idleAutoEndSeconds)
                    break
                }
                kept.append(item)
                continue
            }

            distanceMeters += stepDistance
            anchor = item
            kept.append(item)
        }

        let duration = kept.last.map { max(0.0, $0.date.timeIntervalSince(kept[0].date)) } ?? 0.0
        return Summary(
            ticks: kept.map(\.tick),
            distanceMeters: distanceMeters,
            durationSeconds: duration,
            idleCutoffAt: idleCutoffAt
        )
    }

    nonisolated static func shouldAutoEndForIdle(anchor: CLLocation, current: CLLocation, now: Date = Date()) -> Bool {
        current.distance(from: anchor) <= stationaryRadiusMeters
            && now.timeIntervalSince(anchor.timestamp) >= idleAutoEndSeconds
    }
}
