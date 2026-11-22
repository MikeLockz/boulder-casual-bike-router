import Foundation
import Testing
@testable import BoulderBikeRouter

struct HouseholdOAuthTests {
    @Test func bindsPKCEToAttemptAndExactRedirect() throws {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        let url = try HouseholdOAuthRequest.authorizationURL(
            providerURL: "https://authelia.lockdev.com/api/oidc/authorization?client_id=boulder&state=old&redirect_uri=old",
            state: "attempt", verifier: verifier)
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.filter { $0.name == "state" }.map(\.value) == ["attempt"])
        #expect(items.first { $0.name == "redirect_uri" }?.value == HouseholdOAuthRequest.redirectURI)
        #expect(items.first { $0.name == "code_challenge" }?.value == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        #expect(items.first { $0.name == "code_challenge_method" }?.value == "S256")
    }

    @Test func rejectsUntrustedProviderAndAmbiguousCallbacks() throws {
        #expect(throws: (any Error).self) {
            try HouseholdOAuthRequest.authorizationURL(providerURL: "https://example.com/", state: "x", verifier: "y")
        }
        for value in [
            "com.lockdev.boulder:/oauth2redirect?state=wrong&code=secret",
            "com.lockdev.boulder:/oauth2redirect?state=ok&state=other&code=secret",
            "com.lockdev.boulder:/oauth2redirect?state=ok&code=one&code=two",
            "com.lockdev.boulder://wrong/oauth2redirect?state=ok&code=secret",
            "com.lockdev.boulder:/other?state=ok&code=secret",
            "com.lockdev.boulder:/oauth2redirect?state=ok&error=access_denied"
        ] {
            #expect(throws: (any Error).self) {
                try HouseholdOAuthRequest.authorizationCode(callback: URL(string: value)!, expectedState: "ok")
            }
        }
        #expect(try HouseholdOAuthRequest.authorizationCode(
            callback: URL(string: "com.lockdev.boulder:/oauth2redirect?state=ok&code=valid")!, expectedState: "ok") == "valid")
    }
}
