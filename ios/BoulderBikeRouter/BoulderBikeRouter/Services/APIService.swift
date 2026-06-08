import Foundation
import CoreLocation

/// Errors that can occur when calling the Biking Boulder routing API.
enum APIError: Error, LocalizedError {
    case invalidURL
    case serverError(String)
    case decodingError(Error)
    case requestFailed(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The API URL is invalid."
        case .serverError(let message):
            return "Server error: \(message)"
        case .decodingError(let error):
            return "Failed to decode server response: \(error.localizedDescription)"
        case .requestFailed(let error):
            return "Network request failed: \(error.localizedDescription)"
        }
    }
}

private struct OfficialLoopFeatureCollection: Decodable {
    let features: [OfficialLoopFeature]
}

private struct OfficialLoopFeature: Decodable {
    let geometry: OfficialLoopGeometry
}

private struct OfficialLoopGeometry: Decodable {
    let type: String
    let coordinates: [[[Double]]]
}

/// Service that manages connection to the Biking Boulder backend service.
class APIService {
    private var baseURLLabel: String = {
        #if targetEnvironment(simulator)
        // Simulator runs on the developer machine, so localhost works
        return "http://localhost:8081"
        #else
        // Physical device (use the production host domain) or production build
        return "https://boulder.lockdev.com"
        #endif
    }()

    /// Set a custom base URL (e.g. localhost for simulator testing)
    func setBaseURL(_ urlString: String) {
        self.baseURLLabel = urlString
    }

    /// Retrieve the current base URL
    func getBaseURL() -> String {
        return baseURLLabel
    }

    /// Fetch computed route based on start/end coordinates, waypoints and routing weights
    func fetchRoute(request: RouteRequest) async throws -> RouteResponse {
        guard let baseURL = URL(string: baseURLLabel),
              let routeURL = URL(string: "/api/route", relativeTo: baseURL) else {
            throw APIError.invalidURL
        }

        var urlRequest = URLRequest(url: routeURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let encoder = JSONEncoder()
            urlRequest.httpBody = try encoder.encode(request)
        } catch {
            throw APIError.requestFailed(error)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: urlRequest)
        } catch {
            throw APIError.requestFailed(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.serverError("Invalid response type")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError("Invalid HTTP status code: \(httpResponse.statusCode)")
        }

        do {
            let decoder = JSONDecoder()
            let routeResponse = try decoder.decode(RouteResponse.self, from: data)
            if let apiError = routeResponse.error {
                throw APIError.serverError(apiError)
            }
            return routeResponse
        } catch {
            throw APIError.decodingError(error)
        }
    }

