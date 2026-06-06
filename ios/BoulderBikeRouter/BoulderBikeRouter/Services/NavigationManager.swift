import Foundation
import CoreLocation
import AVFoundation
import UIKit
import SwiftData

/// Represents a single maneuver instruction during active navigation.
struct Maneuver: Identifiable, Equatable {
    let id = UUID()
    let instruction: String
    let shortInstruction: String
    let distanceFromStart: Double      // Meters
    let triggerCoordinate: CLLocationCoordinate2D?
    let iconName: String               // SF Symbol name e.g. "arrow.turn.up.right"
    let distanceToNext: Double         // Meters

    static func == (lhs: Maneuver, rhs: Maneuver) -> Bool {
        lhs.id == rhs.id
    }
}

/// Manages active route turn guidance, voice announcements, and navigation banners.
@Observable
class NavigationManager {
    var isActive: Bool = false
    var isMuted: Bool = false
    var currentManeuverIndex: Int = 0
    var maneuvers: [Maneuver] = []
    
    // Bottom bar stats
    var remainingDistanceString: String = "-- mi"
    var etaString: String = "-- min"
    var currentBannerManeuver: Maneuver?
    var distanceToNextManeuverString: String = ""

    private var routeCoords: [CLLocationCoordinate2D] = []
    private var segments: [RouteSegment] = []
    private let speechSynthesizer = AVSpeechSynthesizer()
    
    // Telemetry properties
    private var activeRouteId: String? = nil
    private var lastLoggedLocation: CLLocation? = nil
    private var lastLoggedTime: Date? = nil
    private let apiService = APIService()
    
    // Local persistence properties
    private var modelContext: ModelContext? = nil
    private var localTicksCache: [NavigationTickRequest] = []
    private var localStartRequest: NavigationStartRequest? = nil
    private var routeGeojsonString: String? = nil
    private var startedAtString: String? = nil
    
    // Proximity triggers to prevent repeating announcements
    private var announcedPre = Set<Int>()
    private var announcedConfirm = Set<Int>()
    
    private let preAnnounceDistance: Double = 200.0 // meters (~650 ft)
    private let confirmDistance: Double = 30.0     // meters (~100 ft)
    private let casualSpeedMps = 4.47              // 10 mph in meters/second

    private var isSyncActive: Bool {
        let hasToken = UserDefaults.standard.string(forKey: "pocketbase_token") != nil
        let isSyncEnabled = UserDefaults.standard.object(forKey: "cloud_sync_enabled") as? Bool ?? true
        return hasToken && isSyncEnabled
    }

    func start(segments: [RouteSegment], modelContext: ModelContext) {
        guard !segments.isEmpty else { return }
        
        self.modelContext = modelContext
        self.segments = segments
        self.routeCoords = flattenSegments(segments)
        self.maneuvers = buildManeuvers(from: segments)
        self.currentManeuverIndex = 0
        self.announcedPre.removeAll()
        self.announcedConfirm.removeAll()
        self.isActive = true
        
        let now = Date()
        let isoFormatter = ISO8601DateFormatter()
        self.startedAtString = isoFormatter.string(from: now)
        
        // Prevent screen sleep during navigation
        UIApplication.shared.isIdleTimerDisabled = true
        
        speak("Starting navigation to destination. Stay safe.")
        updateOverlay(distanceFromStart: 0)
        
        // Setup battery monitoring
        UIDevice.current.isBatteryMonitoringEnabled = true
        
        // Prepare start request
        let startLat = segments.first?.coords.first?.first ?? 0.0
        let startLon = segments.first?.coords.first?.last ?? 0.0
        
        let lastSegment = segments.last
        let lastCoord = lastSegment?.coords.last
        let endLat = lastCoord?.first ?? 0.0
        let endLon = lastCoord?.last ?? 0.0
        
        let totalLength = segments.reduce(0.0) { $0 + $1.length }
        let estTime = totalLength / casualSpeedMps
        
        let features = segments.map { seg -> GeoJSONFeature in
            let geometry = GeoJSONGeometry(type: "LineString", coordinates: [seg.coords])
            let props = [
                "name": seg.name,
                "type": seg.type,
                "length": String(seg.length)
            ]
            return GeoJSONFeature(type: "Feature", geometry: geometry, properties: props)
        }
        let geojson = GeoJSONFeatureCollection(type: "FeatureCollection", features: features)
        
        let weights = [String: Double]()
        
        let startReq = NavigationStartRequest(
            startLat: startLat,
            startLon: startLon,
            endLat: endLat,
            endLon: endLon,
            startPointName: "Start Point",
            endPointName: segments.last?.name ?? "Destination",
            routeGeojson: geojson,
            totalLengthMeters: totalLength,
            totalEstimatedTimeSeconds: estTime,
            deviceType: "ios",
            weights: weights
        )
        
        self.localStartRequest = startReq
        self.localTicksCache.removeAll()
        
        // Save GeoJSON string representation
        let encoder = JSONEncoder()
        if let geojsonData = try? encoder.encode(geojson),
           let geojsonStr = String(data: geojsonData, encoding: .utf8) {
            self.routeGeojsonString = geojsonStr
        }
        
        if isSyncActive {
            Task {
                do {
                    let rId = try await apiService.startNavigation(request: startReq)
                    await MainActor.run {
                        self.activeRouteId = rId
                        self.lastLoggedTime = Date()
                        print("[NavigationManager] Telemetry route started remotely: \(rId)")
                    }
                } catch {
                    print("[NavigationManager] Failed to start telemetry route remotely: \(error.localizedDescription)")
                    // Fall back to local ID if API fails
                    await MainActor.run {
                        self.activeRouteId = UUID().uuidString
                        self.lastLoggedTime = Date()
                    }
                }
            }
        } else {
            self.activeRouteId = UUID().uuidString
            self.lastLoggedTime = Date()
            print("[NavigationManager] Navigation session starting locally (Cloud Sync is disabled or guest).")
        }
    }

