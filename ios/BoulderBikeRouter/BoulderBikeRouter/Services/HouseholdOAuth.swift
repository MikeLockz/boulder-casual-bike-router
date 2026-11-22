import AuthenticationServices
import CryptoKit
import Foundation
import Security
import UIKit

struct HouseholdAuthMethods: Decodable {
    struct OAuth2: Decodable {
        struct Provider: Decodable {
            let name: String
            let authURL: String
        }
        let providers: [Provider]
    }
    let oauth2: OAuth2
}

enum HouseholdOAuthRequest {
    static let redirectURI = "com.lockdev.boulder:/oauth2redirect"

    static func randomToken() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw APIError.serverError("Secure sign-in could not be started.")
        }
        return base64URL(Data(bytes))
    }

    static func base64URL(_ bytes: Data) -> String {
        bytes.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    static func authorizationURL(providerURL: String, state: String, verifier: String) throws -> URL {
        guard var components = URLComponents(string: providerURL),
              components.scheme == "https", components.host == "authelia.lockdev.com",
              components.user == nil, components.password == nil else {
            throw APIError.invalidURL
        }
        let replacements = [
            "redirect_uri": redirectURI, "state": state,
            "scope": "openid profile email groups",
            "code_challenge": base64URL(Data(SHA256.hash(data: Data(verifier.utf8)))),
            "code_challenge_method": "S256"
        ]
        var items = (components.queryItems ?? []).filter { replacements[$0.name] == nil }
        items += replacements.map { URLQueryItem(name: $0.key, value: $0.value) }
        components.queryItems = items
        guard let result = components.url else { throw APIError.invalidURL }
        return result
    }

    static func authorizationCode(callback: URL, expectedState: String) throws -> String {
        guard callback.scheme == "com.lockdev.boulder", callback.host == nil,
              callback.path == "/oauth2redirect",
              let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems,
              items.filter({ $0.name == "state" }).count == 1,
              items.first(where: { $0.name == "state" })?.value == expectedState,
              !items.contains(where: { $0.name == "error" }),
              items.filter({ $0.name == "code" }).count == 1,
              let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            throw APIError.serverError("The sign-in response could not be verified. Please try again.")
        }
        return code
    }
}

@MainActor
final class HouseholdOAuth: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = HouseholdOAuth()
    private var session: ASWebAuthenticationSession?
    private var pending: CheckedContinuation<URL, Error>?
    private var deadline: Task<Void, Never>?
    private var activeAttempt: UUID?

    func authenticate(url: URL) async throws -> URL {
        guard pending == nil else { throw APIError.serverError("A sign-in is already in progress.") }
        let attemptID = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending = continuation
                activeAttempt = attemptID
                let attempt = ASWebAuthenticationSession(url: url, callbackURLScheme: "com.lockdev.boulder") { url, error in
                    Task { @MainActor in
                        if let url { self.finish(.success(url), attempt: attemptID) }
                        else { self.finish(.failure(error ?? APIError.unauthorized), attempt: attemptID) }
                    }
                }
                attempt.presentationContextProvider = self
                session = attempt
                deadline = Task { @MainActor in
                    do { try await Task.sleep(for: .seconds(180)) }
                    catch { return }
                    self.finish(.failure(APIError.serverError("Sign-in timed out. Please try again.")), attempt: attemptID)
                }
                if !attempt.start() { finish(.failure(APIError.serverError("Unable to open sign-in.")), attempt: attemptID) }
            }
        } onCancel: {
            Task { @MainActor in self.finish(.failure(CancellationError()), attempt: attemptID) }
        }
    }

    private func finish(_ result: Result<URL, Error>, attempt: UUID) {
        guard activeAttempt == attempt, let continuation = pending else { return }
        pending = nil
        activeAttempt = nil
        deadline?.cancel()
        deadline = nil
        session?.cancel()
        session = nil
        continuation.resume(with: result)
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}