    /// Fetch an official Boulder loop GeoJSON and convert it into the app's route response shape.
    func fetchOfficialLoopRoute(routeType: String) async throws -> RouteResponse {
        guard routeType == "b180" || routeType == "b360",
              let baseURL = URL(string: baseURLLabel),
              let routeURL = URL(string: "/official_\(routeType).json", relativeTo: baseURL) else {
            throw APIError.invalidURL
        }

        var urlRequest = URLRequest(url: routeURL)
        urlRequest.httpMethod = "GET"

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: urlRequest)
        } catch {
            throw APIError.requestFailed(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.serverError("Invalid response type")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError("Invalid HTTP status code: \(httpResponse.statusCode)")
        }

        do {
            let geojson = try JSONDecoder().decode(OfficialLoopFeatureCollection.self, from: data)
            return makeOfficialLoopRouteResponse(from: geojson, routeType: routeType)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    private func makeOfficialLoopRouteResponse(from geojson: OfficialLoopFeatureCollection, routeType: String) -> RouteResponse {
        let name = routeType == "b180" ? "Boulder Loops B-180" : "Boulder Loops B-360"
        var segments: [RouteSegment] = []
        var totalLength = 0.0

        for feature in geojson.features {
            let lines: [[[Double]]]
            if feature.geometry.type == "MultiLineString" {
                lines = feature.geometry.coordinates
            } else if feature.geometry.type == "LineString" {
                lines = [feature.geometry.coordinates.flatMap { $0 }]
            } else {
                lines = []
            }

            for line in lines {
                guard line.count >= 2 else { continue }
                for index in 0..<(line.count - 1) {
                    let from = line[index]
                    let to = line[index + 1]
                    guard from.count >= 2, to.count >= 2 else { continue }

                    let fromLocation = CLLocation(latitude: from[1], longitude: from[0])
                    let toLocation = CLLocation(latitude: to[1], longitude: to[0])
                    let length = fromLocation.distance(from: toLocation)
                    totalLength += length

                    segments.append(RouteSegment(
                        coords: [[from[1], from[0]], [to[1], to[0]]],
                        type: "separated_path",
                        name: name,
                        length: length,
                        multiplier: 1.0,
                        bikestress: "None",
                        offstreetType: "official_loop",
                        bicyclesAllowed: "Yes",
                        ebikeAllowed: "Yes"
                    ))
                }
            }
        }

        return RouteResponse(segments: segments, totalLengthMeters: totalLength, totalWeight: totalLength, error: nil)
    }

    /// Fetch the list of playgrounds with location data
    func fetchPlaygrounds() async throws -> [Playground] {
        guard let baseURL = URL(string: baseURLLabel),
              let playgroundsURL = URL(string: "/api/playgrounds", relativeTo: baseURL) else {
            throw APIError.invalidURL
        }

        var urlRequest = URLRequest(url: playgroundsURL)
        urlRequest.httpMethod = "GET"

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: urlRequest)
        } catch {
            throw APIError.requestFailed(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.serverError("Invalid response type")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError("Invalid HTTP status code: \(httpResponse.statusCode)")
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode([Playground].self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    /// Fetch place autocomplete suggestions for route planning.
    func fetchPlaceSuggestions(query: String, limit: Int = 8) async throws -> [PlaceSuggestion] {
        guard let baseURL = URL(string: baseURLLabel),
              let autocompleteURL = URL(string: "/api/autocomplete", relativeTo: baseURL),
              var components = URLComponents(url: autocompleteURL, resolvingAgainstBaseURL: true) else {
            throw APIError.invalidURL
        }

        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: String(limit))
        ]

        guard let url = components.url else {
            throw APIError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: urlRequest)
        } catch {
            throw APIError.requestFailed(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.serverError("Invalid response type")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError("Invalid HTTP status code: \(httpResponse.statusCode)")
        }

        do {
            return try JSONDecoder().decode([PlaceSuggestion].self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    /// Fetch the full dynamic app configurations (presets, sliders meta)
    func fetchConfig() async throws -> BackendConfig {
        guard let baseURL = URL(string: baseURLLabel),
              let configURL = URL(string: "/api/config", relativeTo: baseURL) else {
            throw APIError.invalidURL
        }

        var urlRequest = URLRequest(url: configURL)
        urlRequest.httpMethod = "GET"

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: urlRequest)
        } catch {
            throw APIError.requestFailed(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.serverError("Invalid response type")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError("Invalid HTTP status code: \(httpResponse.statusCode)")
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(BackendConfig.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    /// Start logging a new navigation route telemetry session.
    func startNavigation(request: NavigationStartRequest) async throws -> String {
        guard let baseURL = URL(string: baseURLLabel),
              let startURL = URL(string: "/api/navigation/start", relativeTo: baseURL) else {
            throw APIError.invalidURL
        }

        var urlRequest = URLRequest(url: startURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let token = UserDefaults.standard.string(forKey: "pocketbase_token") {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let encoder = JSONEncoder()
            urlRequest.httpBody = try encoder.encode(request)
        } catch {
            throw APIError.requestFailed(error)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: urlRequest)
        } catch {
            throw APIError.requestFailed(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.serverError("Invalid response type")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError("Invalid HTTP status code: \(httpResponse.statusCode)")
        }

        do {
            let startResponse = try JSONDecoder().decode(NavigationStartResponse.self, from: data)
            return startResponse.routeId
        } catch {
            throw APIError.decodingError(error)
        }
    }

    /// Send a coordinates telemetry tick update to the backend.
    func sendLocationTick(routeId: String, request: NavigationTickRequest) async throws {
        guard let baseURL = URL(string: baseURLLabel),
              let tickURL = URL(string: "/api/navigation/\(routeId)/tick", relativeTo: baseURL) else {
            throw APIError.invalidURL
        }

        var urlRequest = URLRequest(url: tickURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let encoder = JSONEncoder()
            urlRequest.httpBody = try encoder.encode(request)
        } catch {
            throw APIError.requestFailed(error)
        }

        let response: URLResponse
        do {
            (_, response) = try await URLSession.shared.data(for: urlRequest)
        } catch {
            throw APIError.requestFailed(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.serverError("Invalid response type")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError("Invalid HTTP status code: \(httpResponse.statusCode)")
        }
    }

    /// End route navigation and send final session exit metadata.
    func endNavigation(routeId: String, request: NavigationEndRequest) async throws {
        guard let baseURL = URL(string: baseURLLabel),
              let endURL = URL(string: "/api/navigation/\(routeId)/end", relativeTo: baseURL) else {
            throw APIError.invalidURL
        }

        var urlRequest = URLRequest(url: endURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let encoder = JSONEncoder()
            urlRequest.httpBody = try encoder.encode(request)
        } catch {
            throw APIError.requestFailed(error)
        }

        let response: URLResponse
        do {
            (_, response) = try await URLSession.shared.data(for: urlRequest)
        } catch {
            throw APIError.requestFailed(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.serverError("Invalid response type")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError("Invalid HTTP status code: \(httpResponse.statusCode)")
        }
    }

    /// Retrieve previous routes navigation history log from the server.
    func fetchHistory(routeIds: [String]? = nil) async throws -> [PastRoute] {
        guard let baseURL = URL(string: baseURLLabel),
              let historyBaseURL = URL(string: "/api/navigation/history", relativeTo: baseURL) else {
            throw APIError.invalidURL
        }
        
        var components = URLComponents(url: historyBaseURL, resolvingAgainstBaseURL: true)
        if let routeIds = routeIds, !routeIds.isEmpty {
            components?.queryItems = [URLQueryItem(name: "route_ids", value: routeIds.joined(separator: ","))]
        }
        
        guard let historyURL = components?.url else {
            throw APIError.invalidURL
        }

        var urlRequest = URLRequest(url: historyURL)
        urlRequest.httpMethod = "GET"
        
        if let token = UserDefaults.standard.string(forKey: "pocketbase_token") {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: urlRequest)
        } catch {
            throw APIError.requestFailed(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.serverError("Invalid response type")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError("Invalid HTTP status code: \(httpResponse.statusCode)")
        }

        do {
            return try JSONDecoder().decode([PastRoute].self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    /// Retrieve authenticated route tuning profiles from the backend.
    func fetchRouteTuningProfiles() async throws -> [RouteTuningProfile] {
        guard let baseURL = URL(string: baseURLLabel),
              let profilesURL = URL(string: "/api/route-tuning-profiles", relativeTo: baseURL) else {
            throw APIError.invalidURL
        }

        var urlRequest = URLRequest(url: profilesURL)
        urlRequest.httpMethod = "GET"
        if let token = UserDefaults.standard.string(forKey: "pocketbase_token") {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: urlRequest)
        } catch {
            throw APIError.requestFailed(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.serverError("Invalid response type")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError("Invalid HTTP status code: \(httpResponse.statusCode)")
        }

        do {
            return try JSONDecoder().decode([RouteTuningProfile].self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    func createRouteTuningProfile(_ profile: RouteTuningProfile) async throws -> RouteTuningProfile {
        try await sendRouteTuningProfile(profile, method: "POST", profileId: nil)
    }

    func updateRouteTuningProfile(_ profile: RouteTuningProfile, serverId: String) async throws -> RouteTuningProfile {
        try await sendRouteTuningProfile(profile, method: "PATCH", profileId: serverId)
    }

    func deleteRouteTuningProfile(serverId: String) async throws {
        guard let baseURL = URL(string: baseURLLabel),
              let profileURL = URL(string: "/api/route-tuning-profiles/\(serverId)", relativeTo: baseURL) else {
            throw APIError.invalidURL
        }

        var urlRequest = URLRequest(url: profileURL)
        urlRequest.httpMethod = "DELETE"
        if let token = UserDefaults.standard.string(forKey: "pocketbase_token") {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (_, response): (Data, URLResponse)
        do {
            (_, response) = try await URLSession.shared.data(for: urlRequest)
        } catch {
            throw APIError.requestFailed(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.serverError("Invalid response type")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError("Invalid HTTP status code: \(httpResponse.statusCode)")
        }
    }

    private func sendRouteTuningProfile(_ profile: RouteTuningProfile, method: String, profileId: String?) async throws -> RouteTuningProfile {
        let path = profileId.map { "/api/route-tuning-profiles/\($0)" } ?? "/api/route-tuning-profiles"
        guard let baseURL = URL(string: baseURLLabel),
              let profileURL = URL(string: path, relativeTo: baseURL) else {
            throw APIError.invalidURL
        }

        var urlRequest = URLRequest(url: profileURL)
        urlRequest.httpMethod = method
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = UserDefaults.standard.string(forKey: "pocketbase_token") {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            urlRequest.httpBody = try JSONEncoder().encode(profile)
        } catch {
            throw APIError.requestFailed(error)
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: urlRequest)
        } catch {
            throw APIError.requestFailed(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.serverError("Invalid response type")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError("Invalid HTTP status code: \(httpResponse.statusCode)")
        }

        do {
            return try JSONDecoder().decode(RouteTuningProfile.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    func fetchHomeLocation() async throws -> HomeLocation? {
        guard let baseURL = URL(string: baseURLLabel),
              let homeURL = URL(string: "/api/settings/home", relativeTo: baseURL) else {
            throw APIError.invalidURL
        }

        var urlRequest = URLRequest(url: homeURL)
        urlRequest.httpMethod = "GET"
        if let token = UserDefaults.standard.string(forKey: "pocketbase_token") {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: urlRequest)
        } catch {
            throw APIError.requestFailed(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.serverError("Invalid response type")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError("Invalid HTTP status code: \(httpResponse.statusCode)")
        }

        do {
            return try JSONDecoder().decode(HomeLocationResponse.self, from: data).home
        } catch {
            throw APIError.decodingError(error)
        }
    }

    func saveHomeLocation(_ coordinate: CLLocationCoordinate2D) async throws -> HomeLocation? {
        guard let baseURL = URL(string: baseURLLabel),
              let homeURL = URL(string: "/api/settings/home", relativeTo: baseURL) else {
            throw APIError.invalidURL
        }

        var urlRequest = URLRequest(url: homeURL)
        urlRequest.httpMethod = "PUT"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = UserDefaults.standard.string(forKey: "pocketbase_token") {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            urlRequest.httpBody = try JSONEncoder().encode(HomeLocationRequest(lat: coordinate.latitude, lng: coordinate.longitude))
        } catch {
            throw APIError.requestFailed(error)
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: urlRequest)
        } catch {
            throw APIError.requestFailed(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.serverError("Invalid response type")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError("Invalid HTTP status code: \(httpResponse.statusCode)")
        }

        do {
            return try JSONDecoder().decode(HomeLocationResponse.self, from: data).home
        } catch {
            throw APIError.decodingError(error)
        }
    }

    func deleteHomeLocation() async throws {
        guard let baseURL = URL(string: baseURLLabel),
              let homeURL = URL(string: "/api/settings/home", relativeTo: baseURL) else {
            throw APIError.invalidURL
        }

        var urlRequest = URLRequest(url: homeURL)
        urlRequest.httpMethod = "DELETE"
        if let token = UserDefaults.standard.string(forKey: "pocketbase_token") {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (_, response): (Data, URLResponse)
        do {
            (_, response) = try await URLSession.shared.data(for: urlRequest)
        } catch {
            throw APIError.requestFailed(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.serverError("Invalid response type")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError("Invalid HTTP status code: \(httpResponse.statusCode)")
        }
    }

    /// Retrieve full details of a specific route, including all GPS ticks.
    func fetchRouteDetails(routeId: String) async throws -> DetailedRouteResponse {
        guard let baseURL = URL(string: baseURLLabel),
              let detailURL = URL(string: "/api/navigation/\(routeId)", relativeTo: baseURL) else {
            throw APIError.invalidURL
        }

        var urlRequest = URLRequest(url: detailURL)
        urlRequest.httpMethod = "GET"

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: urlRequest)
        } catch {
            throw APIError.requestFailed(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.serverError("Invalid response type")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError("Invalid HTTP status code: \(httpResponse.statusCode)")
        }

        do {
            return try JSONDecoder().decode(DetailedRouteResponse.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    func updateHistoryRoute(routeId: String, request: RouteHistoryUpdateRequest) async throws -> PastRoute {
        guard let baseURL = URL(string: baseURLLabel),
              let routeURL = URL(string: "/api/navigation/\(routeId)", relativeTo: baseURL) else {
            throw APIError.invalidURL
        }

        var urlRequest = URLRequest(url: routeURL)
        urlRequest.httpMethod = "PATCH"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = UserDefaults.standard.string(forKey: "pocketbase_token") {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            urlRequest.httpBody = try JSONEncoder().encode(request)
        } catch {
            throw APIError.requestFailed(error)
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: urlRequest)
        } catch {
            throw APIError.requestFailed(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.serverError("Invalid response type")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError("Invalid HTTP status code: \(httpResponse.statusCode)")
        }

        do {
            return try JSONDecoder().decode(PastRoute.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    func deleteHistoryRoute(routeId: String) async throws {
        guard let baseURL = URL(string: baseURLLabel),
              let routeURL = URL(string: "/api/navigation/\(routeId)", relativeTo: baseURL) else {
            throw APIError.invalidURL
        }

        var urlRequest = URLRequest(url: routeURL)
        urlRequest.httpMethod = "DELETE"
        if let token = UserDefaults.standard.string(forKey: "pocketbase_token") {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (_, response): (Data, URLResponse)
        do {
            (_, response) = try await URLSession.shared.data(for: urlRequest)
        } catch {
            throw APIError.requestFailed(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.serverError("Invalid response type")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError("Invalid HTTP status code: \(httpResponse.statusCode)")
        }
    }

    /// Sign in to PocketBase using email (identity) and password
    func signIn(email: String, password: String) async throws -> AuthResponse {
        guard let baseURL = URL(string: baseURLLabel),
              let authURL = URL(string: "/pb/api/collections/users/auth-with-password", relativeTo: baseURL) else {
            throw APIError.invalidURL
        }

        var urlRequest = URLRequest(url: authURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "identity": email,
            "password": password
        ]

        do {
            urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw APIError.requestFailed(error)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: urlRequest)
        } catch {
            throw APIError.requestFailed(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.serverError("Invalid response")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw parsePBError(data: data, httpResponse: httpResponse)
        }

        do {
            return try JSONDecoder().decode(AuthResponse.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    /// Create a new user account in PocketBase
    func signUp(email: String, password: String) async throws {
        guard let baseURL = URL(string: baseURLLabel),
              let registerURL = URL(string: "/pb/api/collections/users/records", relativeTo: baseURL) else {
            throw APIError.invalidURL
        }

        var urlRequest = URLRequest(url: registerURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "email": email,
            "password": password,
            "passwordConfirm": password,
            "emailVisibility": true
        ]

        do {
            urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw APIError.requestFailed(error)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: urlRequest)
        } catch {
            throw APIError.requestFailed(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.serverError("Invalid response")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw parsePBError(data: data, httpResponse: httpResponse)
        }
    }

    private func parsePBError(data: Data, httpResponse: HTTPURLResponse) -> Error {
        if let pbError = try? JSONDecoder().decode(PocketBaseError.self, from: data) {
            var details = [String]()
            if let dataDict = pbError.data {
                for (key, detail) in dataDict {
                    details.append("\(key): \(detail.message)")
                }
            }
            let detailsStr = details.joined(separator: ", ")
            let msg = detailsStr.isEmpty ? pbError.message : "\(pbError.message) (\(detailsStr))"
            return APIError.serverError(msg)
        }
        return APIError.serverError("Server returned status \(httpResponse.statusCode)")
    }
}
