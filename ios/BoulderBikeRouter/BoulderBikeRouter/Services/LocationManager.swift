import Foundation
import CoreLocation
import Combine

/// Delegate to handle updates from a location source.
protocol LocationProviderDelegate: AnyObject {
    func locationProvider(_ provider: LocationProvider, didUpdateLocation location: CLLocation)
    func locationProvider(_ provider: LocationProvider, didUpdateHeading heading: CLHeading)
    func locationProvider(_ provider: LocationProvider, didChangeAuthorization status: CLAuthorizationStatus)
    func locationProvider(_ provider: LocationProvider, didFailWithError error: Error)
}

/// Abstract location source interface allowing real GPS or route simulation.
protocol LocationProvider: AnyObject {
    var delegate: LocationProviderDelegate? { get set }
    var authorizationStatus: CLAuthorizationStatus { get }
    func requestAuthorization()
    func setBackgroundUpdatesEnabled(_ enabled: Bool)
    func startUpdating()
    func stopUpdating()
}

// MARK: - CoreLocation Real Provider

class CoreLocationProvider: NSObject, LocationProvider, CLLocationManagerDelegate {
    weak var delegate: LocationProviderDelegate?
    private let locationManager = CLLocationManager()
    private let canUseBackgroundLocation: Bool

    override init() {
        let env = ProcessInfo.processInfo.environment
        let isTesting = env.keys.contains { $0.contains("XCTest") || $0.contains("XCInject") } || NSClassFromString("XCTestCase") != nil
        let backgroundModes = Bundle.main.infoDictionary?["UIBackgroundModes"] as? [String]
        canUseBackgroundLocation = !isTesting && (backgroundModes?.contains("location") == true)

        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 2.0 // Update every 2 meters
        locationManager.headingFilter = 2.0 // Ignore tiny heading jitter
    }

    var authorizationStatus: CLAuthorizationStatus {
        locationManager.authorizationStatus
    }

    func requestAuthorization() {
        locationManager.requestWhenInUseAuthorization()
    }

    func setBackgroundUpdatesEnabled(_ enabled: Bool) {
        let shouldEnable = enabled && canUseBackgroundLocation
        locationManager.allowsBackgroundLocationUpdates = shouldEnable
        locationManager.showsBackgroundLocationIndicator = shouldEnable
    }

    func startUpdating() {
        locationManager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() {
            locationManager.startUpdatingHeading()
        }
    }

    func stopUpdating() {
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
    }

    // CLLocationManagerDelegate callbacks
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        delegate?.locationProvider(self, didUpdateLocation: location)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        delegate?.locationProvider(self, didUpdateHeading: newHeading)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        delegate?.locationProvider(self, didChangeAuthorization: manager.authorizationStatus)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        delegate?.locationProvider(self, didFailWithError: error)
    }
}

// MARK: - Simulated Heading Helper Class

class SimulatedHeading: CLHeading {
    private let _trueHeading: CLLocationDirection
    private let _magneticHeading: CLLocationDirection

    init(heading: CLLocationDirection) {
        self._trueHeading = heading
        self._magneticHeading = heading
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var trueHeading: CLLocationDirection {
        _trueHeading
    }

    override var magneticHeading: CLLocationDirection {
        _magneticHeading
    }

    override var headingAccuracy: CLLocationDirectionAccuracy {
        1.0
    }
}

// MARK: - Simulated Location Provider

class SimulatedLocationProvider: LocationProvider {
    weak var delegate: LocationProviderDelegate?
    var authorizationStatus: CLAuthorizationStatus = .authorizedWhenInUse

    private var coordinates: [CLLocationCoordinate2D] = []
    private var currentIndex: Int = 0
    private var timer: Timer?
    private var speedMultiplier: Double = 1.0 // 1x, 2x, 4x, etc.
    private let baseUpdateInterval: TimeInterval = 1.0 // 1 second ticks
    private let casualSpeedMps = 4.47 // 10 mph in m/s
    private var simulatedHeading: CLLocationDirection = 0.0
    private var headingInitialized = false
    private var compassDrift: CLLocationDirection = 0.0
    private let compassJitterDegrees = 1.5
    private let compassDriftStepDegrees = 0.15
    private let compassDriftMaxDegrees = 3.0
    private let compassFollowFactor = 0.35
    private let compassMaxStepDegrees = 12.0