    func stop() {
        isActive = false
        maneuvers.removeAll()
        routeCoords.removeAll()
        segments.removeAll()
        currentBannerManeuver = nil
        
        // Re-enable screen sleep
        UIApplication.shared.isIdleTimerDisabled = false
        
        speak("Navigation ended.")
        
        guard let rId = activeRouteId else { return }
        
        let now = Date()
        let isoFormatter = ISO8601DateFormatter()
        let endedAtStr = isoFormatter.string(from: now)
        
        var status = "cancelled"
        var finalLat: Double? = nil
        var finalLon: Double? = nil
        
        if let currentLoc = lastLoggedLocation {
            finalLat = currentLoc.coordinate.latitude
            finalLon = currentLoc.coordinate.longitude
            if let dest = routeCoords.last {
                let destLoc = CLLocation(latitude: dest.latitude, longitude: dest.longitude)
                let dist = currentLoc.distance(from: destLoc)
                if dist <= 50.0 {
                    status = "completed"
                }
            }
        }
        
        // 1. Calculate actual distance and duration locally from cached ticks
        var actualDistance = 0.0
        if localTicksCache.count >= 2 {
            for i in 0..<(localTicksCache.count - 1) {
                let t1 = localTicksCache[i]
                let t2 = localTicksCache[i+1]
                let loc1 = CLLocation(latitude: t1.lat, longitude: t1.lon)
                let loc2 = CLLocation(latitude: t2.lat, longitude: t2.lon)
                actualDistance += loc1.distance(from: loc2)
            }
        }
        
        var actualDuration = 0.0
        if let firstTick = localTicksCache.first,
           let lastTick = localTicksCache.last {
            let fTime = isoFormatter.date(from: firstTick.timestamp) ?? Date()
            let lTime = isoFormatter.date(from: lastTick.timestamp) ?? Date()
            actualDuration = lTime.timeIntervalSince(fTime)
        }
        if actualDuration <= 0 {
            actualDuration = Double(localTicksCache.count) * 3.0
        }
        
        let avgSpeed = actualDuration > 0 ? (actualDistance / actualDuration) : 0.0
        
        // 2. Save locally to SwiftData
        if let startReq = localStartRequest, let context = modelContext {
            let currentUserId = UserDefaults.standard.string(forKey: "logged_in_user_id")
            let localRoute = LocalRoute(
                id: rId,
                startPointName: startReq.startPointName,
                endPointName: startReq.endPointName,
                startLat: startReq.startLat,
                startLon: startReq.startLon,
                endLat: startReq.endLat,
                endLon: startReq.endLon,
                totalLengthMeters: startReq.totalLengthMeters,
                totalEstimatedTimeSeconds: startReq.totalEstimatedTimeSeconds,
                status: status,
                startedAt: startedAtString ?? endedAtStr,
                endedAt: endedAtStr,
                endedLat: finalLat,
                endedLon: finalLon,
                actualDistanceMeters: actualDistance,
                actualDurationSeconds: actualDuration,
                averageSpeed: avgSpeed,
                deviceType: "ios",
                weights: startReq.weights,
                userId: currentUserId,
                synced: isSyncActive,
                routeGeojson: routeGeojsonString
            )
            
            context.insert(localRoute)
            
            // Insert ticks associated with the route
            for (idx, t) in localTicksCache.enumerated() {
                let tickModel = LocalNavigationTick(
                    id: "\(rId)-\(idx)",
                    lat: t.lat,
                    lon: t.lon,
                    speed: t.speed,
                    direction: t.direction,
                    accuracy: t.accuracy,
                    altitude: t.altitude,
                    timestamp: t.timestamp,
                    batteryLevel: t.batteryLevel,
                    route: localRoute
                )
                context.insert(tickModel)
            }
            
            do {
                try context.save()
                print("[NavigationManager] Session successfully saved locally to SwiftData: \(rId)")
            } catch {
                print("[NavigationManager] SwiftData save error: \(error.localizedDescription)")
            }
        }
        
        // 3. Close the telemetry session on the server if sync is active
        if isSyncActive {
            let endReq = NavigationEndRequest(
                status: status,
                endedLat: finalLat,
                endedLon: finalLon,
                endedAt: endedAtStr
            )
            
            Task {
                do {
                    try await apiService.endNavigation(routeId: rId, request: endReq)
                    print("[NavigationManager] Telemetry route closed remotely successfully.")
                } catch {
                    print("[NavigationManager] Failed to end telemetry route remotely: \(error.localizedDescription)")
                }
                
                await MainActor.run {
                    NotificationCenter.default.post(name: NSNotification.Name("TelemetryRouteEnded"), object: nil)
                }
            }
        } else {
            NotificationCenter.default.post(name: NSNotification.Name("TelemetryRouteEnded"), object: nil)
        }
        
        // Cleanup local states
        activeRouteId = nil
        lastLoggedLocation = nil
        lastLoggedTime = nil
        localStartRequest = nil
        routeGeojsonString = nil
        startedAtString = nil
        localTicksCache.removeAll()
    }

