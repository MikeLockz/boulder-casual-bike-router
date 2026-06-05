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
    private var baseURLLabel: String = "http://localhost:8081" // Default local nginx mapping port

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
}