    func setRoute(_ coords: [CLLocationCoordinate2D]) {
        self.coordinates = coords
        self.currentIndex = 0
        self.simulatedHeading = 0.0
        self.headingInitialized = false
        self.compassDrift = 0.0
    }

    func setSpeedMultiplier(_ multiplier: Double) {
        self.speedMultiplier = multiplier
        if timer != nil {
            stopUpdating()
            startUpdating()
        }
    }

    func requestAuthorization() {
        self.authorizationStatus = .authorizedWhenInUse
        delegate?.locationProvider(self, didChangeAuthorization: .authorizedWhenInUse)
    }

    func setBackgroundUpdatesEnabled(_ enabled: Bool) {}

    func startUpdating() {
        guard !coordinates.isEmpty else { return }
        timer = Timer.scheduledTimer(withTimeInterval: baseUpdateInterval / speedMultiplier, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func stopUpdating() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard currentIndex < coordinates.count else {
            stopUpdating()
            return
        }

        let coord = coordinates[currentIndex]
        let routeCourse = calculateRouteCourse(at: currentIndex)
        let headingVal = updateSimulatedHeading(toward: routeCourse)
        
        let location = CLLocation(
            coordinate: coord,
            altitude: 0,
            horizontalAccuracy: 5.0,
            verticalAccuracy: 5.0,
            course: headingVal,
            speed: casualSpeedMps,
            timestamp: Date()
        )

        delegate?.locationProvider(self, didUpdateLocation: location)

        // Send simulated heading
        let headingObj = SimulatedHeading(heading: headingVal)
        delegate?.locationProvider(self, didUpdateHeading: headingObj)

        currentIndex += 1
    }

    private func calculateRouteCourse(at index: Int) -> CLLocationDirection {
        guard coordinates.count >= 2 else { return simulatedHeading }

        let behindIndex = max(0, index - 1)
        let aheadIndex = min(coordinates.count - 1, index + 3)

        if behindIndex != aheadIndex {
            return bearing(from: coordinates[behindIndex], to: coordinates[aheadIndex])
        }

        if index > 0 {
            return bearing(from: coordinates[index - 1], to: coordinates[index])
        }

        return bearing(from: coordinates[index], to: coordinates[index + 1])
    }

    private func updateSimulatedHeading(toward routeCourse: CLLocationDirection) -> CLLocationDirection {
        compassDrift = clamp(
            compassDrift + Double.random(in: -compassDriftStepDegrees...compassDriftStepDegrees),
            min: -compassDriftMaxDegrees,
            max: compassDriftMaxDegrees
        )

        let compassNoise = Double.random(in: -compassJitterDegrees...compassJitterDegrees)
        let target = normalizeHeading(routeCourse + compassDrift + compassNoise)

        if !headingInitialized {
            simulatedHeading = target
            headingInitialized = true
            return simulatedHeading
        }

        let headingDiff = shortestAngleDiff(from: simulatedHeading, to: target)
        let step = clamp(
            headingDiff * compassFollowFactor,
            min: -compassMaxStepDegrees,
            max: compassMaxStepDegrees
        )
        simulatedHeading = normalizeHeading(simulatedHeading + step)
        return simulatedHeading
    }

    private func bearing(from pt1: CLLocationCoordinate2D, to pt2: CLLocationCoordinate2D) -> CLLocationDirection {
        let lat1 = pt1.latitude * .pi / 180.0
        let lat2 = pt2.latitude * .pi / 180.0
        let dLon = (pt2.longitude - pt1.longitude) * .pi / 180.0

        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let bearing = atan2(y, x) * 180.0 / .pi
        return (bearing + 360.0).truncatingRemainder(dividingBy: 360.0)
    }

    private func shortestAngleDiff(from: CLLocationDirection, to: CLLocationDirection) -> CLLocationDirection {
        var diff = to - from
        while diff > 180.0 { diff -= 360.0 }
        while diff < -180.0 { diff += 360.0 }
        return diff
    }

    private func normalizeHeading(_ heading: CLLocationDirection) -> CLLocationDirection {
        (heading + 360.0).truncatingRemainder(dividingBy: 360.0)
    }

    private func clamp(_ value: Double, min: Double, max: Double) -> Double {
        Swift.max(min, Swift.min(max, value))
    }
}

// MARK: - Location Manager Wrapper

@Observable
class LocationManager: LocationProviderDelegate {
    var currentLocation: CLLocation?
    var currentHeading: Double = 0.0
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    
    // Low-pass filter variables for heading stabilization
    private var headingX: Double = 0.0
    private var headingY: Double = 0.0
    private var hasInitializedHeading: Bool = false
    private let headingAlpha: Double = 0.20 // Smoothing factor (lower = smoother, higher = more responsive)
    
