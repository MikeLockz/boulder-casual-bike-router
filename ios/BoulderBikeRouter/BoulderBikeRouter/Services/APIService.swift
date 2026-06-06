import Foundation

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

/// Service that manages connection to the Biking Boulder backend service.
actor APIService {
    private var baseURLLabel: String = {
        #if targetEnvironment(simulator)
        // Simulator runs on the developer machine, so localhost works
        return "http://localhost:8081"
        #else
        // Physical device (use the host runner IP on the local network) or production build
        return "http://192.168.1.44:8081"
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

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError("Invalid HTTP status code")
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

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError("Invalid HTTP status code")
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode([Playground].self, from: data)
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

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError("Invalid HTTP status code")
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

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError("Invalid HTTP status code")
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

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError("Invalid HTTP status code")
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

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError("Invalid HTTP status code")
        }
    }

    /// Retrieve previous routes navigation history log from the server.
    func fetchHistory(routeIds: [String]? = nil) async throws -> [PastRoute] {
        guard let baseURL = URL(string: baseURLLabel) else {
            throw APIError.invalidURL
        }
        
        var components = URLComponents(url: baseURL.appendingPathComponent("/api/navigation/history"), resolvingAgainstBaseURL: true)
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

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError("Invalid HTTP status code")
        }

        do {
            return try JSONDecoder().decode([PastRoute].self, from: data)
        } catch {
            throw APIError.decodingError(error)
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

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError("Invalid HTTP status code")
        }

        do {
            return try JSONDecoder().decode(DetailedRouteResponse.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }
}
