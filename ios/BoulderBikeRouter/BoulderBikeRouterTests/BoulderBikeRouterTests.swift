//
//  BoulderBikeRouterTests.swift
//  BoulderBikeRouterTests
//
//  Created by MBP on 6/5/26.
//

import Testing
import SwiftData
import CoreLocation
@testable import BoulderBikeRouter

struct BoulderBikeRouterTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
        // Swift Testing Documentation
        // https://developer.apple.com/documentation/testing
    }

    @MainActor @Test func backendConfigDecodesLegacyRegionPayload() throws {
        let payload = """
        {
          "presets": [],
          "weights": [],
          "regions": {
            "boulder": {
              "name": "Boulder",
              "bbox": [39.96, -105.30, 40.09, -105.18]
            }
          }
        }
        """

        let config = try JSONDecoder().decode(BackendConfig.self, from: Data(payload.utf8))

        #expect(config.defaultRegion == "boulder")
        #expect(config.regions["boulder"]?.id == "boulder")
        #expect(config.regions["boulder"]?.center == [40.025, -105.24])
        #expect(config.regions["boulder"]?.capabilities.playgrounds == true)
    }

    @Test func watchNavigationDistanceFormatterUsesFeetForNearbyManeuvers() {
        #expect(WatchNavigationDistanceFormatter.shortDistance(30.48) == "100 ft")
    }

    @Test func watchNavigationDistanceFormatterUsesMilesForLongerDistances() {
        #expect(WatchNavigationDistanceFormatter.shortDistance(1609.34) == "1.0 mi")
    }

    @MainActor @Test func navigationManagerProgressesManeuversSequentially() throws {
        let manager = NavigationManager()
        
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: LocalRoute.self, LocalNavigationTick.self, LocalRouteTuningProfile.self, configurations: config)
        let modelContext = ModelContext(container)
        
        // Define route segments
        // Latitude: 1 degree = 111,000 meters.
        // Start: Lat 40.0, Lon -105.27.
        // Turn 1: Lat 40.0009 (~100m distance from start).
        // Destination: Lat 40.00315 (~350m total distance from start).
        let segment1 = RouteSegment(
            coords: [[40.0, -105.27], [40.0009, -105.27]],
            type: "separated_path",
            name: "Walnut St",
            length: 100.0,
            multiplier: 1.0,
            bikestress: nil,
            offstreetType: nil,
            bicyclesAllowed: nil,
            ebikeAllowed: nil
        )
        let segment2 = RouteSegment(
            coords: [[40.0009, -105.27], [40.00315, -105.27]],
            type: "separated_path",
            name: "Maple St",
            length: 250.0,
            multiplier: 1.0,
            bikestress: nil,
            offstreetType: nil,
            bicyclesAllowed: nil,
            ebikeAllowed: nil
        )
        
        // Start navigation
        manager.start(segments: [segment1, segment2], modelContext: modelContext)
        
        // Verify we started correctly
        #expect(manager.isActive)
        #expect(manager.maneuvers.count == 3) // Start Walnut, Turn onto Maple, Destination
        
        // Verify index is 0 initially (Walnut St)
        #expect(manager.currentManeuverIndex == 0)
        #expect(manager.currentBannerManeuver?.instruction.contains("Walnut") == true)
        
        // Send a location update at 0m (user is still at start)
        let startLoc = CLLocation(latitude: 40.0, longitude: -105.27)
        manager.updateLocation(startLoc)
        // With corrected logic, we remain on Maneuver 0 because we haven't traversed 20m yet (passedManeuverDistance)
        #expect(manager.currentManeuverIndex == 0)
        
        // Send location update at 15m along Walnut St (Lat 40.000135)
        let loc15m = CLLocation(latitude: 40.000135, longitude: -105.27)
        manager.updateLocation(loc15m)
        // Still on Maneuver 0 (15m < 20m threshold)
        #expect(manager.currentManeuverIndex == 0)
        
        // Send location update at 25m along Walnut St (Lat 40.000225)
        let loc25m = CLLocation(latitude: 40.000225, longitude: -105.27)
        manager.updateLocation(loc25m)
        // Now traversed >= 20m, should advance to Maneuver 1 (Turn onto Maple St)
        #expect(manager.currentManeuverIndex == 1)
        #expect(manager.currentBannerManeuver?.instruction.contains("Maple") == true)
        
        // Send location update at 115m (15m past the turn onto Maple St, Lat 40.001035)
        let loc115m = CLLocation(latitude: 40.001035, longitude: -105.27)
        manager.updateLocation(loc115m)
        // Turn is at 100m, threshold is 100 + 20 = 120m. Since 115m < 120m, we are still on Maneuver 1
        #expect(manager.currentManeuverIndex == 1)
        
        // Send location update at 125m (25m past the turn onto Maple St, Lat 40.001125)
        let loc125m = CLLocation(latitude: 40.001125, longitude: -105.27)
        manager.updateLocation(loc125m)
        // Now traversed 125m >= 120m threshold, should advance to Maneuver 2 (Destination)
        #expect(manager.currentManeuverIndex == 2)
        #expect(manager.currentBannerManeuver?.instruction.contains("destination") == true)
    }

}