    var isSimulating: Bool = false {
        didSet {
            setupProvider()
        }
    }

    private var activeProvider: LocationProvider?
    private let realProvider = CoreLocationProvider()
    private let simulatedProvider = SimulatedLocationProvider()
    private var backgroundUpdatesEnabled = false

    init() {
        setupProvider()
    }

    private func setupProvider() {
        activeProvider?.stopUpdating()
        
        if isSimulating {
            activeProvider = simulatedProvider
        } else {
            activeProvider = realProvider
        }
        
        activeProvider?.delegate = self
        activeProvider?.setBackgroundUpdatesEnabled(backgroundUpdatesEnabled)
        self.authorizationStatus = activeProvider?.authorizationStatus ?? .notDetermined
    }

    func requestAuthorization() {
        activeProvider?.requestAuthorization()
    }

    func setBackgroundNavigationEnabled(_ enabled: Bool) {
        backgroundUpdatesEnabled = enabled
        realProvider.setBackgroundUpdatesEnabled(enabled)
        simulatedProvider.setBackgroundUpdatesEnabled(enabled)
    }

    func startUpdating() {
        setupProvider()
        activeProvider?.startUpdating()
    }

    func stopUpdating() {
        activeProvider?.stopUpdating()
    }

    func setSimulationRoute(_ coords: [CLLocationCoordinate2D]) {
        simulatedProvider.setRoute(coords)
    }

    func setSimulationSpeed(_ multiplier: Double) {
        simulatedProvider.setSpeedMultiplier(multiplier)
    }

    // LocationProviderDelegate Methods
    func locationProvider(_ provider: LocationProvider, didUpdateLocation location: CLLocation) {
        Task { @MainActor in
            self.currentLocation = location
        }
    }

    func locationProvider(_ provider: LocationProvider, didUpdateHeading heading: CLHeading) {
        let rawHeading = heading.trueHeading >= 0 ? heading.trueHeading : heading.magneticHeading
        guard rawHeading >= 0 else { return }
        
        Task { @MainActor in
            let rad = rawHeading * .pi / 180.0
            let x = cos(rad)
            let y = sin(rad)
            
            if !self.hasInitializedHeading {
                self.headingX = x
                self.headingY = y
                self.hasInitializedHeading = true
                self.currentHeading = rawHeading
            } else {
                // Vector-based low-pass filter
                self.headingX = (1.0 - self.headingAlpha) * self.headingX + self.headingAlpha * x
                self.headingY = (1.0 - self.headingAlpha) * self.headingY + self.headingAlpha * y
                
                var blendedRad = atan2(self.headingY, self.headingX) * 180.0 / .pi
                if blendedRad < 0 {
                    blendedRad += 360.0
                }
                self.currentHeading = blendedRad
            }
        }
    }

    func locationProvider(_ provider: LocationProvider, didChangeAuthorization status: CLAuthorizationStatus) {
        Task { @MainActor in
            self.authorizationStatus = status
        }
    }

    func locationProvider(_ provider: LocationProvider, didFailWithError error: Error) {
        print("Location manager error: \(error.localizedDescription)")
    }
}