    func toggleMute() {
        isMuted.toggle()
        if !isMuted {
            speak("Voice guidance unmuted.")
        }
    }

    /// Primary navigation tick invoked when GPS location updates.
    func updateLocation(_ location: CLLocation) {
        guard isActive, !routeCoords.isEmpty else { return }

        // Find closest point on the route
        let userCoord = location.coordinate
        let (closestIdx, minDistance) = findClosestPoint(userCoord)

        // Off-route warning
        if minDistance > 50.0 { // 50 meters off route
            // Optionally speak warning
        }

        // Calculate progress along route
        let totalMeters = calculateTotalRouteDistance()
        let traversedMeters = calculateDistanceTraversed(toIndex: closestIdx)
        let remainingMeters = max(0.0, totalMeters - traversedMeters)
        
        // Update remaining stats
        let miles = remainingMeters / 1609.34
        remainingDistanceString = String(format: "%.1f mi", miles)
        
        let remainingMinutes = Int(ceil(remainingMeters / casualSpeedMps / 60.0))
        etaString = "\(remainingMinutes) min"

        // Check proximity to maneuvers
        checkManeuversProximity(userLocation: location, closestRouteIdx: closestIdx)
        
        // Log telemetry tick
        logLocationTick(location)
    }

    private func checkManeuversProximity(userLocation: CLLocation, closestRouteIdx: Int) {
        guard currentManeuverIndex < maneuvers.count else { return }

        let currentManeuver = maneuvers[currentManeuverIndex]
        guard let triggerCoord = currentManeuver.triggerCoordinate else { return }
        
        let triggerLoc = CLLocation(latitude: triggerCoord.latitude, longitude: triggerCoord.longitude)
        let distanceToTrigger = userLocation.distance(from: triggerLoc)

        // Update banner text & distance label
        currentBannerManeuver = currentManeuver
        distanceToNextManeuverString = formatDistanceShort(distanceToTrigger)

        // Trigger announcements
        let idx = currentManeuverIndex
        if distanceToTrigger <= preAnnounceDistance, !announcedPre.contains(idx) {
            announcedPre.insert(idx)
            let feet = Int(round(distanceToTrigger * 3.28084 / 50.0) * 50.0)
            speak("In \(feet) feet, \(currentManeuver.instruction)")
        }

        if distanceToTrigger <= confirmDistance, !announcedConfirm.contains(idx) {
            announcedConfirm.insert(idx)
            speak("\(currentManeuver.instruction) now.")
            
            // Advance to next instruction after trigger zone
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                guard let self = self else { return }
                if self.currentManeuverIndex == idx {
                    self.currentManeuverIndex += 1
                }
            }
        }
    }

    private func speak(_ text: String) {
        guard !isMuted else { return }
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        
        // Stop current speaking and start new announcement
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        speechSynthesizer.speak(utterance)
    }

    private func updateOverlay(distanceFromStart: Double) {
        if maneuvers.isEmpty { return }
        currentBannerManeuver = maneuvers.first
        distanceToNextManeuverString = ""
    }

    // MARK: - Helpers

    private func flattenSegments(_ segments: [RouteSegment]) -> [CLLocationCoordinate2D] {
        var coords: [CLLocationCoordinate2D] = []
        for segment in segments {
            for c in segment.clCoordinates {
                if let last = coords.last {
                    if last.latitude == c.latitude && last.longitude == c.longitude {
                        continue
                    }
                }
                coords.append(c)
            }
        }
        return coords
    }

    private func findClosestPoint(_ userCoord: CLLocationCoordinate2D) -> (index: Int, distance: Double) {
        var closestIndex = 0
        var minDistance = Double.infinity
        
        let userLoc = CLLocation(latitude: userCoord.latitude, longitude: userCoord.longitude)
        for (idx, coord) in routeCoords.enumerated() {
            let ptLoc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            let dist = userLoc.distance(from: ptLoc)
            if dist < minDistance {
                minDistance = dist
                closestIndex = idx
            }
        }
        return (closestIndex, minDistance)
    }

    private func calculateTotalRouteDistance() -> Double {
        return segments.reduce(0.0) { $0 + $1.length }
    }

    private func calculateDistanceTraversed(toIndex: Int) -> Double {
        guard toIndex > 0 && toIndex < routeCoords.count else { return 0.0 }
        var dist = 0.0
        for idx in 0..<toIndex {
            let pt1 = CLLocation(latitude: routeCoords[idx].latitude, longitude: routeCoords[idx].longitude)
            let pt2 = CLLocation(latitude: routeCoords[idx+1].latitude, longitude: routeCoords[idx+1].longitude)
            dist += pt1.distance(from: pt2)
        }
        return dist
    }

    private func formatDistanceShort(_ meters: Double) -> String {
        let miles = meters / 1609.34
        if miles < 0.1 {
            let feet = Int(round(meters * 3.28084 / 10.0) * 10.0)
            return "\(feet) ft"
        }
        return String(format: "%.1f mi", miles)
    }

    /// Build simple mock maneuver announcements based on segment intersections
    private func buildManeuvers(from segments: [RouteSegment]) -> [Maneuver] {
        var maneuversList: [Maneuver] = []
        var accumDistance = 0.0

        for (idx, seg) in segments.enumerated() {
            let coords = seg.clCoordinates
            guard coords.count >= 2 else { continue }
            
            let startCoord = coords.first
            
            let instruction: String
            let shortInstruction: String
            let iconName: String
            
            if idx == 0 {
                instruction = "Head \(getCompassDirection(pt1: coords[0], pt2: coords[1])) on \(seg.name)"
                shortInstruction = "Go straight"
                iconName = "arrow.up"
            } else {
                let prevSeg = segments[idx - 1]
                let turn = getTurnManeuver(prev: prevSeg, next: seg)
                instruction = "\(turn.action) on \(seg.name)"
                shortInstruction = turn.action
                iconName = turn.icon
            }
            
            maneuversList.append(Maneuver(
                instruction: instruction,
                shortInstruction: shortInstruction,
                distanceFromStart: accumDistance,
                triggerCoordinate: startCoord,
                iconName: iconName,
                distanceToNext: seg.length
            ))
            
            accumDistance += seg.length
        }
        
        // Add final destination arrival
        if let lastCoord = segments.last?.clCoordinates.last {
            maneuversList.append(Maneuver(
                instruction: "Arrive at destination",
                shortInstruction: "Arrived",
                distanceFromStart: accumDistance,
                triggerCoordinate: lastCoord,
                iconName: "mappin.and.ellipse",
                distanceToNext: 0.0
            ))
        }

        return maneuversList
    }

    private func getCompassDirection(pt1: CLLocationCoordinate2D, pt2: CLLocationCoordinate2D) -> String {
        let lat1 = pt1.latitude * .pi / 180.0
        let lat2 = pt2.latitude * .pi / 180.0
        let dLon = (pt2.longitude - pt1.longitude) * .pi / 180.0
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let bearing = (atan2(y, x) * 180.0 / .pi + 360.0).truncatingRemainder(dividingBy: 360.0)
        
        let directions = ["North", "North East", "East", "South East", "South", "South West", "West", "North West"]
        let index = Int(round(bearing / 45.0).truncatingRemainder(dividingBy: 8.0))
        return directions[index]
    }

    private func getTurnManeuver(prev: RouteSegment, next: RouteSegment) -> (action: String, icon: String) {
        guard prev.clCoordinates.count >= 2, next.clCoordinates.count >= 2 else {
            return ("Continue", "arrow.up")
        }
        let pt1 = prev.clCoordinates[prev.clCoordinates.count - 2]
        let pt2 = prev.clCoordinates.last!
        let pt3 = next.clCoordinates[1]
        
        let b1 = calculateBearing(pt1, pt2)
        let b2 = calculateBearing(pt2, pt3)
        
        var diff = b2 - b1
        while diff > 180 { diff -= 360 }
        while diff < -180 { diff += 360 }
        
        if diff < -45 {
            return ("Turn left", "arrow.turn.up.left")
        } else if diff > 45 {
            return ("Turn right", "arrow.turn.up.right")
        } else {
            return ("Continue straight", "arrow.up")
        }
    }

    private func calculateBearing(_ pt1: CLLocationCoordinate2D, _ pt2: CLLocationCoordinate2D) -> Double {
        let lat1 = pt1.latitude * .pi / 180.0
        let lat2 = pt2.latitude * .pi / 180.0
        let dLon = (pt2.longitude - pt1.longitude) * .pi / 180.0
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return (atan2(y, x) * 180.0 / .pi + 360.0).truncatingRemainder(dividingBy: 360.0)
    }

    private func logLocationTick(_ location: CLLocation) {
        guard let routeId = activeRouteId else { return }
        
        let now = Date()
        if let lastTime = lastLoggedTime {
            let timeElapsed = now.timeIntervalSince(lastTime)
            
            var shouldLog = false
            if let lastLoc = lastLoggedLocation {
                let dist = location.distance(from: lastLoc)
                if dist >= 2.0 || timeElapsed >= 3.0 {
                    shouldLog = true
                }
            } else {
                shouldLog = true
            }
            
            if !shouldLog { return }
        } else {
            lastLoggedTime = now
        }
        
        self.lastLoggedLocation = location
        self.lastLoggedTime = now
        
        let speed = location.speed >= 0 ? location.speed : 0.0
        let heading = location.course >= 0 ? location.course : 0.0
        let accuracy = location.horizontalAccuracy
        let altitude = location.altitude
        
        let isoFormatter = ISO8601DateFormatter()
        let timestampStr = isoFormatter.string(from: location.timestamp)
        
        let tickReq = NavigationTickRequest(
            lat: location.coordinate.latitude,
            lon: location.coordinate.longitude,
            speed: speed,
            direction: heading,
            accuracy: accuracy,
            altitude: altitude,
            timestamp: timestampStr,
            batteryLevel: Double(UIDevice.current.batteryLevel)
        )
        
        // Cache locally in ticks buffer
        localTicksCache.append(tickReq)
        
        if isSyncActive {
            Task {
                do {
                    try await apiService.sendLocationTick(routeId: routeId, request: tickReq)
                } catch {
                    print("[NavigationManager] Failed to send telemetry tick: \(error.localizedDescription)")
                }
            }
        }
    }
}
