//
//  BoulderBikeRouter_Watch_App_Watch_AppTests.swift
//  BoulderBikeRouter Watch App Watch AppTests
//
//  Created by MBP on 6/8/26.
//

import Testing
@testable import BoulderBikeRouter_Watch_App_Watch_App

struct BoulderBikeRouter_Watch_App_Watch_AppTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
        // Swift Testing Documentation
        // https://developer.apple.com/documentation/testing
    }

    @Test func watchNavigationDistanceFormatterUsesFeetForNearbyManeuvers() {
        #expect(WatchNavigationDistanceFormatter.shortDistance(30.48) == "100 ft")
    }

    @Test func watchNavigationDistanceFormatterUsesMilesForLongerDistances() {
        #expect(WatchNavigationDistanceFormatter.shortDistance(1609.34) == "1.0 mi")
    }

}
