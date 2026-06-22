import Foundation
import Security

struct GuestCredential {
    let id: String
    let token: String
}

enum GuestCredentialStore {
    private static let idKey = "guest_installation_id"
    private static let keychainService = "com.bikingboulder.BoulderBikeRouter.guest"
    private static let keychainAccount = "guest_token"
    private static let lock = NSLock()

    static func apply(to request: inout URLRequest) {
        let value = credential()
        request.setValue(value.id, forHTTPHeaderField: "X-Guest-Id")
        request.setValue(value.token, forHTTPHeaderField: "X-Guest-Token")
    }

    static func credential() -> GuestCredential {
        lock.lock()
        defer { lock.unlock() }

        let defaults = UserDefaults.standard
        let id: String
        if let existing = defaults.string(forKey: idKey), !existing.isEmpty {
            id = existing
        } else {
            id = UUID().uuidString.lowercased()
            defaults.set(id, forKey: idKey)
        }

        if let token = readToken(service: keychainService, account: keychainAccount) {
            return GuestCredential(id: id, token: token)
        }

        let token = makeToken()
        saveToken(token, service: keychainService, account: keychainAccount)
        return GuestCredential(id: id, token: token)
    }

    private static func makeToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            return UUID().uuidString.replacingOccurrences(of: "-", with: "")
                + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

final class AuthSessionStore {
    static let shared = AuthSessionStore()

    private let tokenService = "com.bikingboulder.BoulderBikeRouter.auth"
    private let tokenAccount = "pocketbase_token"
    private let legacyTokenKey = "pocketbase_token"
    private let userIdKey = "logged_in_user_id"
    private let emailKey = "logged_in_user_email"
    private let lock = NSLock()

    private init() {}

    var token: String? {
        lock.lock()
        defer { lock.unlock() }
        return migratedToken()
    }

    var userId: String? {
        UserDefaults.standard.string(forKey: userIdKey)
    }

    var email: String? {
        UserDefaults.standard.string(forKey: emailKey)
    }

    var isAuthenticated: Bool {
        token != nil
    }

    var isSessionExpired: Bool {
        token == nil && userId != nil
    }

    func applyAuthorization(to request: inout URLRequest) {
        guard let token else { return }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    func save(token: String, userId: String, email: String?) {
        lock.lock()
        defer { lock.unlock() }
        saveToken(token, service: tokenService, account: tokenAccount)
        UserDefaults.standard.removeObject(forKey: legacyTokenKey)
        UserDefaults.standard.set(userId, forKey: userIdKey)
        if let email {
            UserDefaults.standard.set(email, forKey: emailKey)
        } else {
            UserDefaults.standard.removeObject(forKey: emailKey)
        }
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        deleteToken(service: tokenService, account: tokenAccount)
        UserDefaults.standard.removeObject(forKey: legacyTokenKey)
        UserDefaults.standard.removeObject(forKey: userIdKey)
        UserDefaults.standard.removeObject(forKey: emailKey)
    }

    private func migratedToken() -> String? {
        if let token = readToken(service: tokenService, account: tokenAccount) {
            return token
        }
        guard let legacyToken = UserDefaults.standard.string(forKey: legacyTokenKey),
              !legacyToken.isEmpty else {
            return nil
        }
        saveToken(legacyToken, service: tokenService, account: tokenAccount)
        UserDefaults.standard.removeObject(forKey: legacyTokenKey)
        return legacyToken
    }
}

private func readToken(service: String, account: String) -> String? {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account,
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne
    ]
    var item: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
          let data = item as? Data else {
        return nil
    }
    return String(data: data, encoding: .utf8)
}

private func saveToken(_ token: String, service: String, account: String) {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account
    ]
    SecItemDelete(query as CFDictionary)
    var item = query
    item[kSecValueData as String] = Data(token.utf8)
    item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    SecItemAdd(item as CFDictionary, nil)
}

private func deleteToken(service: String, account: String) {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account
    ]
    SecItemDelete(query as CFDictionary)
}
